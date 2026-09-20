# Host-owned retained conversations share the ordinary delegation lifecycle.
conversation_abort <- function(message) {
  abort_deputy(message, class = "conversation")
}

conversation_entry <- function(owner, handle) {
  handle <- delegation_text(handle, "handle")
  entry <- owner$.__enclos_env__$private$owned_conversations[[handle]]
  if (is.null(entry)) {
    conversation_abort("Conversation handle is unavailable for this owner.")
  }
  entry
}

conversation_configuration <- function(agent) {
  private <- agent$.__enclos_env__$private
  list(
    tools = agent$get_tools(),
    prompt = agent$get_system_prompt(),
    provider = agent$provider(),
    chat = private$.chat,
    fallback = private$.fallback_chats,
    hooks = agent$hooks$count()
  )
}

check_conversation_owner <- function(owner) {
  private <- owner$.__enclos_env__$private
  if (
    !is.null(private$.conversation_owner) ||
      !is.null(attr(private$.chat, "deputy_conversation_owner", exact = TRUE))
  ) {
    conversation_abort("Recursive conversation ownership is not yet supported.")
  }
  check_conversation_access(owner, NULL)
}

validate_conversation_candidate <- function(owner, agent) {
  if (
    !inherits(agent, "Agent") ||
      inherits(agent, "LeadAgent") ||
      identical(owner, agent)
  ) {
    conversation_abort(
      "Retain a distinct standalone Agent; recursive delegation is not yet supported."
    )
  }
  op <- owner$.__enclos_env__$private
  cp <- agent$.__enclos_env__$private
  if (identical(op$.chat, cp$.chat)) {
    conversation_abort(
      "The owner and retained specialist must use distinct Chats."
    )
  }
  check_conversation_owner(owner)
  if (length(cp$owned_conversations)) {
    conversation_abort("Recursive conversation ownership is not yet supported.")
  }
  if (
    !is.null(attr(cp$.chat, "deputy_conversation_owner")) ||
      !is.null(attr(cp$.chat, "deputy_active_runtime", exact = TRUE)) ||
      length(attr(cp$.chat, "deputy_active_conversations", exact = TRUE)) >
        0L ||
      isTRUE(cp$run_active) ||
      !is.null(cp$.conversation_owner) ||
      !is.null(cp$.delegation_binding)
  ) {
    conversation_abort("The conversation is active or already owned.")
  }
  if (!is.null(cp$.approval_dir) || !is.null(cp$.pending_approval_path)) {
    conversation_abort(
      "Retained delegation does not support durable approvals."
    )
  }
  if (
    any(vapply(
      agent$get_tools(),
      function(tool) {
        source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||%
          tool
        isTRUE(attr(source, "deputy_delegation_tool", exact = TRUE)) ||
          identical(source@name, "delegate_to_agent")
      },
      logical(1)
    ))
  ) {
    conversation_abort("Retained specialists cannot contain delegation tools.")
  }
  if (
    any(vapply(agent$get_tools(), inherits, logical(1), "ellmer::ToolBuiltIn"))
  ) {
    conversation_abort(
      "Provider-native tools cannot bind delegation governance."
    )
  }
  if (length(cp$.fallback_chats)) {
    conversation_abort(
      "Retained delegation currently requires one configured provider."
    )
  }
  invisible(NULL)
}

retain_conversation <- function(
  owner,
  agent,
  usage_limits,
  max_runs,
  initial_turns = NULL,
  fork = NULL,
  authorize = NULL,
  authorization = NULL,
  manifest = NULL
) {
  validate_conversation_candidate(owner, agent)
  op <- owner$.__enclos_env__$private
  cp <- agent$.__enclos_env__$private
  if (!is.null(op$.delegation_tree)) {
    conversation_abort(
      "Release the configured graph before retaining more agents."
    )
  }
  max_runs <- context_policy_whole_number(max_runs, "max_runs")
  if (is.null(max_runs) || length(op$owned_conversations) >= 32L) {
    conversation_abort(
      "Retained conversations require finite max_runs and at most 32 live handles."
    )
  }
  limits <- intersect_usage_limits(
    normalize_usage_limits(usage_limits),
    agent$usage_limits
  )
  previous_turns <- cp$.chat$get_turns()
  committed <- FALSE
  on.exit(
    if (!committed && !is.null(initial_turns)) {
      try(cp$.chat$set_turns(previous_turns), silent = TRUE)
    },
    add = TRUE
  )
  if (!is.null(initial_turns)) {
    cp$.chat$set_turns(initial_turns)
  }
  # A Chat may already be wrapped by another Agent. Retention transfers
  # execution authority to this Agent, so remove the other wrapper's callback
  # stacks and re-adapt the shared tools before recording the retained setup.
  cp$rewire_chat_runtime()
  attr(cp$.chat, "deputy_retained_runtime") <- TRUE
  entry <- new.env(parent = emptyenv())
  entry$agent <- agent
  entry$token <- new.env(parent = emptyenv())
  entry$limits <- limits
  entry$usage <- AgentUsage()
  entry$max_runs <- max_runs
  entry$ids <- character()
  entry$busy <- FALSE
  entry$configuration <- conversation_configuration(agent)
  entry$fork <- fork
  entry$authorize <- authorize
  entry$authorization <- authorization
  entry$manifest <- manifest
  handle <- new_deputy_id("conversation_")
  if (is.environment(cp$.chat)) {
    attr(cp$.chat, "deputy_conversation_owner") <- entry$token
  }
  cp$.conversation_owner <- entry$token
  cp$.hooks$.__enclos_env__$private$configuration_locked <- TRUE
  op$owned_conversations[[handle]] <- entry
  committed <- TRUE
  handle
}

conversation_remaining <- function(limits, usage) {
  fields <- c(
    max_requests = "requests",
    max_tool_calls = "tool_calls",
    max_input_tokens = "input_tokens",
    max_output_tokens = "output_tokens",
    max_total_tokens = "total_tokens",
    max_cost_usd = "cost_usd"
  )
  values <- lapply(names(fields), function(field) {
    limit <- S7::prop(limits, field)
    if (is.null(limit)) {
      return(NULL)
    }
    used <- S7::prop(usage, fields[[field]])
    if (is.na(used)) {
      conversation_abort(
        "Cumulative usage is unavailable for the requested budget."
      )
    }
    max(0, limit - used)
  })
  names(values) <- names(fields)
  do.call(UsageLimits, c(values, list(on_exceed = limits$on_exceed)))
}

continue_conversation <- function(
  owner,
  handle,
  task,
  usage_limits,
  correlation = NULL,
  caller = owner
) {
  check_conversation_owner(owner)
  entry <- conversation_entry(owner, handle)
  op <- owner$.__enclos_env__$private
  child <- entry$agent
  cp <- child$.__enclos_env__$private
  caller_private <- caller$.__enclos_env__$private
  tree <- op$.delegation_tree
  if (!identical(caller, owner)) {
    check_graph_caller(tree, caller)
  }
  # Recheck host source authority before any retained-run state is admitted.
  # This must precede busy/run-slot checks and lifecycle admission so a denied
  # or stale source cannot consume a run slot or leave a sticky reservation.
  context_fork_reauthorize(entry)
  if (entry$busy || isTRUE(cp$run_active)) {
    conversation_abort("The conversation is busy.")
  }
  if (length(entry$ids) >= entry$max_runs) {
    conversation_abort("The conversation has reached max_runs; release it.")
  }
  if (!identical(entry$configuration, conversation_configuration(child))) {
    conversation_abort(
      "The retained configuration changed; release and explicitly adopt it again."
    )
  }
  if (!identical(cp$.conversation_owner, entry$token)) {
    conversation_abort("Conversation ownership has expired.")
  }
  task <- delegation_text(task, "task")
  if (nchar(task, type = "bytes") > op$delegation_max_bytes) {
    conversation_abort(
      "The continuation brief exceeds the admission byte limit."
    )
  }
  limits <- intersect_usage_limits(
    normalize_usage_limits(usage_limits),
    intersect_usage_limits(
      conversation_remaining(entry$limits, entry$usage),
      caller_private$derive_subagent_usage_limits(list(max_requests = NULL))
    )
  )
  limits <- intersect_usage_limits(limits, child$usage_limits)
  correlation <- correlation %||%
    list(
      delegation_id = new_deputy_id("delegation_"),
      tool_call_id = NULL,
      parent_agent_id = caller$agent_id,
      parent_run_id = if (isTRUE(caller_private$run_active)) {
        caller_private$current_run_id
      } else {
        NULL
      },
      run_context = caller_private$effective_run_context()
    )
  tree_admission <- NULL
  if (!is.null(tree)) {
    if (!handle %in% tree$handles) {
      conversation_abort("This handle is not part of the configured graph.")
    }
    check_graph_ancestors(owner, caller)
    tree_admission <- tree_admit(
      tree,
      correlation$delegation_id,
      caller_private$.delegation_id
    )
    correlation <- c(correlation, tree_admission)
  }
  id <- correlation$delegation_id
  old <- NULL
  owner_chat <- op$.chat
  handed_off <- FALSE
  cleanup <- function() {
    if (!is.null(tree)) {
      tree_settle(tree, id)
    }
    active <- setdiff(
      attr(owner_chat, "deputy_active_conversations", exact = TRUE),
      id
    )
    attr(owner_chat, "deputy_active_conversations") <- if (length(active)) {
      active
    } else {
      NULL
    }
    caller_private$release_delegation_usage(id)
    if (!is.null(old)) {
      cp$.parent_agent_id <- old$parent_agent_id
      cp$.parent_run_id <- old$parent_run_id
      cp$.delegation_id <- old$delegation_id
      cp$.delegation_guard <- old$guard
      cp$.delegation_observe <- old$observe
      cp$.delegation_binding <- old$binding
      cp$.hooks <- old$hooks
      cp$.delegation_ancestors <- old$ancestors
    }
    entry$busy <- FALSE
    entry$configuration <- conversation_configuration(child)
  }
  on.exit(
    {
      if (!handed_off) {
        cleanup()
        if (!is.null(op$subagent_runs[[id]])) {
          lead_settle_delegation(owner, id, stop_reason = "setup_failed")
        }
      }
    },
    add = TRUE
  )
  definition <- list(name = child$agent_name %||% "specialist")
  entry$busy <- TRUE
  id <- lead_admit_delegation(owner, definition, task, correlation)
  previous <- utils::tail(entry$ids, 1L)
  op$subagent_runs[[id]]$conversation_handle <- handle
  op$subagent_runs[[id]]$previous_delegation_id <- if (length(previous)) {
    previous
  } else {
    NULL
  }
  entry$ids <- c(entry$ids, id)
  caller_private$reserve_delegation_usage(id, limits)
  # Acquire before returning the promise, including before the first dispatch.
  old <- list(
    parent_agent_id = cp$.parent_agent_id,
    parent_run_id = cp$.parent_run_id,
    delegation_id = cp$.delegation_id,
    guard = cp$.delegation_guard,
    observe = cp$.delegation_observe,
    binding = cp$.delegation_binding,
    hooks = cp$.hooks,
    ancestors = cp$.delegation_ancestors
  )
  cp$current_run_id <- NULL
  cp$last_run_usage <- AgentUsage()
  cp$.last_run_result <- NULL
  cp$delegation_artifacts <- list()
  cp$.parent_agent_id <- correlation$parent_agent_id
  cp$.parent_run_id <- correlation$parent_run_id
  cp$.delegation_id <- id
  cp$.delegation_binding <- list(mode = "retained", approval = "unsupported")
  ancestors <- if (is.null(tree)) {
    list(owner)
  } else {
    graph_ancestors(owner, caller)
  }
  cp$.delegation_guard <- function(tool_name, tool_input, context) {
    if (!is.null(old$guard)) {
      old$guard(tool_name, tool_input, context)
    }
    for (ancestor in ancestors) {
      decision <- permissions_check(
        ancestor$permissions,
        tool_name,
        tool_input,
        context
      )
      if (!S7::S7_inherits(decision, PermissionResultAllow)) {
        ellmer::tool_reject(
          decision$reason %||% "Denied by current caller policy."
        )
      }
    }
  }
  if (is.null(tree)) {
    runtime_hooks <- cp$.hooks$clone(deep = TRUE)
    runtime_hooks$.__enclos_env__$private$configuration_locked <- FALSE
    for (event in c("PreToolUse", "PostToolUse", "PostToolUseFailure")) {
      local({
        selected <- event
        runtime_hooks$add(HookMatcher(
          selected,
          timeout = 0,
          callback = function(...) {
            forward_delegation_hook(owner, id, selected, ...)
          }
        ))
      })
    }
    runtime_hooks$.__enclos_env__$private$configuration_locked <- TRUE
    cp$.hooks <- runtime_hooks
  } else {
    cp$.delegation_ancestors <- ancestors
  }
  if (!isTRUE(op$run_active) && !length(op$active_subagents)) {
    op$should_stop <- FALSE
  }
  cp$.delegation_observe <- function(event) lead_observe_event(owner, id, event)
  lead_bind_delegation(owner, id, child, entry$manifest)
  # Track work on the shared Chat too: another Agent wrapper must not adopt
  # this owner while its admitted child continuations are still outstanding.
  owner_chat <- op$.chat
  attr(owner_chat, "deputy_active_conversations") <- c(
    attr(owner_chat, "deputy_active_conversations", exact = TRUE),
    id
  )
  promise <- coro::async(function() {
    on.exit(cleanup(), add = TRUE)
    outcome <- coro::await(lead_run_delegation(
      owner,
      id,
      child,
      definition,
      task,
      limits = limits,
      usage_owner = caller,
      run = function() {
        check_conversation_owner(owner)
        if (!is.null(tree)) {
          check_graph_ancestors(owner, caller)
        }
        stream <- cp$start_governed_stream(
          list(task),
          limits,
          child$run_context,
          conversation_token = entry$token
        )
        cp$collect_governed_stream(stream)
      }
    ))
    record <- op$subagent_runs[[id]]
    entry$usage <- agent_usage_add(entry$usage, record$usage %||% AgentUsage())
    op$subagent_runs[[id]]$cumulative_usage <- entry$usage
    if (!is.null(outcome$error)) {
      rlang::cnd_signal(outcome$error)
    }
    outcome$result %||%
      AgentResult(
        stop_reason = record$stop_reason,
        session_id = record$session_id,
        agent_id = record$agent_id,
        agent_name = record$agent_name,
        parent_agent_id = record$parent_agent_id,
        parent_run_id = record$parent_run_id,
        delegation_id = id,
        run_context = record$run_context
      )
  })()
  handed_off <- TRUE
  promise
}

release_conversation <- function(owner, handle) {
  entry <- conversation_entry(owner, handle)
  if (!is.null(owner$.__enclos_env__$private$.delegation_tree)) {
    conversation_abort(
      "Release graph members together with release_agent_graph()."
    )
  }
  if (entry$busy) {
    conversation_abort(
      "Cancel and wait for settlement before releasing a busy conversation."
    )
  }
  op <- owner$.__enclos_env__$private
  cp <- entry$agent$.__enclos_env__$private
  if (is.environment(cp$.chat)) {
    attr(cp$.chat, "deputy_conversation_owner") <- NULL
  }
  cp$.conversation_owner <- NULL
  cp$.hooks$.__enclos_env__$private$configuration_locked <- FALSE
  op$owned_conversations[[handle]] <- NULL
  # Release snapshots too; hosts can explicitly export them beforehand.
  op$subagent_runs[entry$ids] <- NULL
  invisible(NULL)
}

check_incoming_conversation <- function(chat) {
  if (
    !is.null(attr(chat, "deputy_conversation_owner", exact = TRUE)) ||
      !is.null(attr(chat, "deputy_active_runtime", exact = TRUE)) ||
      length(attr(chat, "deputy_active_conversations", exact = TRUE))
  ) {
    conversation_abort("This Chat is already owned by a retained conversation.")
  }
}

check_conversation_initialization <- function(agent) {
  if (isTRUE(agent$.__enclos_env__$private$run_active)) {
    conversation_abort(
      "Wait for the active run before reinitializing an Agent."
    )
  }
  if (length(agent$.__enclos_env__$private$owned_conversations)) {
    conversation_abort(
      "Release retained conversations before reinitializing an Agent."
    )
  }
  check_conversation_lease(agent, NULL)
}

check_conversation_lease <- function(agent, token) {
  check_owner_children(agent)
  check_conversation_access(agent, token)
}

check_conversation_access <- function(agent, token) {
  private <- agent$.__enclos_env__$private
  active <- attr(private$.chat, "deputy_active_runtime", exact = TRUE)
  if (
    !is.null(active) &&
      !(isTRUE(private$run_active) && identical(active, private$current_run_id))
  ) {
    conversation_abort(
      "Wait for the active run before accessing this shared Chat."
    )
  }
  shared <- attr(private$.chat, "deputy_conversation_owner", exact = TRUE)
  if (
    !identical(private$.conversation_owner, token) ||
      (!is.null(shared) && !identical(shared, token))
  ) {
    conversation_abort(
      "This conversation must be run through its current owner."
    )
  }
  invisible(NULL)
}

# Registered without an owner-capturing closure, so collection can release leases.
finalize_owned_conversations <- function(owner) {
  finalize_delegation_graph(owner)
  private <- owner$.__enclos_env__$private
  for (entry in private$owned_conversations) {
    if (isTRUE(entry$busy)) {
      next
    }
    child <- entry$agent$.__enclos_env__$private
    if (identical(child$.conversation_owner, entry$token)) {
      child$.conversation_owner <- NULL
      child$.hooks$.__enclos_env__$private$configuration_locked <- FALSE
    }
    if (
      identical(attr(child$.chat, "deputy_conversation_owner"), entry$token)
    ) {
      attr(child$.chat, "deputy_conversation_owner") <- NULL
    }
  }
  invisible(NULL)
}

check_owner_children <- function(agent) {
  private <- agent$.__enclos_env__$private
  if (
    !isTRUE(private$run_active) &&
      (length(private$active_subagents) ||
        length(attr(
          private$.chat,
          "deputy_active_conversations",
          exact = TRUE
        )))
  ) {
    conversation_abort(
      "Wait for active child conversations before starting an owner run."
    )
  }
  invisible(NULL)
}
