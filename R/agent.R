# Agent class for deputy

#' Agent R6 Class
#'
#' @description
#' The main class for creating AI agents that can use tools to accomplish tasks.
#' Agent wraps an ellmer Chat object and adds agentic capabilities including
#' multi-turn execution, permission enforcement, and streaming output.
#'
#' @section Skill Methods:
#' The following methods are added dynamically when the package loads:
#'
#' \describe{
#'   \item{`$load_skill(skill, allow_conflicts = FALSE)`}{Load a [Skill] into
#'     the agent. The `skill` parameter can be a Skill object or path to a
#'     skill directory. If `allow_conflicts` is FALSE (default), an error is
#'     thrown when skill tools conflict with existing tools. Set to TRUE to
#'     allow overwriting. Returns invisible self.}
#'   \item{`$skills()`}{Get a named list of loaded [Skill] objects.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Create an agent with file tools
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = tools_file()
#' )
#'
#' # Run a task with streaming output
#' for (event in agent$run("List files in the current directory")) {
#'   if (event$type == "text") cat(event$text)
#' }
#'
#' # Or use the blocking convenience method
#' result <- agent$run_sync("List files")
#' print(result$response)
#' }
Agent <- R6::R6Class(
  "Agent",

  public = list(
    #' @field chat The wrapped ellmer Chat object
    chat = NULL,

    #' @field permissions Permission policy for the agent
    permissions = NULL,

    #' @field working_dir Working directory for file operations
    working_dir = NULL,

    #' @field hooks Hook registry for lifecycle events
    hooks = NULL,

    #' @description
    #' Create a new Agent.
    #'
    #' @param chat An ellmer Chat object created by `ellmer::chat()` or
    #'   provider-specific functions like `ellmer::chat_openai()`.
    #' @param tools A list of tools created with `ellmer::tool()`. See
    #'   [tools_file()] and [tools_code()] for built-in tool bundles.
    #' @param system_prompt Optional system prompt. If provided, overrides the
    #'   chat object's existing system prompt.
    #' @param permissions A [Permissions] object controlling what the agent can do.
    #'   Defaults to [permissions_standard()].
    #' @param working_dir Working directory for file operations. Defaults to
    #'   current directory.
    #' @return A new `Agent` object
    initialize = function(
      chat,
      tools = list(),
      system_prompt = NULL,
      permissions = NULL,
      working_dir = getwd()
    ) {
      validate_chat(chat)

      self$chat <- chat
      self$permissions <- permissions %||% permissions_standard(working_dir)
      self$working_dir <- working_dir
      self$hooks <- HookRegistry$new()

      # Override system prompt if provided
      if (!is.null(system_prompt)) {
        self$chat$set_system_prompt(system_prompt)
      }

      # Register tools
      if (length(tools) > 0) {
        self$chat$register_tools(tools)
      }

      # Wire up ellmer's callbacks for permission/hook enforcement
      self$chat$on_tool_request(private$on_tool_request)
      self$chat$on_tool_result(private$on_tool_result)

      invisible(self)
    },

    #' @description
    #' Run an agentic task with streaming output.
    #'
    #' Returns a generator that yields [AgentEvent] objects as the agent works.
    #' The agent will continue until the task is complete, max_turns is reached,
    #' or the cost limit is exceeded.
    #'
    #' @param task The task for the agent to perform
    #' @param max_turns Maximum number of turns (default: from permissions)
    #' @return A generator yielding [AgentEvent] objects
    run = function(task, max_turns = NULL) {
      max_turns <- max_turns %||% self$permissions$max_turns %||% 25

      # Create and return the generator
      private$create_run_generator(task, max_turns)
    },

    #' @description
    #' Run an agentic task and block until completion.
    #'
    #' Convenience wrapper around `run()` that collects all events and returns
    #' an [AgentResult].
    #'
    #' @param task The task for the agent to perform
    #' @param max_turns Maximum number of turns (default: from permissions)
    #' @return An [AgentResult] object
    run_sync = function(task, max_turns = NULL) {
      start_time <- Sys.time()

      # Collect all events from the generator
      gen <- self$run(task, max_turns)
      events <- list()

      # Iterate through the generator
      # Note: coro generators return coro::exhausted() when done, not NULL
      repeat {
        event <- tryCatch(
          gen(),
          error = function(e) {
            if (grepl("generator has been exhausted", e$message, fixed = TRUE)) {
              return(coro::exhausted())
            }
            stop(e)
          }
        )

        # Check for exhaustion (coro returns special exhausted symbol, not NULL)
        if (coro::is_exhausted(event)) {
          break
        }

        events <- c(events, list(event))

        # Also break on stop event to avoid extra generator call
        if (inherits(event, "AgentEvent") && event$type == "stop") {
          break
        }
      }

      # Find the stop event for metadata
      stop_event <- Find(function(e) e$type == "stop", events)

      duration <- as.numeric(Sys.time() - start_time, units = "secs")

      AgentResult$new(
        response = private$get_last_response(),
        turns = self$chat$get_turns(),
        cost = stop_event$cost %||% self$cost(),
        events = events,
        duration = duration,
        stop_reason = stop_event$reason %||% "complete"
      )
    },

    #' @description
    #' Register a tool with the agent.
    #'
    #' @param tool A tool created with `ellmer::tool()`
    #' @return Invisible self for chaining
    register_tool = function(tool) {
      self$chat$register_tool(tool)
      invisible(self)
    },

    #' @description
    #' Register multiple tools with the agent.
    #'
    #' @param tools A list of tools created with `ellmer::tool()`
    #' @return Invisible self for chaining
    register_tools = function(tools) {
      self$chat$register_tools(tools)
      invisible(self)
    },

    #' @description
    #' Add a hook to the agent.
    #'
    #' Hooks are called at specific points during agent execution and can
    #' modify behavior (e.g., deny tool calls, log events).
    #'
    #' @param hook A [HookMatcher] object
    #' @return Invisible self for chaining
    #'
    #' @examples
    #' \dontrun{
    #' # Add a hook to block dangerous bash commands
    #' agent$add_hook(hook_block_dangerous_bash())
    #'
    #' # Add a custom PreToolUse hook
    #' agent$add_hook(HookMatcher$new(
    #'   event = "PreToolUse",
    #'   pattern = "^write_file$",
    #'   callback = function(tool_name, tool_input, context) {
    #'     cli::cli_alert_info("Writing to: {tool_input$path}")
    #'     HookResultPreToolUse(permission = "allow")
    #'   }
    #' ))
    #' }
    add_hook = function(hook) {
      if (!inherits(hook, "HookMatcher")) {
        cli_abort("{.arg hook} must be a HookMatcher object")
      }
      self$hooks$add(hook)
      invisible(self)
    },

    #' @description
    #' Get the conversation history.
    #'
    #' @return A list of Turn objects
    turns = function() {
      self$chat$get_turns()
    },

    #' @description
    #' Get the last turn in the conversation.
    #'
    #' @param role Role to filter by ("assistant", "user", or "system")
    #' @return A Turn object or NULL
    last_turn = function(role = "assistant") {
      self$chat$last_turn(role = role)
    },

    #' @description
    #' Get cost information for the conversation.
    #'
    #' @return A list with input, output, cached, and total token costs
    cost = function() {
      tokens <- self$chat$get_tokens()
      list(
        input = sum(tokens$input, na.rm = TRUE),
        output = sum(tokens$output, na.rm = TRUE),
        cached = sum(tokens$cached_input, na.rm = TRUE),
        total = sum(tokens$cost, na.rm = TRUE)
      )
    },

    #' @description
    #' Get provider information.
    #'
    #' @return A list with provider name and model
    provider = function() {
      provider <- self$chat$get_provider()
      # Handle both S7 objects (@ access) and regular lists ($ access)
      name <- tryCatch(provider@name, error = function(e) {
        provider$name %||% "unknown"
      })
      model <- tryCatch(provider@model, error = function(e) {
        provider$model %||% "unknown"
      })
      list(
        name = name,
        model = model
      )
    },

    #' @description
    #' Save the current session to an RDS file.
    #'
    #' @param path Path to save the session
    #' @return Invisible path
    #'
    #' @details
    #' The session file contains:
    #' - Conversation turns
    #' - System prompt
    #' - Tool definitions (serialized)
    #' - Permissions configuration
    #' - Working directory
    #' - Metadata (timestamp, version, provider info)
    save_session = function(path) {
      # Get tools as a list for serialization
      tools_list <- self$chat$get_tools()

      session <- list(
        turns = self$chat$get_turns(),
        system_prompt = self$chat$get_system_prompt(),
        tool_names = names(tools_list),
        tools = tools_list, # Store actual tool objects
        permissions = self$permissions,
        working_dir = self$working_dir,
        loaded_skills = names(private$loaded_skills),
        hooks_count = self$hooks$count(),
        metadata = list(
          saved_at = Sys.time(),
          deputy_version = as.character(utils::packageVersion("deputy")),
          provider = self$provider(),
          session_format_version = 2L # Track format for compatibility
        )
      )
      saveRDS(session, path)
      cli_alert_success("Session saved to {.path {path}}")
      invisible(path)
    },

    #' @description
    #' Load a session from an RDS file.
    #'
    #' @param path Path to the session file
    #' @param restore_tools If TRUE (default), restore tools from session
    #' @return Invisible self
    #'
    #' @details
    #' Note: Hooks are NOT restored from sessions as they contain
    #' function closures that may not serialize correctly.
    load_session = function(path, restore_tools = TRUE) {
      # Validate file exists
      if (!file.exists(path)) {
        abort_session_load(
          "Session file not found: {.path {path}}",
          path = path
        )
      }

      # Load with error handling
      session <- tryCatch(
        readRDS(path),
        error = function(e) {
          abort_session_load(
            c(
              "Failed to load session file",
              "x" = e$message
            ),
            path = path,
            parent = e
          )
        }
      )

      # Validate session structure
      required_fields <- c(
        "turns",
        "system_prompt",
        "permissions",
        "working_dir"
      )
      missing <- setdiff(required_fields, names(session))
      if (length(missing) > 0) {
        abort_session_load(
          c(
            "Invalid session file - missing required fields",
            "x" = "Missing: {.val {missing}}"
          ),
          path = path
        )
      }

      # Check version compatibility
      if (!is.null(session$metadata$deputy_version)) {
        current_version <- as.character(utils::packageVersion("deputy"))
        loaded_version <- session$metadata$deputy_version
        if (loaded_version != current_version) {
          cli_warn(c(
            "Session from different deputy version",
            "i" = "Session version: {loaded_version}",
            "i" = "Current version: {current_version}",
            "i" = "This may cause compatibility issues"
          ))
        }
      }

      # Restore turns
      self$chat$set_turns(session$turns)

      # Restore system prompt
      if (!is.null(session$system_prompt)) {
        self$chat$set_system_prompt(session$system_prompt)
      }

      # Restore tools if available and requested
      if (
        restore_tools && !is.null(session$tools) && length(session$tools) > 0
      ) {
        tryCatch(
          {
            self$chat$register_tools(session$tools)
            cli_alert_info("Restored {length(session$tools)} tools")
          },
          error = function(e) {
            cli_warn(c(
              "Could not restore tools from session",
              "x" = e$message,
              "i" = "You may need to re-register tools manually"
            ))
          }
        )
      } else if (
        !is.null(session$tool_names) && length(session$tool_names) > 0
      ) {
        cli_warn(c(
          "Session contains tool references but not tool definitions",
          "i" = "Tools not restored: {.val {session$tool_names}}",
          "i" = "Re-register tools manually or use a newer session format"
        ))
      }

      # Restore permissions and working dir
      if (!is.null(session$permissions)) {
        self$permissions <- session$permissions
      }
      if (!is.null(session$working_dir)) {
        self$working_dir <- session$working_dir
      }

      # Note about skills and hooks
      if (
        !is.null(session$loaded_skills) && length(session$loaded_skills) > 0
      ) {
        cli_alert_info("Session had skills: {.val {session$loaded_skills}}")
        cli_alert_info("Skills must be reloaded manually with $load_skill()")
      }
      if (!is.null(session$hooks_count) && session$hooks_count > 0) {
        cli_alert_info("Session had {session$hooks_count} hooks (not restored)")
        cli_alert_info("Re-add hooks manually with $add_hook()")
      }

      cli_alert_success("Session loaded from {.path {path}}")
      invisible(self)
    },

    #' @description
    #' Compact the conversation history to reduce context size.
    #'
    #' This method uses the LLM to generate a meaningful summary of older
    #' conversation turns, then replaces them with the summary appended to
    #' the system prompt. This preserves important context while reducing
    #' token usage.
    #'
    #' @param keep_last Number of recent turns to keep uncompacted (default: 4)
    #' @param summary Optional custom summary to use instead of auto-generating.
    #'   If NULL, the LLM will generate a summary focusing on key decisions,
    #'   findings, files discussed, and task progress.
    #' @return Invisible self
    #'
    #' @details
    #' The compaction process:
    #' 1. Fires the PreCompact hook (can cancel or provide custom summary)
    #' 2. If no custom summary, uses LLM to summarize compacted turns
    #' 3. Appends summary to system prompt under "Previous Conversation Summary"
    #' 4. Keeps only the most recent `keep_last` turns
    #'
    #' If LLM summarization fails (e.g., no API key), falls back to a simple
    #' text-based summary with truncated turn contents.
    compact = function(keep_last = 4, summary = NULL) {
      turns <- self$chat$get_turns()

      if (length(turns) <= keep_last) {
        cli_alert_info(
          "Not enough turns to compact (have {length(turns)}, keep_last = {keep_last})"
        )
        return(invisible(self))
      }

      # Determine which turns to compact
      compact_count <- length(turns) - keep_last
      turns_to_compact <- turns[1:compact_count]
      turns_to_keep <- turns[(compact_count + 1):length(turns)]

      # Fire PreCompact hook
      hook_result <- self$hooks$fire(
        "PreCompact",
        turns_to_compact = turns_to_compact,
        turns_to_keep = turns_to_keep,
        context = list(
          working_dir = self$working_dir,
          total_turns = length(turns),
          compact_count = compact_count
        )
      )

      # Check if hook wants to cancel compaction
      if (!is.null(hook_result) && isFALSE(hook_result$continue)) {
        cli_alert_info("Compaction cancelled by hook")
        return(invisible(self))
      }

      # Generate summary if not provided
      if (is.null(summary)) {
        # Check if hook provided a custom summary
        if (!is.null(hook_result) && !is.null(hook_result$summary)) {
          summary <- hook_result$summary
        } else {
          # Use LLM to generate a meaningful summary
          summary <- private$generate_compaction_summary(turns_to_compact)
        }
      }

      # Add summary to system prompt and keep only recent turns
      current_system <- self$chat$get_system_prompt() %||% ""
      new_system <- paste0(
        current_system,
        "\n\n## Previous Conversation Summary\n",
        summary
      )

      self$chat$set_system_prompt(new_system)
      self$chat$set_turns(turns_to_keep)

      cli_alert_success(
        "Compacted {compact_count} turns, keeping {length(turns_to_keep)}"
      )
      invisible(self)
    },

    #' @description
    #' Print the agent configuration.
    print = function() {
      provider_info <- self$provider()
      tools <- self$chat$get_tools()

      cat("<Agent>\n")
      cat("  provider:", provider_info$name, "\n")
      cat("  model:", provider_info$model, "\n")
      cat("  tools:", length(tools), "registered\n")
      if (length(tools) > 0) {
        tool_names <- names(tools)
        if (length(tool_names) > 5) {
          tool_names <- c(tool_names[1:5], "...")
        }
        cat("    ", paste(tool_names, collapse = ", "), "\n")
      }
      cat("  working_dir:", self$working_dir, "\n")
      cat("  permissions:\n")
      cat("    mode:", self$permissions$mode, "\n")
      cat("    max_turns:", self$permissions$max_turns, "\n")
      invisible(self)
    }
  ),

  private = list(
    # Flag to signal stopping from hooks
    should_stop = FALSE,
    stop_reason_from_hook = NULL,

    # Callback for tool requests (permission checking + hooks)
    on_tool_request = function(request) {
      # Validate and extract request data safely
      extracted <- private$extract_tool_request_data(request)
      tool_name <- extracted$tool_name
      tool_input <- extracted$tool_input
      tool_annotations <- extracted$tool_annotations

      context <- list(
        working_dir = self$working_dir,
        tool_annotations = tool_annotations
      )

      # Check permissions first
      perm_result <- self$permissions$check(tool_name, tool_input, context)

      if (inherits(perm_result, "PermissionResultDeny")) {
        ellmer::tool_reject(perm_result$reason)
      }

      # Fire PreToolUse hooks
      hook_result <- self$hooks$fire(
        "PreToolUse",
        tool_name = tool_name,
        tool_input = tool_input,
        context = context
      )

      # Check hook result
      if (inherits(hook_result, "HookResultPreToolUse")) {
        if (hook_result$permission == "deny") {
          ellmer::tool_reject(hook_result$reason %||% "Denied by hook")
        }
        # Check continue field - signal to stop after this tool
        if (!is.null(hook_result$continue) && !hook_result$continue) {
          private$should_stop <- TRUE
          private$stop_reason_from_hook <- "hook_requested_stop"
        }
      }

      # Allow the tool to proceed
      invisible(NULL)
    },

    # Callback for tool results (hooks)
    on_tool_result = function(result) {
      # Validate and extract tool result data safely
      # ContentToolResult (S7) has: value, error, extra, request
      # request is ContentToolRequest with: id, name, arguments, tool, extra
      extracted <- private$extract_tool_result_data(result)

      context <- list(
        working_dir = self$working_dir
      )

      # Fire PostToolUse hooks
      hook_result <- self$hooks$fire(
        "PostToolUse",
        tool_name = extracted$tool_name,
        tool_result = extracted$tool_result,
        tool_error = extracted$tool_error,
        context = context
      )

      # Check continue field in PostToolUse result
      if (inherits(hook_result, "HookResultPostToolUse")) {
        if (!is.null(hook_result$continue) && !hook_result$continue) {
          private$should_stop <- TRUE
          private$stop_reason_from_hook <- "hook_requested_stop"
        }
      }

      invisible(NULL)
    },

    # Safely extract data from a tool request (handles S7 and malformed objects)
    extract_tool_request_data = function(request) {
      # Default values if extraction fails
      tool_name <- "unknown"
      tool_input <- list()
      tool_annotations <- NULL

      # Check if we have a valid request object
      if (is.null(request)) {
        cli_warn("Tool request callback received NULL request")
        return(list(
          tool_name = tool_name,
          tool_input = tool_input,
          tool_annotations = tool_annotations
        ))
      }

      # Check if it's a ContentToolRequest (S7 class)
      if (!inherits(request, "ContentToolRequest")) {
        cli_warn(c(
          "Tool request is not a ContentToolRequest",
          "i" = "Got class: {.cls {class(request)}}"
        ))

        # Attempt list-style access for backwards compatibility
        if (is.list(request)) {
          tool_name <- request$name %||% "unknown"
          tool_input <- request$arguments %||% list()
          if (!is.null(request$tool) && is.list(request$tool)) {
            tool_annotations <- request$tool$annotations
          }
        }

        return(list(
          tool_name = tool_name,
          tool_input = tool_input,
          tool_annotations = tool_annotations
        ))
      }

      # Extract from S7 object with error handling
      # Tool name
      tool_name <- tryCatch(
        request@name %||% "unknown",
        error = function(e) {
          cli_warn("Failed to extract tool name from request: {e$message}")
          "unknown"
        }
      )

      # Tool arguments
      tool_input <- tryCatch(
        request@arguments %||% list(),
        error = function(e) {
          cli_warn("Failed to extract tool arguments from request: {e$message}")
          list()
        }
      )

      # Tool annotations
      tool_annotations <- tryCatch(
        {
          if (!is.null(request@tool)) {
            request@tool@annotations
          } else {
            NULL
          }
        },
        error = function(e) {
          # Annotations are optional, don't warn
          NULL
        }
      )

      list(
        tool_name = tool_name,
        tool_input = tool_input,
        tool_annotations = tool_annotations
      )
    },

    # Safely extract data from a tool result (handles S7 and malformed objects)
    extract_tool_result_data = function(result) {
      # Default values if extraction fails
      tool_name <- "unknown"
      tool_result <- NULL
      tool_error <- NULL

      # Check if we have a valid result object
      if (is.null(result)) {
        cli_warn("Tool result callback received NULL result")
        return(list(
          tool_name = tool_name,
          tool_result = tool_result,
          tool_error = "NULL result received"
        ))
      }

      # Check if it's a ContentToolResult (S7 class)
      if (!inherits(result, "ContentToolResult")) {
        # Try to handle as a list-like object for backwards compatibility
        cli_warn(c(
          "Tool result is not a ContentToolResult",
          "i" = "Got class: {.cls {class(result)}}"
        ))

        # Attempt list-style access
        if (is.list(result)) {
          tool_result <- result$value
          tool_error <- result$error
          if (!is.null(result$request)) {
            tool_name <- result$request$name %||% "unknown"
          }
        }

        return(list(
          tool_name = tool_name,
          tool_result = tool_result,
          tool_error = tool_error
        ))
      }

      # Extract from S7 object with error handling
      # Tool name from request
      tool_name <- tryCatch(
        {
          if (!is.null(result@request)) {
            result@request@name %||% "unknown"
          } else {
            "unknown"
          }
        },
        error = function(e) {
          cli_warn("Failed to extract tool name from result: {e$message}")
          "unknown"
        }
      )

      # Tool result value
      tool_result <- tryCatch(
        result@value,
        error = function(e) {
          cli_warn("Failed to extract tool result value: {e$message}")
          NULL
        }
      )

      # Tool error
      tool_error <- tryCatch(
        result@error,
        error = function(e) {
          cli_warn("Failed to extract tool error: {e$message}")
          NULL
        }
      )

      list(
        tool_name = tool_name,
        tool_result = tool_result,
        tool_error = tool_error
      )
    },

    # Create a true coro generator for streaming events
    create_run_generator = function(task, max_turns) {
      agent <- self

      # Note: We use .__enclos_env__$private access inside the generator because
      # coro's state machine parser doesn't support calling closure functions.
      # This is a known limitation - see https://github.com/r-lib/coro/issues

      # Reset stop flags at start
      private$should_stop <- FALSE
      private$stop_reason_from_hook <- NULL

      # Create the generator using coro
      coro::generator(function() {
        # Yield start event
        coro::yield(AgentEvent("start", task = task))

        # Fire SessionStart hook (before first turn begins)
        agent$hooks$fire(
          "SessionStart",
          context = list(
            working_dir = agent$working_dir,
            permissions = agent$permissions,
            provider = agent$provider(),
            tools_count = length(agent$chat$get_tools())
          )
        )

        # Fire UserPromptSubmit hook
        agent$hooks$fire(
          "UserPromptSubmit",
          prompt = task,
          context = list(working_dir = agent$working_dir)
        )

        turn_num <- 0
        stop_reason <- "complete"
        last_response_hash <- NULL

        for (i in seq_len(max_turns)) {
          turn_num <- i

          # Check if hook requested stop
          if (agent$.__enclos_env__$private$should_stop) {
            hook_reason <- agent$.__enclos_env__$private$stop_reason_from_hook
            if (is.null(hook_reason)) {
              stop_reason <- "hook_requested_stop"
            } else {
              stop_reason <- hook_reason
            }
            break
          }

          # Check cost limit
          if (!is.null(agent$permissions$max_cost_usd)) {
            current_cost <- agent$cost()$total
            if (
              !is.na(current_cost) &&
                current_cost >= agent$permissions$max_cost_usd
            ) {
              stop_reason <- "cost_limit"
              break
            }
            if (
              !is.na(current_cost) &&
                current_cost >= agent$permissions$max_cost_usd * 0.9
            ) {
              cli::cli_warn(
                "Approaching cost limit: {format_cost(current_cost)} / {format_cost(agent$permissions$max_cost_usd)}"
              )
            }
          }

          # Determine the prompt for this turn
          if (i == 1) {
            prompt <- task
          } else {
            prompt <- NULL
          }

          # Use ellmer's stream() for true streaming text output
          text_chunks <- character()
          stream_error <- NULL

          # Try streaming first
          stream_gen <- tryCatch(
            agent$chat$stream(prompt),
            error = function(e) {
              stream_error <<- e
              NULL
            }
          )

          if (!is.null(stream_gen)) {
            # Stream chunks as they arrive
            repeat {
              chunk <- tryCatch(
                stream_gen(),
                error = function(e) coro::exhausted()
              )
              if (coro::is_exhausted(chunk)) {
                break
              }
              if (!is.null(chunk) && nchar(chunk) > 0) {
                text_chunks <- c(text_chunks, chunk)
                coro::yield(AgentEvent(
                  "text",
                  text = chunk,
                  is_complete = FALSE
                ))
              }
            }
          } else {
            # Fallback to non-streaming if stream() failed
            if (!is.null(stream_error)) {
              cli::cli_warn(c(
                "Streaming failed, falling back to non-streaming",
                "x" = stream_error$message
              ))
            }
            response <- agent$chat$chat(prompt)
            if (!is.null(response) && nchar(response) > 0) {
              text_chunks <- response
              coro::yield(AgentEvent(
                "text",
                text = response,
                is_complete = TRUE
              ))
            }
          }

          # Yield complete text event with full response
          full_text <- paste(text_chunks, collapse = "")
          if (length(text_chunks) > 0 && nchar(full_text) > 0) {
            coro::yield(AgentEvent("text_complete", text = full_text))
          }

          # Stall detection
          if (nchar(full_text) > 0) {
            current_hash <- digest::digest(full_text, algo = "md5")
          } else {
            current_hash <- ""
          }
          if (
            !is.null(last_response_hash) &&
              identical(current_hash, last_response_hash) &&
              nchar(full_text) > 0
          ) {
            cli::cli_warn("Agent may be stalled - identical response detected")
          }
          last_response_hash <- current_hash

          # Yield turn event
          last_turn <- agent$chat$last_turn()
          coro::yield(AgentEvent(
            "turn",
            turn = last_turn,
            turn_number = turn_num
          ))

          # Check if hook requested stop (after tool execution)
          if (agent$.__enclos_env__$private$should_stop) {
            hook_reason <- agent$.__enclos_env__$private$stop_reason_from_hook
            if (is.null(hook_reason)) {
              stop_reason <- "hook_requested_stop"
            } else {
              stop_reason <- hook_reason
            }
            break
          }

          # Check if we're done (no tool requests in last turn)
          if (!agent$.__enclos_env__$private$has_tool_requests(last_turn)) {
            break
          }

          # Check if we hit max turns
          if (i >= max_turns) {
            stop_reason <- "max_turns"
          }
        }

        # Fire Stop hook
        agent$hooks$fire(
          "Stop",
          reason = stop_reason,
          context = list(
            working_dir = agent$working_dir,
            total_turns = turn_num,
            cost = agent$cost()
          )
        )

        # Fire SessionEnd hook (after agent stops for any reason)
        agent$hooks$fire(
          "SessionEnd",
          reason = stop_reason,
          context = list(
            working_dir = agent$working_dir,
            total_turns = turn_num,
            cost = agent$cost()
          )
        )

        # Yield stop event
        coro::yield(AgentEvent(
          "stop",
          reason = stop_reason,
          total_turns = turn_num,
          cost = agent$cost()
        ))
      })()
    },

    # Check if a turn has tool requests
    has_tool_requests = function(turn) {
      if (is.null(turn)) {
        return(FALSE)
      }

      # Check contents for tool requests
      contents <- turn@contents
      for (content in contents) {
        if (inherits(content, "ContentToolRequest")) {
          return(TRUE)
        }
      }
      FALSE
    },

    # Get the last response text
    get_last_response = function() {
      last <- self$chat$last_turn()
      if (is.null(last)) {
        return(NULL)
      }
      last@text
    },

    # Generate a summary of turns using the LLM
    generate_compaction_summary = function(turns) {
      # Helper to get turn text (handles both S7 and list objects)
      get_turn_text <- function(turn) {
        tryCatch(turn@text, error = function(e) turn$text) %||% "[no text]"
      }

      # Helper to get turn contents (handles both S7 and list objects)
      get_turn_contents <- function(turn) {
        tryCatch(turn@contents, error = function(e) turn$contents) %||% list()
      }

      # Format turns for summarization
      turn_texts <- vapply(
        turns,
        function(turn) {
          role <- if (inherits(turn, "UserTurn")) "User" else "Assistant"
          text <- get_turn_text(turn)

          # Include tool information if present
          tool_info <- ""
          if (inherits(turn, "AssistantTurn")) {
            contents <- get_turn_contents(turn)
            tool_requests <- Filter(
              function(c) inherits(c, "ContentToolRequest"),
              contents
            )
            if (length(tool_requests) > 0) {
              tool_names <- vapply(
                tool_requests,
                function(t) tryCatch(t@name, error = function(e) t$name) %||% "unknown",
                character(1)
              )
              tool_info <- paste0(" [Tools: ", paste(tool_names, collapse = ", "), "]")
            }
          }

          paste0(role, tool_info, ": ", text)
        },
        character(1)
      )

      conversation_text <- paste(turn_texts, collapse = "\n\n")

      # Create summarization prompt
      summarization_prompt <- paste0(
        "Summarize the following conversation excerpt concisely. ",
        "Focus on:\n",
        "1. Key decisions made\n",
        "2. Important findings or results\n",
        "3. Files created, modified, or discussed\n",
        "4. Any errors encountered and how they were resolved\n",
        "5. Current state/progress of the task\n\n",
        "Keep the summary under 500 words. Be factual and specific.\n\n",
        "Conversation to summarize:\n",
        "---\n",
        conversation_text,
        "\n---\n\n",
        "Summary:"
      )

      # Try to use the LLM for summarization
      summary <- tryCatch(
        {
          # Create a temporary chat for summarization
          # Use the same provider as the main chat
          provider_info <- self$provider()

          temp_chat <- tryCatch(
            {
              # Try to create a chat with the same provider
              if (provider_info$name == "openai") {
                ellmer::chat_openai(model = provider_info$model %||% "gpt-4o-mini")
              } else if (provider_info$name == "anthropic") {
                ellmer::chat_anthropic(model = provider_info$model %||% "claude-sonnet-4-5-20250929")
              } else if (provider_info$name == "google") {
                ellmer::chat_google(model = provider_info$model %||% "gemini-2.0-flash")
              } else {
                # Fallback to a default provider
                ellmer::chat_openai(model = "gpt-4o-mini")
              }
            },
            error = function(e) {
              cli_warn(c(
                "Could not create summarization chat",
                "i" = "Falling back to text-based summary",
                "x" = e$message
              ))
              NULL
            }
          )

          if (is.null(temp_chat)) {
            return(private$generate_fallback_summary(turns))
          }

          # Generate summary
          response <- temp_chat$chat(summarization_prompt)
          response
        },
        error = function(e) {
          cli_warn(c(
            "LLM summarization failed",
            "i" = "Falling back to text-based summary",
            "x" = e$message
          ))
          private$generate_fallback_summary(turns)
        }
      )

      summary
    },

    # Fallback summary when LLM is unavailable
    generate_fallback_summary = function(turns) {
      summary_parts <- vapply(
        turns,
        function(turn) {
          role <- if (inherits(turn, "UserTurn")) "User" else "Assistant"
          # Handle both S7 objects (with @) and regular lists (with $)
          text <- tryCatch(
            turn@text,
            error = function(e) turn$text
          ) %||% "[no text]"
          if (nchar(text) > 200) {
            text <- paste0(substr(text, 1, 197), "...")
          }
          paste0(role, ": ", text)
        },
        character(1)
      )

      paste0(
        "[Compacted ",
        length(turns),
        " earlier turns - LLM summary unavailable]\n\n",
        paste(summary_parts, collapse = "\n\n")
      )
    },

    # Storage for loaded skills
    loaded_skills = list()
  )
)
