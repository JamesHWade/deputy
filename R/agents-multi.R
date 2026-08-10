# Multi-agent orchestration for deputy

#' Create an Agent Definition
#'
#' @description
#' AgentDefinition describes a specialized agent that can be used by a lead
#' agent to delegate tasks. It bundles together a system prompt, tools, and
#' metadata about what the agent can do.
#'
#' @param name Unique name for this agent type
#' @param description Brief description of what this agent does (shown to lead agent)
#' @param prompt System prompt for this agent
#' @param tools Optional list of tools for this agent
#' @param model Model to use (default: "inherit" uses parent's model)
#' @param skills Optional list of skills to load
#' @param disallowed_tools Optional tool denylist for this sub-agent
#' @param memory Optional memory text appended to this sub-agent's prompt
#' @param mcp_servers Optional MCP server names to load for this sub-agent
#' @param initial_prompt Optional text prepended to delegated tasks
#' @param max_turns Optional non-negative whole-number sub-agent request limit
#' @param background Logical SDK-compatible metadata flag
#' @param effort Optional reasoning effort metadata
#' @param permission_mode Optional permission mode. For non-bypass lead agents,
#'   this must match the lead mode (with `"default"` and `"auto"` treated as
#'   equivalent); use `disallowed_tools` and `max_turns` to tighten a child
#'   policy. A bypass lead may select any mode.
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
  max_turns = NULL,
  background = FALSE,
  effort = NULL,
  permission_mode = NULL
) {
  if (!is.null(permission_mode)) {
    permission_mode <- validate_permission_mode_value(
      permission_mode,
      arg = "permission_mode"
    )
  }
  if (!is.null(max_turns)) {
    max_turns <- validate_usage_limit(max_turns, "max_turns", integer = TRUE)
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
      max_turns = max_turns,
      background = isTRUE(background),
      effort = effort,
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
    #' @field sub_agent_defs List of AgentDefinition objects
    sub_agent_defs = NULL,

    #' @description
    #' Create a new LeadAgent.
    #'
    #' @param chat An ellmer Chat object
    #' @param sub_agents List of [agent_definition()] objects
    #' @param tools Additional tools for the lead agent
    #' @param system_prompt System prompt for the lead agent
    #' @param permissions Permissions for the lead agent (also applied to sub-agents)
    #' @param usage_limits Optional [UsageLimits] for each lead-agent run.
    #' @param enable_file_checkpointing Whether to journal reversible file
    #'   preimages in one workspace journal shared by the lead agent and its
    #'   delegated agents.
    #' @param file_checkpoint_max_file_bytes Maximum bytes captured for one
    #'   file preimage. Defaults to 50 MiB.
    #' @param file_checkpoint_max_journal_bytes Maximum aggregate serialized
    #'   bytes for workspace checkpoint records, markers, metadata, and pending
    #'   captures. Defaults to 250 MiB.
    #' @param working_dir Working directory
    #' @param setting_sources Optional Claude-style setting sources
    #' @param settings Optional pre-loaded settings list from claude_settings_load()
    #' @return A new `LeadAgent` object
    initialize = function(
      chat,
      sub_agents = list(),
      tools = list(),
      system_prompt = NULL,
      permissions = NULL,
      usage_limits = NULL,
      enable_file_checkpointing = FALSE,
      file_checkpoint_max_file_bytes = 50 * 1024^2,
      file_checkpoint_max_journal_bytes = 250 * 1024^2,
      working_dir = getwd(),
      setting_sources = NULL,
      settings = NULL
    ) {
      # Validate sub-agent definitions
      for (def in sub_agents) {
        if (!inherits(def, "AgentDefinition")) {
          cli_abort("All sub_agents must be AgentDefinition objects")
        }
      }

      self$sub_agent_defs <- sub_agents

      # Build enhanced system prompt
      enhanced_prompt <- private$build_lead_prompt(system_prompt, sub_agents)

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
        enable_file_checkpointing = enable_file_checkpointing,
        file_checkpoint_max_file_bytes = file_checkpoint_max_file_bytes,
        file_checkpoint_max_journal_bytes = file_checkpoint_max_journal_bytes,
        working_dir = working_dir,
        setting_sources = setting_sources,
        settings = settings
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

      self$sub_agent_defs <- c(self$sub_agent_defs, list(definition))

      # Rebuild and update system prompt to include new sub-agent
      # Extract base prompt (before sub-agent section) if possible
      current_prompt <- self$chat$get_system_prompt()
      base_prompt <- private$extract_base_prompt(current_prompt)
      new_prompt <- private$build_lead_prompt(base_prompt, self$sub_agent_defs)
      self$chat$set_system_prompt(new_prompt)

      cli_alert_info("Registered sub-agent: {.val {definition$name}}")
      invisible(self)
    },

    #' @description
    #' Get available sub-agent names.
    #'
    #' @return Character vector of sub-agent names
    available_sub_agents = function() {
      sapply(self$sub_agent_defs, function(d) d$name)
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
          session_id = character(),
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
            session_id = run$session_id %||% NA_character_,
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
      cat("  sub_agents:", length(self$sub_agent_defs), "\n")
      if (length(self$sub_agent_defs) > 0) {
        names <- self$available_sub_agents()
        cat("    ", paste(names, collapse = ", "), "\n")
      }
      invisible(self)
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
          ""
        )
      }

      paste(lines, collapse = "\n")
    },

    # Extract base prompt (before sub-agent section) from full prompt
    extract_base_prompt = function(full_prompt) {
      if (is.null(full_prompt) || nchar(full_prompt) == 0) {
        return(NULL)
      }

      # Look for the sub-agent section marker
      marker <- "# Available Sub-Agents"
      marker_pos <- regexpr(marker, full_prompt, fixed = TRUE)

      if (marker_pos > 0) {
        # Extract everything before the marker
        base <- substr(full_prompt, 1, marker_pos - 1)
        # Trim trailing whitespace
        base <- sub("\\s+$", "", base)
        if (nchar(base) == 0) {
          return(NULL)
        }
        return(base)
      }

      # No marker found, return the full prompt as base
      full_prompt
    },

    # Create the delegate_to_agent tool
    create_delegate_tool = function() {
      # Capture self for the closure
      lead_agent <- self

      ellmer::tool(
        fun = function(agent_name, task) {
          # Find the agent definition
          def <- NULL
          for (d in lead_agent$sub_agent_defs) {
            if (d$name == agent_name) {
              def <- d
              break
            }
          }

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

          # Create the sub-agent
          sub_agent <- private$create_sub_agent(def)

          # Run the task
          cli::cli_alert_info("Delegating to {.val {agent_name}}: {task}")
          started_at <- Sys.time()

          lead_agent$hooks$fire(
            "SubagentStart",
            agent_name = agent_name,
            task = task,
            context = list(
              working_dir = lead_agent$working_dir,
              agent_definition = def
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
            usage = NULL
          ) {
            private$subagent_runs <- c(
              private$subagent_runs,
              list(list(
                agent_name = agent_name,
                task = task,
                session_id = sub_agent$session_id(),
                started_at = started_at,
                completed_at = Sys.time(),
                status = status,
                result = result_text,
                error = error,
                usage = usage,
                turns = tryCatch(sub_agent$turns(), error = function(e) list())
              ))
            )
          }

          result <- tryCatch(
            {
              sub_result <- sub_agent$run_sync(
                task_to_run
              )
              private$add_external_usage(sub_result$usage)
              sub_result$response
            },
            error = function(e) {
              failed_usage <- sub_agent$.__enclos_env__$private$last_run_usage
              private$add_external_usage(failed_usage)
              cli::cli_alert_danger(
                "Sub-agent {.val {agent_name}} failed: {e$message}"
              )
              record_run(
                status = "failed",
                error = e$message,
                usage = failed_usage
              )
              lead_agent$hooks$fire(
                "SubagentStop",
                agent_name = agent_name,
                task = task,
                result = NULL,
                context = list(
                  working_dir = lead_agent$working_dir,
                  status = "failed",
                  error = e$message
                )
              )
              ellmer::tool_reject(paste0(
                "Sub-agent '",
                agent_name,
                "' failed.\n",
                "Error: ",
                e$message
              ))
            }
          )

          # Fire SubagentStop hook (success path)
          lead_agent$hooks$fire(
            "SubagentStop",
            agent_name = agent_name,
            task = task,
            result = result,
            context = list(
              working_dir = lead_agent$working_dir,
              status = "completed"
            )
          )

          record_run(
            status = "completed",
            result_text = result,
            usage = sub_result$usage
          )

          result
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
          destructive_hint = FALSE
        )
      )
    },

    # Create a sub-agent from a definition
    create_sub_agent = function(def) {
      # Get the model to use
      if (def$model == "inherit") {
        # Clone the parent chat to get the same provider/model config,
        # then clear conversation history so the sub-agent starts fresh.
        sub_chat <- tryCatch(
          {
            cloned <- self$chat$clone()
            cloned$set_turns(list())
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
      sub_agent <- Agent$new(
        chat = sub_chat,
        tools = sub_tools,
        system_prompt = sub_prompt,
        permissions = sub_permissions,
        usage_limits = private$derive_subagent_usage_limits(def),
        working_dir = self$working_dir
      )
      # A checkpoint describes workspace state, not one agent's private
      # execution history. Delegated agents therefore write to the exact same
      # journal as the lead so a lead-level rewind includes child mutations.
      if (!is.null(private$.file_checkpoints)) {
        sub_agent$.__enclos_env__$private$.file_checkpoints <-
          private$.file_checkpoints
      }
      sub_agent$configure_sdk_compat(list(
        persist_session = FALSE,
        session_store_dir = session_store_default_dir(),
        session_id = generate_session_id()
      ))

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
      allowed_modes <- switch(
        existing$mode,
        bypassPermissions = PermissionMode,
        default = c("default", "auto"),
        auto = c("default", "auto"),
        acceptEdits = "acceptEdits",
        dontAsk = "dontAsk",
        plan = "plan",
        readonly = "readonly"
      )
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
            ", then tighten the child with disallowed_tools or max_turns."
          )
        ))
      }
      denylist <- unique(c(existing$tool_denylist, def$disallowed_tools))
      Permissions$new(
        mode = requested_mode,
        file_read = existing$file_read,
        file_write = existing$file_write,
        bash = existing$bash,
        r_code = existing$r_code,
        web = existing$web,
        install_packages = existing$install_packages,
        max_turns = def$max_turns %||% existing$max_turns,
        max_cost_usd = existing$max_cost_usd,
        can_use_tool = existing$can_use_tool,
        tool_allowlist = existing$tool_allowlist,
        tool_denylist = denylist,
        permission_prompt_tool_name = existing$permission_prompt_tool_name
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
      remaining <- lapply(names(usage_fields), function(limit_field) {
        limit <- limits[[limit_field]]
        if (is.null(limit)) {
          return(NULL)
        }
        max(0, limit - current[[usage_fields[[limit_field]]]])
      })
      names(remaining) <- names(usage_fields)
      if (!is.null(def$max_turns)) {
        remaining$max_requests <- if (is.null(remaining$max_requests)) {
          def$max_turns
        } else {
          min(remaining$max_requests, def$max_turns)
        }
      }

      do.call(
        UsageLimits,
        c(remaining, list(on_exceed = limits$on_exceed))
      )
    },

    filter_disallowed_tools = function(tools, disallowed_tools) {
      if (is.null(disallowed_tools) || length(disallowed_tools) == 0) {
        return(tools)
      }

      disallowed <- tolower(trimws(as.character(disallowed_tools)))
      Filter(
        function(tool) {
          name <- tryCatch(tool@name, error = function(e) NULL)
          if (is.null(name)) {
            return(TRUE)
          }
          !tolower(name) %in% disallowed
        },
        tools
      )
    },

    subagent_runs = list()
  )
)

#' Create a simple delegation agent
#'
#' @description
#' Convenience function to create a LeadAgent with common sub-agents for
#' code-related tasks.
#'
#' @param chat An ellmer Chat object
#' @param permissions Optional permissions
#' @return A [LeadAgent] object
#'
#' @examples
#' \dontrun{
#' agent <- agent_with_delegation(
#'   chat = ellmer::chat("openai/gpt-4o")
#' )
#'
#' result <- agent$run_sync("Review the code in main.R and suggest improvements")
#' }
#'
#' @export
agent_with_delegation <- function(chat, permissions = NULL) {
  # Define common sub-agents
  code_reader <- agent_definition(
    name = "code_reader",
    description = "Reads and explains code files. Good for understanding what code does.",
    prompt = "You are a code reading expert. Read files carefully and explain what the code does clearly and concisely.",
    tools = list(tool_read_file, tool_list_files)
  )

  code_analyzer <- agent_definition(
    name = "code_analyzer",
    description = "Analyzes code for bugs, issues, and improvements. Good for code review.",
    prompt = "You are a code analysis expert. Look for bugs, potential issues, and suggest improvements. Be specific and actionable.",
    tools = list(tool_read_file, tool_list_files)
  )

  LeadAgent$new(
    chat = chat,
    sub_agents = list(code_reader, code_analyzer),
    tools = tools_file(),
    permissions = permissions
  )
}
