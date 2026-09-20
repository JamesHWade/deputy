# Runtime binding for host-scheduled jobs. Persistence stays in agent-job.R;
# execution stays in the ordinary governed Agent kernel.
job_runtime_abort <- function(message) {
  abort_deputy(message, class = "job_error")
}

job_agents <- function(agent) {
  if (!inherits(agent, "Agent") || inherits(agent, "LeadAgent")) {
    job_runtime_abort(
      "A job requires an ordinary Agent or a configured graph root."
    )
  }
  private <- agent$.__enclos_env__$private
  if (!is.null(private$.conversation_owner)) {
    job_runtime_abort("A retained child cannot become an independent job.")
  }
  tree <- private$.delegation_tree
  if (is.null(tree)) {
    if (length(private$owned_conversations)) {
      job_runtime_abort(
        "Durable child ownership requires an explicit agent graph."
      )
    }
    return(list(root = agent))
  }
  if (!identical(delegation_tree_root(tree), agent)) {
    job_runtime_abort("Only the graph root can own a job.")
  }
  c(list(root = agent), tree$agents)
}

job_node_manifest <- function(agent) {
  private <- agent$.__enclos_env__$private
  if (isTRUE(private$run_active) || length(private$active_subagents)) {
    job_runtime_abort("Create and bind jobs only while every Agent is idle.")
  }
  if (length(private$.fallback_chats)) {
    job_runtime_abort(
      "Jobs currently require one configured provider per Agent."
    )
  }
  tools <- agent$get_tools()
  if (any(vapply(tools, inherits, logical(1), "ellmer::ToolBuiltIn"))) {
    job_runtime_abort(
      "Provider-native tools cannot bind durable job governance and effect records."
    )
  }
  policy <- S7::props(agent$context_policy)
  policy$offload_dir <- NULL
  policy$summary_fallback_chats <- lapply(
    policy$summary_fallback_chats,
    function(chat) {
      list(model = chat$get_model(), provider = chat$provider()$name)
    }
  )
  turns <- list(
    transcript = agent$get_turns(),
    context = agent$get_context_turns()
  )
  if (!observation_payload_fits(turns, 16 * 1024^2)) {
    job_runtime_abort(
      "Job source context exceeds the 16 MiB admission ceiling."
    )
  }
  records <- lapply(turns, approval_record_turns)
  list(
    agent_id = agent$agent_id,
    session_id = agent$session_id(),
    agent_name = agent$agent_name,
    model = agent$get_model(),
    provider = agent$provider()$name,
    system_prompt = agent$get_system_prompt(),
    working_dir = agent$working_dir,
    run_context = agent$run_context,
    tools = lapply(tools, approval_tool_fingerprint),
    permissions = approval_policy_record(agent$permissions),
    usage_limits = S7::props(agent$usage_limits),
    context_policy = policy,
    context_digest = delegation_digest(records),
    approval_enabled = !is.null(private$.approval_dir)
  )
}

job_graph_snapshot <- function(agent) {
  private <- agent$.__enclos_env__$private
  tree <- private$.delegation_tree
  if (is.null(tree)) {
    return(NULL)
  }
  members <- lapply(tree$handles, function(handle) {
    entry <- private$owned_conversations[[handle]]
    list(
      usage = S7::props(entry$usage),
      limits = S7::props(entry$limits),
      max_runs = entry$max_runs,
      ids = entry$ids,
      busy = entry$busy
    )
  })
  routes <- lapply(tree$routes, function(routes) {
    lapply(routes, function(route) {
      route$usage_limits <- S7::props(route$usage_limits)
      route
    })
  })
  list(
    limits = S7::props(tree$limits),
    max_depth = tree$max_depth,
    max_delegations = tree$max_delegations,
    max_concurrency = tree$max_concurrency,
    routes = routes,
    usage = S7::props(tree_usage(tree)),
    count = tree$count,
    admissions = tree$admissions,
    reservations = lapply(job_agents(agent), function(node) {
      node$.__enclos_env__$private$delegation_usage_reservations
    }),
    delegations = c(
      (tree$job_prior_delegations %||% list())[
        setdiff(names(tree$job_prior_delegations), names(private$subagent_runs))
      ],
      lapply(private$subagent_runs, function(record) {
        fields <- c(
          "agent_name",
          "agent_id",
          "session_id",
          "run_id",
          "parent_agent_id",
          "parent_run_id",
          "delegation_id",
          "parent_delegation_id",
          "depth",
          "root_agent_id",
          "tool_call_id",
          "admitted_at",
          "started_at",
          "completed_at",
          "status",
          "stop_reason",
          "conversation_handle"
        )
        out <- record[intersect(fields, names(record))]
        for (name in c("admitted_at", "started_at", "completed_at")) {
          if (!is.null(out[[name]])) out[[name]] <- as.numeric(out[[name]])
        }
        out$usage <- if (!is.null(record$usage)) S7::props(record$usage)
        out
      })
    ),
    members = members
  )
}

job_agent_manifest <- function(agent, pending_path = NULL) {
  nodes <- job_agents(agent)
  for (name in names(nodes)) {
    pending <- nodes[[name]]$.__enclos_env__$private$.pending_approval_path
    if (
      !is.null(pending) &&
        !(identical(name, "root") && identical(pending, pending_path))
    ) {
      job_runtime_abort(
        "Resolve or deny the Agent's pending approval before admitting another job."
      )
    }
  }
  ids <- vapply(nodes, function(node) node$agent_id, character(1))
  sessions <- vapply(nodes, function(node) node$session_id(), character(1))
  if (anyDuplicated(ids) || anyDuplicated(sessions)) {
    job_runtime_abort(
      "Every job Agent must have distinct agent and session identities."
    )
  }
  manifest <- list(
    runtime = list(
      schema_version = 1L,
      deputy = as.character(utils::packageVersion("deputy")),
      ellmer = as.character(utils::packageVersion("ellmer"))
    ),
    nodes = lapply(nodes, job_node_manifest),
    graph = job_graph_snapshot(agent)
  )
  if (
    !is.null(manifest$graph) &&
      (any(vapply(
        manifest$graph$members,
        function(member) isTRUE(member$busy),
        logical(1)
      )) ||
        any(lengths(manifest$graph$reservations)) ||
        any(vapply(
          manifest$graph$admissions,
          function(item) isTRUE(item$active),
          logical(1)
        )))
  ) {
    job_runtime_abort(
      "Admit a job only after all existing graph work has settled."
    )
  }
  approval_portable(manifest)
  manifest
}

job_bind_agent <- function(agent, record) {
  pending_path <- if (identical(record$status, "approval_pending")) {
    job_pending_path(record$pending_approval)
  } else {
    NULL
  }
  current <- job_agent_manifest(agent, pending_path = pending_path)
  saved <- record$manifest
  if (!identical(current$runtime, saved$runtime)) {
    job_runtime_abort(
      "The job requires its original compatible runtime versions."
    )
  }
  if (!is.list(saved) || !identical(names(current$nodes), names(saved$nodes))) {
    job_runtime_abort("The job's configured Agent graph changed.")
  }
  for (name in names(saved$nodes)) {
    expected <- saved$nodes[[name]]
    actual <- current$nodes[[name]]
    if (
      isTRUE(expected$permissions$callback_required) &&
        !isTRUE(actual$permissions$callback_required)
    ) {
      job_runtime_abort(
        "Reattach the host permission callback before recovering this job."
      )
    }
    # Current policy is checked by the ordinary runtime. The saved static
    # ceiling is an additional gate, so tightening remains possible.
    expected$permissions <- actual$permissions <- NULL
    # The approval protocol restores its own authenticated continuation context.
    if (identical(record$status, "approval_pending")) {
      expected$context_digest <- actual$context_digest <- NULL
    }
    if (!identical(expected, actual)) {
      job_runtime_abort(paste0(
        "Job definition or context changed for ",
        name,
        "."
      ))
    }
  }
  graph <- saved$graph
  if (is.null(graph) != is.null(current$graph)) {
    job_runtime_abort("The job's graph configuration changed.")
  }
  if (!is.null(graph)) {
    config <- c(
      "limits",
      "max_depth",
      "max_delegations",
      "max_concurrency",
      "routes"
    )
    if (!identical(graph[config], current$graph[config])) {
      job_runtime_abort("The job's graph routes or bounds changed.")
    }
    if (
      any(vapply(
        graph$members,
        function(member) isTRUE(member$busy),
        logical(1)
      ))
    ) {
      job_runtime_abort("An active graph snapshot cannot be replayed.")
    }
    private <- agent$.__enclos_env__$private
    tree <- private$.delegation_tree
    # A binder may reconstruct a fresh graph, but may not discard newer work
    # performed on a reused live graph after the job was admitted.
    zero_usage <- S7::props(AgentUsage())
    fresh <- identical(current$graph$usage, zero_usage) &&
      tree$count == 0L &&
      !length(tree$admissions) &&
      !length(current$graph$delegations) &&
      all(vapply(
        current$graph$members,
        function(member) {
          identical(member$usage, zero_usage) && !length(member$ids)
        },
        logical(1)
      ))
    if (!fresh && !identical(current$graph, graph)) {
      job_runtime_abort("The bound graph has advanced beyond the saved job.")
    }
    # Validate and construct every restored value before mutating any owner.
    restored_usage <- approval_usage(graph$usage)
    restored_members <- list()
    for (name in names(tree$handles)) {
      entry <- private$owned_conversations[[tree$handles[[name]]]]
      member <- graph$members[[name]]
      if (
        !identical(S7::props(entry$limits), member$limits) ||
          !identical(entry$max_runs, member$max_runs)
      ) {
        job_runtime_abort("The bound conversation allocation changed.")
      }
      restored_members[[name]] <- list(
        usage = approval_usage(member$usage),
        ids = member$ids
      )
    }
    tree$usage <- restored_usage
    tree$count <- graph$count
    tree$admissions <- graph$admissions
    # Historical correlations are portable job evidence, not reconstructed
    # live child handles or transcript access grants.
    tree$job_prior_delegations <- graph$delegations
    for (name in names(tree$handles)) {
      entry <- private$owned_conversations[[tree$handles[[name]]]]
      entry$usage <- restored_members[[name]]$usage
      entry$ids <- restored_members[[name]]$ids
    }
  }
  invisible(NULL)
}

job_event_data <- function(event) {
  if (S7::S7_inherits(event, AgentEvent)) event$data else event
}

job_effect_key <- function(agent, id) {
  paste(
    agent$agent_id,
    agent$.__enclos_env__$private$current_run_id,
    id,
    sep = "/"
  )
}

job_attach_runtime <- function(agent, checkpoint, record = NULL) {
  nodes <- job_agents(agent)
  state <- new.env(parent = emptyenv())
  state$root <- agent
  state$checkpoint_error <- NULL
  state$effects <- record$runtime$effects %||% list()
  pending <- record$runtime$pending_approval
  if (identical(record$status, "approval_pending") && !is.null(pending)) {
    approval <- approval_store_read(pending)
    validate_approval_record(approval)
    for (id in names(approval$effects)) {
      effect <- approval$effects[[id]]
      known <- any(vapply(
        state$effects,
        function(existing) {
          identical(existing$agent_id, approval$source$agent_id) &&
            identical(existing$tool_call_id, id) &&
            identical(existing$signature, effect$signature)
        },
        logical(1)
      ))
      if (known) {
        next
      }
      key <- paste(
        approval$source$agent_id,
        approval$source$run_id,
        id,
        sep = "/"
      )
      state$effects[[key]] <- c(
        list(
          agent_id = approval$source$agent_id,
          run_id = approval$source$run_id,
          tool_call_id = id
        ),
        effect
      )
    }
  }
  state$requests <- list()
  state$policies <- stats::setNames(
    lapply(names(nodes), function(name) {
      record$manifest$nodes[[name]]$permissions %||%
        approval_policy_record(nodes[[name]]$permissions)
    }),
    vapply(nodes, function(node) node$agent_id, character(1))
  )
  for (node in nodes) {
    private <- node$.__enclos_env__$private
    if (!is.null(private$.job_checkpoint)) {
      job_runtime_abort("This Agent is already bound to a job worker.")
    }
  }
  observe <- function(node, event) {
    type <- event$type
    settling <- type %in%
      c("delegation_settled", "delegation_released") ||
      (identical(type, "delegation_status") &&
        identical(event$phase, "settled"))
    if (!is.null(state$checkpoint_error) && !settling) {
      rlang::cnd_signal(state$checkpoint_error)
    }
    data <- job_event_data(event)
    private <- node$.__enclos_env__$private
    if (identical(type, "permission_check")) {
      ancestors <- private$.delegation_ancestors %||% list()
      for (subject in c(list(node), ancestors)) {
        saved <- state$policies[[subject$agent_id]]
        if (is.null(saved)) {
          job_runtime_abort("An unbound Agent entered the job.")
        }
        decision <- permissions_check(
          approval_static_policy(saved),
          data$tool_name,
          data$tool_input,
          data$context
        )
        if (!S7::S7_inherits(decision, PermissionResultAllow)) {
          ellmer::tool_reject(
            decision$reason %||% "Outside the saved job authority."
          )
        }
      }
      return(invisible(NULL))
    }
    if (identical(type, "tool_start")) {
      approval_validate_inputs(data$tool_input)
      key <- job_effect_key(node, data$tool_call_id)
      state$requests[[key]] <- list(
        name = data$tool_name,
        arguments = data$tool_input
      )
    }
    if (identical(type, "effect_start")) {
      key <- job_effect_key(node, data$tool_call_id)
      request <- state$requests[[key]]
      if (is.null(request) || !is.null(state$effects[[key]])) {
        job_runtime_abort(
          "The job cannot journal an uncorrelated or repeated effect."
        )
      }
      state$effects[[key]] <- list(
        agent_id = node$agent_id,
        run_id = private$current_run_id,
        tool_call_id = data$tool_call_id,
        request = request,
        signature = tool_request_signature(request$name, request$arguments),
        executed = TRUE,
        status = "executing",
        result = NULL
      )
    }
    if (identical(type, "effect_result")) {
      key <- job_effect_key(node, data$tool_call_id)
      effect <- state$effects[[key]]
      # A denied request has a result, but did not begin an external effect.
      if (!is.null(effect)) {
        result <- data$result
        effect$status <- if (is.null(result@error)) "completed" else "failed"
        effect$result <- if (observation_payload_fits(result, 1024^2)) {
          tryCatch(
            approval_record_content(result),
            error = function(error) {
              list(omitted = "unsupported result evidence")
            }
          )
        } else {
          list(omitted = "result evidence exceeds 1 MiB")
        }
        state$effects[[key]] <- effect
      }
    }
    if (
      type %in%
        c(
          "request_start",
          "request_end",
          "request_error",
          "run_error",
          "tool_start",
          "effect_start",
          "effect_result",
          "approval",
          "run_start",
          "run_end",
          "stop",
          "subagent_start",
          "subagent_stop",
          "delegation_admitted",
          "delegation_reserved",
          "delegation_released",
          "delegation_settled",
          "delegation_status"
        )
    ) {
      if (settling) {
        # A failed durable write must not prevent the ordinary runtime's
        # finally blocks from releasing child leases and restoring callbacks.
        # The worker checks this failure before publishing a terminal result.
        tryCatch(checkpoint(node, event), error = function(error) {
          state$checkpoint_error <- state$checkpoint_error %||% error
        })
      } else {
        checkpoint(node, event)
      }
    }
    invisible(NULL)
  }
  for (node in nodes) {
    private <- node$.__enclos_env__$private
    private$.job_state <- state
    private$.job_checkpoint <- observe
  }
  function() {
    for (node in nodes) {
      private <- node$.__enclos_env__$private
      if (identical(private$.job_checkpoint, observe)) {
        private$.job_checkpoint <- NULL
        private$.job_state <- NULL
      }
    }
    invisible(NULL)
  }
}

job_runtime_snapshot <- function(agent, event = NULL) {
  private <- agent$.__enclos_env__$private
  state <- private$.job_state
  root <- if (is.null(state)) agent else state$root
  nodes <- job_agents(root)
  usage <- lapply(nodes, function(node) {
    private <- node$.__enclos_env__$private
    value <- if (isTRUE(private$run_active)) {
      private$current_run_usage()
    } else {
      private$last_run_usage %||% AgentUsage()
    }
    S7::props(value)
  })
  source <- lapply(nodes, function(node) {
    private <- node$.__enclos_env__$private
    list(
      agent_id = node$agent_id,
      session_id = node$session_id(),
      run_id = private$current_run_id,
      parent_agent_id = private$.parent_agent_id,
      parent_run_id = private$.parent_run_id,
      delegation_id = private$.delegation_id
    )
  })
  list(
    usage = usage$root,
    node_usage = usage,
    effects = state$effects %||% list(),
    graph = job_graph_snapshot(root),
    source = source,
    pending_approval = root$.__enclos_env__$private$.pending_approval_path,
    event = if (!is.null(event)) {
      list(
        type = event$type,
        agent_id = agent$agent_id,
        run_id = private$current_run_id,
        tool_call_id = event$tool_call_id,
        delegation_id = event$delegation_id,
        phase = event$phase,
        status = event$status
      )
    }
  )
}
