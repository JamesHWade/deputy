# Multi-agent orchestration for deputy

normalize_agent_definition_name <- function(name, arg = "name") {
  if (!is_nonempty_string(name)) {
    cli_abort("{.arg {arg}} must be one non-empty string")
  }

  name <- tolower(trimws(name))
  if (!grepl("^[a-z][a-z0-9_-]*$", name)) {
    cli_abort(c(
      "{.arg {arg}} must be a valid AgentDefinition routing key",
      "i" = paste(
        "Use a letter first, followed only by lowercase letters, numbers,",
        "underscores, or hyphens."
      )
    ))
  }

  name
}

validate_agent_definition_text <- function(value, arg, optional = FALSE) {
  if (is.null(value) && optional) {
    return(NULL)
  }
  if (!is_nonempty_string(value)) {
    cli_abort("{.arg {arg}} must be one non-empty string")
  }
  value
}

validate_agent_definition_character <- function(
  value,
  arg,
  optional = TRUE,
  normalize = FALSE
) {
  if (is.null(value) && optional) {
    return(NULL)
  }
  if (
    !is.character(value) ||
      anyNA(value) ||
      !all(nzchar(trimws(value)))
  ) {
    cli_abort("{.arg {arg}} must be a character vector of non-empty strings")
  }

  value <- trimws(value)
  if (normalize) {
    value <- tolower(value)
  }
  unique(value)
}

copy_agent_definition <- function(definition, arg = "definition") {
  if (!inherits(definition, "AgentDefinition")) {
    cli_abort("{.arg {arg}} must be an AgentDefinition object")
  }

  fields <- setdiff(names(formals(agent_definition)), "...")
  do.call(agent_definition, unclass(definition)[fields])
}

normalize_agent_definitions <- function(definitions, arg = "sub_agents") {
  if (!is.list(definitions)) {
    cli_abort("{.arg {arg}} must be a list of AgentDefinition objects")
  }

  definitions <- lapply(
    seq_along(definitions),
    function(index) {
      copy_agent_definition(
        definitions[[index]],
        arg = paste0(arg, "[[", index, "]]")
      )
    }
  )
  keys <- vapply(
    definitions,
    function(definition) definition$name,
    character(1)
  )
  duplicate_keys <- unique(keys[duplicated(keys)])
  if (length(duplicate_keys) > 0) {
    cli_abort(c(
      "Duplicate AgentDefinition routing keys are not allowed",
      "x" = "Duplicated: {.val {duplicate_keys}}"
    ))
  }

  stats::setNames(definitions, keys)
}

#' Create an Agent Definition
#'
#' @description
#' AgentDefinition describes a specialized agent that can be used by a lead
#' agent to delegate tasks. It bundles together a system prompt, tools, and
#' metadata about what the agent can do.
#'
#' @param name Unique routing key for this Agent type. Names are trimmed,
#'   converted to lowercase, and must start with a letter followed only by
#'   letters, numbers, underscores, or hyphens.
#' @param description Brief description of what this agent does (shown to lead agent)
#' @param prompt System prompt for this agent
#' @param tools Optional list of tools for this agent
#' @param model Model to use (default: "inherit" uses parent's model)
#' @param skills Optional list of skills to load
#' @param disallowed_tools Optional tool denylist for this sub-agent
#' @param memory Optional memory text appended to this sub-agent's prompt
#' @param mcp_servers Optional MCP server names to load for this sub-agent
#' @param initial_prompt Optional text prepended to delegated tasks
#' @param max_requests Optional non-negative whole-number sub-agent request limit
#' @param permission_mode Optional permission mode. A child may keep the lead
#'   mode or narrow it to `"readonly"`; a `"full"` lead may select any mode.
#'   Use `disallowed_tools` and `max_requests` for additional limits.
#' @return An `AgentDefinition` object
#'
#' @examples
#' \dontrun{
#' # Define a code review agent
#' code_reviewer <- agent_definition(
#'   name = "code_reviewer",
#'   description = "Reviews code for bugs, style issues, and best practices",
#'   prompt = "You are an expert code reviewer...",
#'   tools = list(tool_read_file, tool_list_files)
#' )
#'
#' # Use with a lead agent
#' lead <- LeadAgent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   sub_agents = list(code_reviewer)
#' )
#' }
#'
#' @export
agent_definition <- function(
  name,
  description,
  prompt,
  tools = list(),
  model = "inherit",
  skills = list(),
  disallowed_tools = NULL,
  memory = NULL,
  mcp_servers = NULL,
  initial_prompt = NULL,
  max_requests = NULL,
  permission_mode = NULL
) {
  name <- normalize_agent_definition_name(name)
  description <- validate_agent_definition_text(description, "description")
  prompt <- validate_agent_definition_text(prompt, "prompt")
  model <- validate_agent_definition_text(model, "model")
  if (!is.list(tools)) {
    cli_abort("{.arg tools} must be a list")
  }
  if (!is.list(skills)) {
    cli_abort("{.arg skills} must be a list")
  }
  disallowed_tools <- validate_agent_definition_character(
    disallowed_tools,
    "disallowed_tools",
    normalize = TRUE
  )
  memory <- validate_agent_definition_character(memory, "memory")
  mcp_servers <- validate_agent_definition_character(
    mcp_servers,
    "mcp_servers"
  )
  initial_prompt <- validate_agent_definition_text(
    initial_prompt,
    "initial_prompt",
    optional = TRUE
  )
  if (!is.null(permission_mode)) {
    permission_mode <- validate_permission_mode_value(
      permission_mode,
      arg = "permission_mode"
    )
  }
  if (!is.null(max_requests)) {
    max_requests <- validate_usage_limit(
      max_requests,
      "max_requests",
      integer = TRUE
    )
  }

  structure(
    list(
      name = name,
      description = description,
      prompt = prompt,
      tools = tools,
      model = model,
      skills = skills,
      disallowed_tools = disallowed_tools,
      memory = memory,
      mcp_servers = mcp_servers,
      initial_prompt = initial_prompt,
      max_requests = max_requests,
      permission_mode = permission_mode
    ),
    class = "AgentDefinition"
  )
}

#' @export
print.AgentDefinition <- function(x, ...) {
  cat("<AgentDefinition:", x$name, ">\n")
  cat("  description:", truncate_string(x$description, 60), "\n")
  cat("  tools:", length(x$tools), "\n")
  cat("  skills:", length(x$skills), "\n")
  cat("  model:", x$model, "\n")
  if (!is.null(x$permission_mode)) {
    cat("  permission_mode:", x$permission_mode, "\n")
  }
  invisible(x)
}

deputy_lead_routing_start_marker <-
  "<!-- deputy-lead-routing:v1:start -->"
deputy_lead_routing_end_marker <-
  "<!-- deputy-lead-routing:v1:end -->"

#' LeadAgent R6 Class
#'
#' @description
#' A LeadAgent is an agent that can delegate tasks to specialized sub-agents.
#' It automatically has a `delegate_to_agent` tool that allows it to spawn
#' sub-agents based on registered AgentDefinitions.
#'
#' @export
LeadAgent <- R6::R6Class(
  "LeadAgent",
  inherit = Agent,

  public = list(
    #' @description
    #' Create a new LeadAgent.
    #'
    #' @param chat An ellmer Chat object
    #' @param sub_agents List of [agent_definition()] objects
    #' @param tools Additional tools for the lead agent
    #' @param system_prompt System prompt for the lead agent
    #' @param permissions Permissions for the lead agent (also applied to sub-agents)
    #' @param usage_limits Optional [UsageLimits] for each lead-agent run.
    #' @param context_policy A [ContextPolicy] controlling automatic compaction
    #'   and durable offloading of large tool results for the lead agent and its
    #'   delegated agents.
    #' @param enable_file_checkpointing Whether to journal reversible file
    #'   preimages in one workspace journal shared by the lead agent and its
    #'   delegated agents.
    #' @param file_checkpoint_max_file_bytes Maximum bytes captured for one
    #'   file preimage. Defaults to 50 MiB.
    #' @param file_checkpoint_max_journal_bytes Maximum aggregate serialized
    #'   bytes for workspace checkpoint records, markers, metadata, and pending
    #'   captures. Defaults to 250 MiB.
    #' @param working_dir Working directory
    #' @param session_id Optional stable session identifier used for correlation.
    #'   A unique identifier is generated by default.
    #' @param run_context Immutable canonical product context inherited by lead
    #'   runs and delegated agents.
    #' @param agent_id Optional stable identifier for this LeadAgent instance.
    #' @param agent_name Optional human-readable LeadAgent name.
    #' @return A new `LeadAgent` object
    initialize = function(
      chat,
      sub_agents = list(),
      tools = list(),
      system_prompt = NULL,
      permissions = NULL,
      usage_limits = NULL,
      context_policy = ContextPolicy(),
      enable_file_checkpointing = FALSE,
      file_checkpoint_max_file_bytes = 50 * 1024^2,
      file_checkpoint_max_journal_bytes = 250 * 1024^2,
      working_dir = getwd(),
      session_id = NULL,
      run_context = list(),
      agent_id = NULL,
      agent_name = NULL
    ) {
      private$.sub_agent_defs <- normalize_agent_definitions(sub_agents)

      # Build enhanced system prompt
      enhanced_prompt <- private$build_lead_prompt(
        system_prompt,
        private$.sub_agent_defs
      )

      # Create the delegate tool
      delegate_tool <- private$create_delegate_tool()

      # Combine tools
      all_tools <- c(list(delegate_tool), tools)

      # Call parent constructor
      super$initialize(
        chat = chat,
        tools = all_tools,
        system_prompt = enhanced_prompt,
        permissions = permissions,
        usage_limits = usage_limits,
        context_policy = context_policy,
        enable_file_checkpointing = enable_file_checkpointing,
        file_checkpoint_max_file_bytes = file_checkpoint_max_file_bytes,
        file_checkpoint_max_journal_bytes = file_checkpoint_max_journal_bytes,
        working_dir = working_dir,
        session_id = session_id,
        run_context = run_context,
        agent_id = agent_id,
        agent_name = agent_name
      )
    },

    #' @description
    #' Register a new sub-agent definition.
    #'
    #' @param definition An [agent_definition()] object
    #' @return Invisible self
    register_sub_agent = function(definition) {
      if (!inherits(definition, "AgentDefinition")) {
        cli_abort("{.arg definition} must be an AgentDefinition object")
      }

      definition <- copy_agent_definition(definition)
      if (definition$name %in% names(private$.sub_agent_defs)) {
        cli_abort(
          "AgentDefinition {.val {definition$name}} is already registered"
        )
      }
      private$.sub_agent_defs[[definition$name]] <- definition

      # Replace only the generated routing section so compaction summaries,
      # skills, and hook-provided context remain intact.
      current_prompt <- private$.chat$get_system_prompt()
      new_prompt <- private$replace_lead_prompt(
        current_prompt,
        private$.sub_agent_defs
      )
      private$.chat$set_system_prompt(new_prompt)

      cli_alert_info("Registered sub-agent: {.val {definition$name}}")
      invisible(self)
    },

    #' @description
    #' Get available sub-agent names.
    #'
    #' @return Character vector of sub-agent names
    available_sub_agents = function() {
      unname(vapply(
        private$.sub_agent_defs,
        function(definition) definition$name,
        character(1)
      ))
    },

    #' @description
    #' Run independent, stateless responders concurrently.
    #'
    #' Each selected AgentDefinition gets a fresh conversation and at most one
    #' model request. Definitions with tools, skills, or MCP servers are
    #' rejected. This is tier-1 fan-out, not background tool-using agents.
    #' Results preserve input order, including failures and unstarted tasks.
    #' @param tasks A named character vector of tasks. Names select unique
    #'   registered AgentDefinitions.
    #' @param max_active Maximum simultaneous responders.
    #' @param mode Execution contract. Currently only `"stateless"` is supported.
    #' @param usage_limits Optional batch-wide [UsageLimits]. Unset fields
    #'   inherit the lead's defaults. Requests are reserved before dispatch;
    #'   token and cost ceilings are divided across each concurrent wave and
    #'   checked after responses, with possible overage by one response per
    #'   active responder.
    #' @param run_context Additional immutable context for the batch.
    #' @return A list with `mode`, named `results` ([AgentResult] or `NULL`),
    #'   named `errors`, named `status`, and an aggregate `run` ([AgentResult]).
    #'   `$last_run()` retains the aggregate run. The lead's conversation is
    #'   unchanged. Failed responders do not discard successful siblings.
    parallel_delegate = function(
      tasks,
      max_active = 2L,
      mode = "stateless",
      usage_limits = NULL,
      run_context = list()
    ) {
      promise <- self$parallel_delegate_async(
        tasks,
        max_active,
        mode,
        usage_limits,
        run_context
      )
      tryCatch(
        private$resolve_promise(promise),
        interrupt = function(condition) {
          self$interrupt()
          try(private$resolve_promise(promise), silent = TRUE)
          stop(condition)
        }
      )
    },

    #' @description
    #' Run stateless fan-out without blocking the R event loop.
    #' @param tasks,max_active,mode,usage_limits,run_context See
    #'   `$parallel_delegate()`.
    #' @return A promise resolving to the same batch result as
    #'   `$parallel_delegate()`. `$interrupt()` cancels queued work and asks
    #'   active responders to stop at their next supported provider boundary.
    parallel_delegate_async = function(
      tasks,
      max_active = 2L,
      mode = "stateless",
      usage_limits = NULL,
      run_context = list()
    ) {
      lead_parallel_delegate(
        self,
        tasks,
        max_active,
        mode,
        usage_limits,
        run_context
      )
    },

    #' @description
    #' List delegated sub-agent runs, including failures.
    #'
    #' @return Data frame with one row per sub-agent run
    list_subagents = function() {
      runs <- private$subagent_runs
      if (length(runs) == 0) {
        return(data.frame(
          agent_name = character(),
          agent_id = character(),
          parent_agent_id = character(),
          session_id = character(),
          run_id = character(),
          parent_run_id = character(),
          delegation_id = character(),
          tool_call_id = character(),
          task = character(),
          status = character(),
          started_at = as.POSIXct(character()),
          completed_at = as.POSIXct(character()),
          error = character(),
          stringsAsFactors = FALSE
        ))
      }

      do.call(
        rbind,
        lapply(runs, function(run) {
          data.frame(
            agent_name = run$agent_name,
            agent_id = run$agent_id %||% NA_character_,
            parent_agent_id = run$parent_agent_id %||% NA_character_,
            session_id = run$session_id %||% NA_character_,
            run_id = run$run_id %||% NA_character_,
            parent_run_id = run$parent_run_id %||% NA_character_,
            delegation_id = run$delegation_id %||% NA_character_,
            tool_call_id = run$tool_call_id %||% NA_character_,
            task = run$task,
            status = run$status %||% "completed",
            started_at = as.POSIXct(run$started_at, tz = "UTC"),
            completed_at = as.POSIXct(run$completed_at, tz = "UTC"),
            error = run$error %||% NA_character_,
            stringsAsFactors = FALSE
          )
        })
      )
    },

    #' @description
    #' Get retained results from delegated sub-agent runs.
    #'
    #' @param agent_name Optional sub-agent name filter
    #' @param delegation_id Optional delegation identifier filter
    #' @return List of [AgentResult] objects or `NULL` entries for failed runs
    get_subagent_results = function(agent_name = NULL, delegation_id = NULL) {
      runs <- private$subagent_runs
      if (!is.null(agent_name)) {
        runs <- Filter(
          function(run) identical(run$agent_name, agent_name),
          runs
        )
      }
      if (!is.null(delegation_id)) {
        runs <- Filter(
          function(run) identical(run$delegation_id, delegation_id),
          runs
        )
      }
      lapply(runs, function(run) run$agent_result)
    },

    #' @description
    #' Get stored turn history for delegated sub-agent runs.
    #'
    #' @param agent_name Optional sub-agent name filter
    #' @param session_id Optional sub-agent session id filter
    #' @return List of turn histories
    get_subagent_messages = function(agent_name = NULL, session_id = NULL) {
      runs <- private$subagent_runs
      if (!is.null(agent_name)) {
        runs <- Filter(
          function(run) identical(run$agent_name, agent_name),
          runs
        )
      }
      if (!is.null(session_id)) {
        runs <- Filter(
          function(run) identical(run$session_id, session_id),
          runs
        )
      }

      lapply(runs, function(run) run$turns)
    },

    #' @description
    #' Print the lead agent.
    print = function() {
      super$print()
      cat("  sub_agents:", length(private$.sub_agent_defs), "\n")
      if (length(private$.sub_agent_defs) > 0) {
        names <- self$available_sub_agents()
        cat("    ", paste(names, collapse = ", "), "\n")
      }
      invisible(self)
    }
  ),

  active = list(
    #' @field sub_agent_defs Read-only snapshot of registered AgentDefinitions.
    sub_agent_defs = function(value) {
      if (!missing(value)) {
        cli_abort("{.field sub_agent_defs} is read-only")
      }
      unname(lapply(private$.sub_agent_defs, copy_agent_definition))
    }
  ),

  private = list(
    # Build the lead agent's system prompt
    build_lead_prompt = function(base_prompt, sub_agents) {
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
    },

    replace_lead_prompt = function(full_prompt, sub_agents) {
      section <- private$build_lead_prompt(NULL, sub_agents)
      if (!is_nonempty_string(full_prompt)) {
        return(section)
      }

      start_marker <- deputy_lead_routing_start_marker
      end_marker <- deputy_lead_routing_end_marker
      start <- regexpr(start_marker, full_prompt, fixed = TRUE)
      if (start[[1L]] < 0L) {
        return(private$build_lead_prompt(full_prompt, sub_agents))
      }
      remainder <- substr(full_prompt, start[[1L]], nchar(full_prompt))
      end <- regexpr(end_marker, remainder, fixed = TRUE)
      if (end[[1L]] < 0L) {
        return(private$build_lead_prompt(full_prompt, sub_agents))
      }

      before <- substr(full_prompt, 1L, start[[1L]] - 1L)
      after_start <- start[[1L]] + end[[1L]] - 1L + attr(end, "match.length")
      after <- if (after_start > nchar(full_prompt)) {
        ""
      } else {
        substr(full_prompt, after_start, nchar(full_prompt))
      }
      paste0(before, section, after)
    },

    # Create the delegate_to_agent tool
    create_delegate_tool = function() {
      # Capture self for the closure
      lead_agent <- self

      ellmer::tool(
        fun = function(agent_name, task) {
          correlation <- private$claim_delegation()

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

          # Derive the child budget before creating it. The reservation is
          # recorded before this tool returns its promise, so concurrent tool
          # calls cannot all receive the same remaining lead-agent budget.
          child_usage_limits <- private$derive_subagent_usage_limits(def)
          sub_agent <- private$create_sub_agent(
            def,
            correlation,
            usage_limits = child_usage_limits
          )

          # Run the task
          cli::cli_alert_info("Delegating to {.val {agent_name}}: {task}")
          started_at <- Sys.time()

          lead_agent$hooks$fire(
            "SubagentStart",
            agent_name = agent_name,
            task = task,
            context = private$hook_context(
              agent_definition = def,
              tool_call_id = correlation$tool_call_id,
              parent_agent_id = correlation$parent_agent_id,
              parent_run_id = correlation$parent_run_id,
              child_agent_id = sub_agent$agent_id,
              child_agent_name = sub_agent$agent_name,
              child_run_context = sub_agent$run_context,
              delegation_id = correlation$delegation_id
            )
          )

          task_to_run <- task
          if (
            !is.null(def$initial_prompt) && nzchar(trimws(def$initial_prompt))
          ) {
            task_to_run <- paste(def$initial_prompt, task, sep = "\n\n")
          }

          # Record the run before invoking so failures aren't lost when
          # `tool_reject` short-circuits the rest of this closure.
          record_run <- function(
            status,
            result_text = NULL,
            error = NULL,
            usage = NULL,
            agent_result = NULL
          ) {
            child_run_id <- agent_result$run_id %||%
              sub_agent$.__enclos_env__$private$current_run_id
            private$subagent_runs <- c(
              private$subagent_runs,
              list(list(
                agent_name = agent_name,
                agent_id = sub_agent$agent_id,
                parent_agent_id = correlation$parent_agent_id,
                task = task,
                session_id = sub_agent$session_id(),
                run_id = child_run_id,
                parent_run_id = correlation$parent_run_id,
                delegation_id = correlation$delegation_id,
                tool_call_id = correlation$tool_call_id,
                run_context = agent_result$run_context %||%
                  sub_agent$run_context,
                started_at = started_at,
                completed_at = Sys.time(),
                status = status,
                result = result_text,
                error = error,
                usage = usage,
                agent_result = agent_result,
                turns = tryCatch(sub_agent$turns(), error = function(e) list())
              ))
            )
          }

          private$reserve_delegation_usage(
            correlation$delegation_id,
            child_usage_limits
          )
          reservation_active <- TRUE
          settle_usage <- function(usage) {
            if (!isTRUE(reservation_active)) {
              return(invisible(NULL))
            }
            private$release_delegation_usage(correlation$delegation_id)
            reservation_active <<- FALSE
            private$add_external_usage(usage)
            invisible(NULL)
          }

          promises::promise_resolve(NULL) |>
            promises::then(function(...) {
              sub_agent$run_async(task_to_run)
            }) |>
            promises::then(function(sub_result) {
              settle_usage(sub_result$usage)
              result <- sub_result$response

              lead_agent$hooks$fire(
                "SubagentStop",
                agent_name = agent_name,
                task = task,
                result = result,
                context = private$hook_context(
                  status = "completed",
                  tool_call_id = correlation$tool_call_id,
                  parent_agent_id = correlation$parent_agent_id,
                  parent_run_id = correlation$parent_run_id,
                  child_agent_id = sub_agent$agent_id,
                  child_agent_name = sub_agent$agent_name,
                  child_run_id = sub_result$run_id,
                  child_run_context = sub_result$run_context,
                  delegation_id = correlation$delegation_id
                )
              )

              record_run(
                status = "completed",
                result_text = result,
                usage = sub_result$usage,
                agent_result = sub_result
              )
              result
            }) |>
            promises::catch(function(e) {
              failed_usage <- sub_agent$.__enclos_env__$private$last_run_usage
              settle_usage(failed_usage)
              cli::cli_alert_danger(
                "Sub-agent {.val {agent_name}} failed: {e$message}"
              )
              record_run(
                status = "failed",
                error = e$message,
                usage = failed_usage,
                agent_result = NULL
              )
              child_run_id <- sub_agent$.__enclos_env__$private$current_run_id
              lead_agent$hooks$fire(
                "SubagentStop",
                agent_name = agent_name,
                task = task,
                result = NULL,
                context = private$hook_context(
                  status = "failed",
                  error = e$message,
                  tool_call_id = correlation$tool_call_id,
                  parent_agent_id = correlation$parent_agent_id,
                  parent_run_id = correlation$parent_run_id,
                  child_agent_id = sub_agent$agent_id,
                  child_agent_name = sub_agent$agent_name,
                  child_run_id = child_run_id,
                  child_run_context = sub_agent$run_context,
                  delegation_id = correlation$delegation_id
                )
              )
              ellmer::tool_reject(paste0(
                "Sub-agent '",
                agent_name,
                "' failed.\n",
                "Error: ",
                e$message
              ))
            })
        },
        name = "delegate_to_agent",
        description = "Delegate a task to a specialized sub-agent. The sub-agent will complete the task and return results.",
        arguments = list(
          agent_name = ellmer::type_string(
            "Name of the sub-agent to delegate to"
          ),
          task = ellmer::type_string("The task to delegate to the sub-agent")
        ),
        annotations = ellmer::tool_annotations(
          read_only_hint = FALSE,
          destructive_hint = FALSE,
          open_world_hint = FALSE,
          idempotent_hint = FALSE
        )
      )
    },

    # Create a sub-agent from a definition
    create_sub_agent = function(
      def,
      correlation = NULL,
      usage_limits = NULL,
      stateless = FALSE
    ) {
      correlation <- correlation %||% private$claim_delegation()

      # Get the model to use
      if (def$model == "inherit") {
        # Clone the parent chat to get the same provider/model config,
        # then clear conversation history so the sub-agent starts fresh.
        sub_chat <- tryCatch(
          {
            cloned <- private$.chat$clone(deep = TRUE)
            if (identical(cloned, private$.chat)) {
              cli_abort("Chat cloning must return an independent instance")
            }
            clear_chat_tool_callbacks(cloned)
            cloned$set_turns(list())
            # The child definition chooses its tools. Inherited provider
            # configuration must not import the parent's executable registry.
            cloned$set_tools(list())
            cloned
          },
          error = function(e) {
            cli_abort(c(
              "Could not inherit model from parent for sub-agent {.val {def$name}}",
              "x" = e$message,
              "i" = "Please specify an explicit {.arg model} in {.fn agent_definition}"
            ))
          }
        )
      } else {
        # Use the specified model string (e.g., "openai/gpt-4o", "anthropic/claude-sonnet-4-5-20250929")
        sub_chat <- tryCatch(
          ellmer::chat(def$model),
          error = function(e) {
            cli_abort(c(
              "Failed to create chat for sub-agent {.val {def$name}}",
              "x" = "Invalid model: {.val {def$model}}",
              "i" = e$message
            ))
          }
        )
      }

      sub_tools <- private$filter_disallowed_tools(
        def$tools,
        def$disallowed_tools
      )
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

      # Create the sub-agent
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
        context_policy = if (stateless) {
          ContextPolicy(max_tokens = NULL, max_tool_result_bytes = NULL)
        } else {
          self$context_policy
        },
        working_dir = self$working_dir,
        session_id = new_deputy_id("session_"),
        run_context = child_run_context,
        agent_name = def$name
      )
      sub_agent$.__enclos_env__$private$.parent_agent_id <-
        correlation$parent_agent_id
      sub_agent$.__enclos_env__$private$.parent_run_id <-
        correlation$parent_run_id
      sub_agent$.__enclos_env__$private$.delegation_id <-
        correlation$delegation_id
      # A checkpoint describes workspace state, not one agent's private
      # execution history. Delegated agents therefore write to the exact same
      # journal as the lead so a lead-level rewind includes child mutations.
      if (!stateless && !is.null(private$.file_checkpoints)) {
        sub_agent$.__enclos_env__$private$.file_checkpoints <-
          private$.file_checkpoints
      }
      # Load any skills
      for (skill in def$skills) {
        sub_agent$load_skill(skill)
      }

      if (!is.null(def$mcp_servers) && length(def$mcp_servers) > 0) {
        sub_agent$load_mcp(servers = def$mcp_servers)
      }

      sub_agent
    },

    derive_subagent_permissions = function(def) {
      existing <- self$permissions
      requested_mode <- def$permission_mode %||% existing$mode
      allowed_modes <- permission_mode_targets(existing$mode)
      if (!requested_mode %in% allowed_modes) {
        cli_abort(c(
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
        ))
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

      Permissions$new(
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
    },

    derive_subagent_usage_limits = function(def) {
      limits <- private$current_usage_limits %||% self$usage_limits
      current <- if (isTRUE(private$run_active)) {
        private$current_run_usage()
      } else {
        AgentUsage()
      }
      usage_fields <- c(
        max_requests = "requests",
        max_tool_calls = "tool_calls",
        max_input_tokens = "input_tokens",
        max_output_tokens = "output_tokens",
        max_total_tokens = "total_tokens",
        max_cost_usd = "cost_usd"
      )
      reserved <- private$reserved_delegation_usage()
      remaining <- lapply(names(usage_fields), function(limit_field) {
        limit <- limits[[limit_field]]
        if (is.null(limit)) {
          return(NULL)
        }
        max(
          0,
          limit -
            current[[usage_fields[[limit_field]]]] -
            reserved[[limit_field]]
        )
      })
      names(remaining) <- names(usage_fields)
      if (!is.null(def$max_requests)) {
        remaining$max_requests <- if (is.null(remaining$max_requests)) {
          def$max_requests
        } else {
          min(remaining$max_requests, def$max_requests)
        }
      }

      do.call(
        UsageLimits,
        c(remaining, list(on_exceed = limits$on_exceed))
      )
    },

    reserve_delegation_usage = function(delegation_id, limits) {
      fields <- c(
        "max_requests",
        "max_tool_calls",
        "max_input_tokens",
        "max_output_tokens",
        "max_total_tokens",
        "max_cost_usd"
      )
      private$delegation_usage_reservations[[delegation_id]] <- vapply(
        fields,
        function(field) limits[[field]] %||% 0,
        numeric(1)
      )
      invisible(NULL)
    },

    release_delegation_usage = function(delegation_id) {
      private$delegation_usage_reservations[[delegation_id]] <- NULL
      invisible(NULL)
    },

    reserved_delegation_usage = function() {
      fields <- c(
        "max_requests",
        "max_tool_calls",
        "max_input_tokens",
        "max_output_tokens",
        "max_total_tokens",
        "max_cost_usd"
      )
      reserved <- stats::setNames(numeric(length(fields)), fields)
      for (reservation in private$delegation_usage_reservations) {
        reserved <- reserved + reservation[fields]
      }
      reserved
    },

    prepare_cloned_tool = function(tool) {
      name <- read_optional_value(
        function() tool@name,
        validator = is_nonempty_string
      )
      if (
        identical(name$status, "present") &&
          identical(name$value, "delegate_to_agent")
      ) {
        return(private$adapt_tool(private$create_delegate_tool()))
      }
      private$adapt_tool(tool)
    },

    filter_disallowed_tools = function(tools, disallowed_tools) {
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
    },

    .sub_agent_defs = list(),
    subagent_runs = list(),
    delegation_usage_reservations = list()
  )
)
