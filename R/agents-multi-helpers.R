# Internal helpers for LeadAgent orchestration -------------------------------

# Clone a Chat with isolated callbacks, empty turns, and empty tools.
clone_clean_subagent_chat <- function(chat, model = "inherit") {
  cloned <- clone_governed_chat(chat)
  if (identical(cloned, chat)) {
    cli_abort("Chat cloning must return an independent instance")
  }
  clear_chat_tool_callbacks(cloned, source = chat)
  cloned$set_turns(list())
  # The child definition chooses its tools. Inherited provider configuration
  # must not import the parent's executable registry.
  cloned$set_tools(list())
  if (!identical(model, "inherit")) {
    cloned$set_model(model)
  }
  cloned
}

# A copy of the lead's chat keeps the lead's params, and ellmer has no public
# way to change them, so only a host chat function can apply a clone-form
# definition's params.
lead_check_definition_params <- function(
  private,
  definition,
  call = rlang::caller_env()
) {
  if (
    length(definition$params) &&
      definition_copies_lead_chat(definition) &&
      !is.function(private$.delegation_policy$chat)
  ) {
    abort_deputy(
      c(
        "AgentDefinition {.val {definition$name}} has {.arg params}, but its model copies the lead's chat, which keeps the lead's params.",
        "i" = "Give the lead a {.code DelegationPolicy(chat = )} function that builds the subagent's chat, or use a {.val provider/model} model."
      ),
      class = "delegation_binding",
      call = call
    )
  }
  invisible(definition)
}

lead_build_prompt <- function(base_prompt, sub_agents) {
  lines <- character()

  if (!is.null(base_prompt)) {
    lines <- c(lines, base_prompt, "")
  }

  if (length(sub_agents) > 0) {
    lines <- c(
      lines,
      deputy_lead_routing_start_marker,
      "# Available Sub-Agents",
      "",
      "You can delegate specialized tasks to these sub-agents using the",
      "`delegate_to_agent` tool:",
      ""
    )

    for (def in sub_agents) {
      lines <- c(lines, paste0("## ", def$name), def$description, "")
    }

    lines <- c(
      lines,
      "When delegating, provide a clear task description. The sub-agent",
      "will complete the task and return results to you.",
      "",
      "# End Available Sub-Agents",
      deputy_lead_routing_end_marker,
      ""
    )
  }

  paste(lines, collapse = "\n")
}

lead_replace_prompt <- function(full_prompt, sub_agents) {
  section <- lead_build_prompt(NULL, sub_agents)
  if (!is_nonempty_string(full_prompt)) {
    return(section)
  }

  start_marker <- deputy_lead_routing_start_marker
  end_marker <- deputy_lead_routing_end_marker
  start <- regexpr(start_marker, full_prompt, fixed = TRUE)
  if (start[[1L]] < 0L) {
    return(lead_build_prompt(full_prompt, sub_agents))
  }
  remainder <- substr(full_prompt, start[[1L]], nchar(full_prompt))
  end <- regexpr(end_marker, remainder, fixed = TRUE)
  if (end[[1L]] < 0L) {
    return(lead_build_prompt(full_prompt, sub_agents))
  }

  before <- substr(full_prompt, 1L, start[[1L]] - 1L)
  after_start <- start[[1L]] + end[[1L]] - 1L + attr(end, "match.length")
  after <- if (after_start > nchar(full_prompt)) {
    ""
  } else {
    substr(full_prompt, after_start, nchar(full_prompt))
  }
  # The section ends with the newline that followed the old end marker,
  # so `after` must not bring a second one.
  if (endsWith(section, "\n") && startsWith(after, "\n")) {
    after <- substr(after, 2L, nchar(after))
  }
  paste0(before, section, after)
}

lead_create_delegate_tool <- function(lead_agent, private) {
  tool <- ellmer::tool(
    fun = function(
      agent_name,
      task,
      constraints = character(),
      evidence = list(),
      deliverable = NULL,
      stop_conditions = character()
    ) {
      correlation <- private$claim_delegation(
        tool_name = "delegate_to_agent"
      )

      route_key <- if (is_nonempty_string(agent_name)) {
        tolower(trimws(agent_name))
      } else {
        ""
      }
      def <- private$.sub_agent_defs[[route_key]]

      if (is.null(def)) {
        available <- lead_agent$available_sub_agents()
        ellmer::tool_reject(paste0(
          "Unknown agent: ",
          agent_name,
          ". ",
          "Available agents: ",
          paste(available, collapse = ", ")
        ))
      }

      id <- lead_admit_delegation(lead_agent, def, task, correlation)
      child <- tryCatch(
        {
          input <- if (S7::S7_inherits(task, DelegationInput)) {
            if (
              length(constraints) ||
                length(evidence) ||
                !is.null(deliverable) ||
                length(stop_conditions)
            ) {
              delegation_input_abort(
                "invalid",
                "Structured task cannot be combined with separate brief fields."
              )
            }
            normalize_delegation_input(task)
          } else {
            DelegationInput(
              task,
              constraints,
              delegation_tool_references(evidence),
              deliverable,
              stop_conditions
            )
          }
          prepared <- resolve_delegation_input(lead_agent, def, input)
          limits <- private$derive_subagent_usage_limits(def)
          child <- private$create_sub_agent(def, correlation, limits)
          manifest <- prepare_delegation_manifest(
            lead_agent,
            def,
            prepared,
            child
          )
          lead_bind_delegation(lead_agent, id, child, manifest)
          child
        },
        error = function(condition) {
          lead_settle_delegation(
            lead_agent,
            id,
            error = condition,
            stop_reason = "setup_error"
          )
          release_delegation_binding(lead_agent, id)
          stop(condition)
        }
      )
      # Reserve before returning the promise, so concurrent calls cannot
      # each receive the same remaining budget.
      private$reserve_delegation_usage(id, limits)
      cli::cli_alert_info("Delegating to {.val {def$name}}: {input$task}")
      lead_run_delegation(lead_agent, id, child, def, manifest$message) |>
        promises::then(function(outcome) {
          if (!is.null(private$current_usage_limits)) {
            limit <- private$limit_status(require_followup = TRUE)
            if (!is.null(limit)) private$mark_usage_limit(limit)
          }
          delegation_tool_result_payload(
            private$subagent_runs[[id]],
            failed = !is.null(outcome$error),
            agent_name = def$name
          )
        })
    },
    name = "delegate_to_agent",
    description = "Delegate a task to a specialized sub-agent. The sub-agent will complete the task and return results.",
    arguments = list(
      agent_name = ellmer::type_string(
        "Name of the sub-agent to delegate to"
      ),
      task = ellmer::type_string("The task to delegate to the Subagent"),
      constraints = ellmer::type_array(
        ellmer::type_string(),
        required = FALSE
      ),
      evidence = ellmer::type_array(
        ellmer::type_object(
          source_id = ellmer::type_string(),
          revision = ellmer::type_string()
        ),
        required = FALSE
      ),
      deliverable = ellmer::type_string(required = FALSE),
      stop_conditions = ellmer::type_array(
        ellmer::type_string(),
        required = FALSE
      )
    ),
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = FALSE
    )
  )
  attr(tool, "deputy_delegation_tool") <- TRUE
  attr(tool, "deputy_internal_tool") <- deputy_delegation_tool_marker
  mark_native_tool(tool)
}

lead_build_subagent_chat <- function(
  self,
  private,
  def,
  correlation,
  call = rlang::caller_env()
) {
  # "inherit" clones the parent chat. A bare model id (no "provider/" prefix)
  # also clones it, keeping the lead's provider, endpoint and credentials, and
  # switches only the model: the way to run a child on a cheaper model of a
  # provider that ellmer::chat() cannot name, such as a gateway client built
  # outside ellmer.
  if (is.function(private$.delegation_policy$chat)) {
    return(delegation_factory_chat(self, def, correlation))
  }
  if (definition_copies_lead_chat(def)) {
    return(tryCatch(
      clone_clean_subagent_chat(private$.chat, model = def$model),
      error = function(e) {
        cli_abort(
          c(
            if (def$model == "inherit") {
              "Could not inherit model from parent for sub-agent {.val {def$name}}"
            } else {
              "Could not use model {.val {def$model}} on the parent's provider for sub-agent {.val {def$name}}"
            },
            "x" = conditionMessage(e),
            "i" = "Please specify an explicit {.arg model} in {.fn agent_definition}"
          ),
          call = call
        )
      }
    ))
  }
  tryCatch(
    ellmer::chat(
      def$model,
      params = if (length(def$params)) def$params
    ),
    error = function(e) {
      cli_abort(
        c(
          "Failed to create chat for sub-agent {.val {def$name}}",
          "x" = "Invalid model: {.val {def$model}}",
          "i" = conditionMessage(e)
        ),
        call = call
      )
    }
  )
}

lead_create_sub_agent <- function(
  self,
  private,
  def,
  correlation = NULL,
  usage_limits = NULL,
  stateless = FALSE,
  call = rlang::caller_env()
) {
  begin_delegation_binding(self, def, correlation, stateless)
  bound <- FALSE
  on.exit(
    if (!bound) release_delegation_binding(self, correlation$delegation_id),
    add = TRUE
  )

  sub_chat <- lead_build_subagent_chat(
    self,
    private,
    def,
    correlation,
    call = call
  )
  sub_tools <- private$filter_disallowed_tools(def$tools, def$disallowed_tools)
  sub_permissions <- private$derive_subagent_permissions(def)
  sub_prompt <- def$prompt
  if (!is.null(def$memory) && length(def$memory) > 0) {
    sub_prompt <- paste(
      sub_prompt,
      "",
      "# Memory",
      paste(as.character(def$memory), collapse = "\n\n"),
      sep = "\n"
    )
  }

  child_run_context <- merge_run_context(
    correlation$run_context,
    list(role = def$name)
  )
  sub_agent <- Agent$new(
    chat = sub_chat,
    tools = sub_tools,
    system_prompt = sub_prompt,
    permissions = sub_permissions,
    usage_limits = usage_limits %||%
      private$derive_subagent_usage_limits(def),
    context_policy = self$context_policy,
    working_dir = self$working_dir,
    session_id = new_deputy_id("session_"),
    run_context = child_run_context,
    agent_name = def$name
  )
  child_private <- agent_private(sub_agent)
  child_private$.parent_agent_id <- correlation$parent_agent_id
  child_private$.parent_run_id <- correlation$parent_run_id
  child_private$.delegation_id <- correlation$delegation_id
  # A subagent's runs belong to the conversation of the run that delegated them.
  child_private$.inherited_conversation_id <- trace_conversation_id(private)
  # A checkpoint describes workspace state, not one agent's private execution
  # history. Delegated agents therefore write to the exact same journal as the
  # lead so a lead-level rewind includes child mutations.
  if (!stateless && !is.null(private$.file_checkpoints)) {
    child_private$.file_checkpoints <- private$.file_checkpoints
  }
  for (skill in def$skills) {
    sub_agent$load_skill(skill)
  }

  bind_delegation_host(self, sub_agent, def, correlation, stateless)
  # Check the final registry, after binding has applied the denylist to
  # skill and host tools. A failure here still releases the binding.
  private$inherit_trusted_results(sub_agent)
  bound <- TRUE
  sub_agent
}

# Each definition's checked registry: its tools and Skill values, less its
# denylist.
lead_trusted_definition_tools <- function(private) {
  lapply(private$.sub_agent_defs, function(def) {
    skill_tools <- unlist(
      lapply(def$skills, function(skill) {
        if (S7::S7_inherits(skill, Skill)) skill$tools else list()
      }),
      recursive = FALSE
    )
    validate_tool_batch(private$filter_disallowed_tools(
      c(def$tools, skill_tools),
      def$disallowed_tools
    ))
  })
}

# The whole delegation tree obeys one no-bypass rule: the lead may keep its
# own delegate tool only because every child inherits the policy.
lead_check_trusted_tools <- function(
  self,
  private,
  tools,
  call = rlang::caller_env()
) {
  policy <- private$.trusted_results
  if (is.null(policy)) {
    return(invisible(NULL))
  }
  # Designated producers must be declared statically, in tools or Skill
  # values. Skills named by path load fresh objects when each child is built,
  # so they may add other checked tools but never a producer.
  definitions <- private$trusted_definition_tools()
  sources <- trusted_tree_sources(policy, c(list(tools), definitions))
  check_trusted_registry(
    policy,
    tools,
    available = unique(c(
      names(tools),
      unlist(lapply(definitions, names), use.names = FALSE)
    )),
    allow_delegation = TRUE,
    sources = sources,
    admit_route = trusted_route_admission(self, tools)
  )
  for (name in names(definitions)) {
    withCallingHandlers(
      check_trusted_registry(
        policy,
        definitions[[name]],
        available = policy@results,
        sources = sources
      ),
      deputy_tool_registration = function(error) {
        rlang::abort(
          paste0(
            "AgentDefinition '",
            name,
            "' violates the trusted-results policy."
          ),
          class = setdiff(
            class(error),
            c("rlang_error", "error", "condition")
          ),
          parent = error,
          call = call
        )
      }
    )
  }
  # Names a retained agent's own policy designates stay that tool in the
  # lead's registry and in every definition.
  for (entry in private$owned_conversations) {
    if (!is.null(entry$trusted)) {
      trusted_check_names(
        trusted_policy_sources(entry$trusted$policy),
        c(list(tools), definitions)
      )
    }
  }
  invisible(sources)
}

# Children inherit the lead policy. Their trusted results are recorded in the
# lead's run and delivered to the lead's callback, with the child's
# correlation fields intact.
lead_inherit_trusted_results <- function(private, child) {
  policy <- private$.trusted_results
  if (is.null(policy)) {
    return(invisible(NULL))
  }
  sources <- private$check_trusted_tools(private$.chat$get_tools())
  forward <- function(event) {
    private$record_run_event(event)
    if (is.function(policy@on_result)) {
      policy@on_result(event)
    }
    invisible(NULL)
  }
  child_private <- agent_private(child)
  child_private$.trusted_results <- trusted_policy_copy(policy, forward)
  child_private$.trusted_tree_member <- TRUE
  child_private$.trusted_sources <- sources
  child_private$check_trusted_tools(child$get_tools())
  invisible(NULL)
}

lead_derive_subagent_permissions <- function(
  self,
  def,
  call = rlang::caller_env()
) {
  existing <- self$permissions
  requested_mode <- def$permission_mode %||% existing$mode
  allowed_modes <- permission_mode_targets(existing$mode)
  if (!requested_mode %in% allowed_modes) {
    cli_abort(
      c(
        "Sub-agent permission mode cannot change under the lead policy",
        "x" = paste0(
          "Lead mode ",
          existing$mode,
          " cannot delegate with mode ",
          requested_mode,
          "."
        ),
        "i" = paste0(
          "Use mode ",
          existing$mode,
          ", then tighten the child with disallowed_tools or ",
          "max_requests."
        )
      ),
      call = call
    )
  }
  denylist <- unique(c(existing$tool_denylist, def$disallowed_tools))

  ceiling <- permission_capabilities_from(existing)
  capabilities <- if (identical(requested_mode, existing$mode)) {
    ceiling
  } else {
    intersect_permission_capabilities(
      ceiling,
      permission_mode_capabilities(requested_mode, self$working_dir)
    )
  }

  Permissions(
    mode = requested_mode,
    file_read = capabilities$file_read,
    file_write = capabilities$file_write,
    bash = capabilities$bash,
    r_code = capabilities$r_code,
    web = capabilities$web,
    install_packages = capabilities$install_packages,
    can_use_tool = existing$can_use_tool,
    tool_allowlist = existing$tool_allowlist,
    tool_denylist = denylist,
    permission_prompt_tool_name = capabilities$permission_prompt_tool_name
  )
}

lead_filter_disallowed_tools <- function(tools, disallowed_tools) {
  if (is.null(disallowed_tools) || length(disallowed_tools) == 0) {
    return(tools)
  }

  disallowed <- tolower(trimws(as.character(disallowed_tools)))
  tool_names <- names(tools)
  keep <- vapply(
    seq_along(tools),
    function(index) {
      tool <- tools[[index]]
      label <- if (
        !is.null(tool_names) &&
          length(tool_names) >= index &&
          is_nonempty_string(tool_names[[index]])
      ) {
        tool_names[[index]]
      } else {
        paste0("#", index)
      }
      name <- read_optional_value(
        function() tool@name,
        validator = is_nonempty_string
      )

      if (identical(name$status, "unreadable")) {
        cli_warn(c(
          "Dropping tool {.val {label}} because its name could not be read.",
          "i" = "Tool object class: {.cls {class(tool)}}.",
          "x" = conditionMessage(name$error)
        ))
        return(FALSE)
      }

      if (!identical(name$status, "present")) {
        cli_warn(c(
          "Dropping tool {.val {label}} because it has no usable name.",
          "i" = "Tool object class: {.cls {class(tool)}}."
        ))
        return(FALSE)
      }

      !tolower(trimws(name$value)) %in% disallowed
    },
    logical(1)
  )

  tools[keep]
}
