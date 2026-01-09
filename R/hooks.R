# Hook system for deputy agents

#' Hook events supported by deputy
#'
#' @description
#' Hook events are fired at specific points during agent execution. Each event
#' type has a specific callback signature and context structure.
#'
#' @section Event Types:
#'
#' **PreToolUse** - Before a tool is executed (can deny)
#'
#' Callback signature: `function(tool_name, tool_input, context)`
#' - `tool_name`: Name of the tool being called (character)
#' - `tool_input`: Named list of arguments passed to the tool
#' - `context`: List containing `working_dir` and `tool_annotations` (if available)
#' - Return: [HookResultPreToolUse()] to allow/deny
#'
#' **PostToolUse** - After a tool completes
#'
#' Callback signature: `function(tool_name, tool_result, tool_error, context)`
#' - `tool_name`: Name of the tool that was called (character)
#' - `tool_result`: Result returned by the tool (or NULL on error)
#' - `tool_error`: Error message if tool failed (or NULL on success)
#' - `context`: List containing `working_dir` (current directory)
#' - Return: [HookResultPostToolUse()] to continue/stop
#'
#' **Stop** - When the agent stops
#'
#' Callback signature: `function(reason, context)`
#' - `reason`: Why the agent stopped ("complete", "max_turns", "error")
#' - `context`: List containing `working_dir`, `total_turns`, `cost`
#' - Return: [HookResultStop()]
#'
#' **SubagentStop** - When a sub-agent completes (LeadAgent only)
#'
#' Callback signature: `function(agent_name, task, result, context)`
#' - `agent_name`: Name of the sub-agent that completed (character)
#' - `task`: The task that was delegated (character)
#' - `result`: Result returned by the sub-agent
#' - `context`: List containing `working_dir`
#' - Return: [HookResultSubagentStop()]
#'
#' **UserPromptSubmit** - When a user prompt is submitted
#'
#' Callback signature: `function(prompt, context)`
#' - `prompt`: The user's prompt text (character)
#' - `context`: List containing `working_dir`
#' - Return: NULL (informational only)
#'
#' **PreCompact** - Before conversation compaction
#'
#' Callback signature: `function(turns_to_compact, turns_to_keep, context)`
#' - `turns_to_compact`: List of turns that will be compacted into a summary
#' - `turns_to_keep`: List of recent turns that will be preserved
#' - `context`: List containing `working_dir`, `total_turns`, `compact_count`
#' - Return: [HookResultPreCompact()] to allow/cancel or provide custom summary
#'
#' @section Context Structure:
#'
#' The context parameter is always a named list. Common fields:
#' - `working_dir`: The agent's current working directory
#' - `tool_annotations`: (PreToolUse only) Tool annotations from ellmer if available
#' - `total_turns`: (Stop, PreCompact) Number of turns in the conversation
#' - `cost`: (Stop only) List with `total`, `input_tokens`, `output_tokens`
#' - `compact_count`: (PreCompact only) Number of turns being compacted
#'
#' @examples
#' \dontrun{
#' # PreToolUse callback example
#' agent$add_hook(HookMatcher$new(
#'   event = "PreToolUse",
#'   callback = function(tool_name, tool_input, context) {
#'     message("Tool: ", tool_name, " in ", context$working_dir)
#'     HookResultPreToolUse(permission = "allow")
#'   }
#' ))
#'
#' # PostToolUse callback example
#' agent$add_hook(HookMatcher$new(
#'   event = "PostToolUse",
#'   callback = function(tool_name, tool_result, tool_error, context) {
#'     if (!is.null(tool_error)) {
#'       warning("Tool failed: ", tool_error)
#'     }
#'     HookResultPostToolUse()
#'   }
#' ))
#' }
#'
#' @export
HookEvent <- c(
  "PreToolUse",
  "PostToolUse",

  "Stop",
  "SubagentStop",
  "UserPromptSubmit",
  "PreCompact"
)

#' Create a PreToolUse hook result
#'
#' @description
#' Return this from a PreToolUse hook callback to control tool execution.
#'
#' @param permission Either `"allow"` or `"deny"`
#' @param reason Reason for denial (shown to the LLM)
#' @param continue If FALSE, stop the agent after this hook
#' @return A `HookResultPreToolUse` object
#'
#' @examples
#' # Allow a tool call
#' HookResultPreToolUse(permission = "allow")
#'
#' # Deny a dangerous command
#' HookResultPreToolUse(
#'   permission = "deny",
#'   reason = "Dangerous command pattern detected"
#' )
#'
#' @export
HookResultPreToolUse <- function(
  permission = c("allow", "deny"),
  reason = NULL,
  continue = TRUE
) {
  permission <- match.arg(permission)

  structure(
    list(
      permission = permission,
      reason = reason,
      continue = continue
    ),
    class = c("HookResultPreToolUse", "HookResult", "list")
  )
}

#' Create a PostToolUse hook result
#'
#' @description
#' Return this from a PostToolUse hook callback.
#'
#' @param continue If FALSE, stop the agent after this hook
#' @return A `HookResultPostToolUse` object
#'
#' @examples
#' # Continue execution
#' HookResultPostToolUse()
#'
#' # Stop after this tool
#' HookResultPostToolUse(continue = FALSE)
#'
#' @export
HookResultPostToolUse <- function(continue = TRUE) {
  structure(
    list(
      continue = continue
    ),
    class = c("HookResultPostToolUse", "HookResult", "list")
  )
}

#' Create a Stop hook result
#'
#' @description
#' Return this from a Stop hook callback.
#'
#' @param handled If TRUE, indicates the hook handled the stop event
#' @return A `HookResultStop` object
#'
#' @export
HookResultStop <- function(handled = TRUE) {
  structure(
    list(
      handled = handled
    ),
    class = c("HookResultStop", "HookResult", "list")
  )
}

#' Create a SubagentStop hook result
#'
#' @description
#' Return this from a SubagentStop hook callback. This hook fires when a
#' sub-agent (delegated from a LeadAgent) completes its task.
#'
#' @param handled If TRUE, indicates the hook handled the sub-agent completion
#' @return A `HookResultSubagentStop` object
#'
#' @examples
#' # Basic handler
#' HookResultSubagentStop()
#'
#' # Mark as handled
#' HookResultSubagentStop(handled = TRUE)
#'
#' @export
HookResultSubagentStop <- function(handled = TRUE) {
  structure(
    list(
      handled = handled
    ),
    class = c("HookResultSubagentStop", "HookResult", "list")
  )
}

#' Create a PreCompact hook result
#'
#' @description
#' Return this from a PreCompact hook callback to control whether compaction
#' should proceed.
#'
#' @param continue If FALSE, cancels the compaction
#' @param summary Optional custom summary to use for compaction
#' @return A `HookResultPreCompact` object
#'
#' @examples
#' # Allow compaction
#' HookResultPreCompact()
#'
#' # Cancel compaction
#' HookResultPreCompact(continue = FALSE)
#'
#' # Provide custom summary
#' HookResultPreCompact(summary = "Previous conversation discussed X, Y, Z.")
#'
#' @export
HookResultPreCompact <- function(continue = TRUE, summary = NULL) {
  structure(
    list(
      continue = continue,
      summary = summary
    ),
    class = c("HookResultPreCompact", "HookResult", "list")
  )
}

#' HookMatcher R6 Class
#'
#' @description
#' Defines when a hook callback should be triggered. Hooks can be filtered
#' by event type and optionally by tool name pattern.
#'
#' @export
HookMatcher <- R6::R6Class(
  "HookMatcher",

  public = list(
    #' @field event The hook event type (see [HookEvent])
    event = NULL,

    #' @field pattern Optional regex pattern for tool name filtering
    pattern = NULL,

    #' @field callback The function to call when the hook fires
    callback = NULL,

    #' @field timeout Maximum execution time for the callback in seconds
    timeout = 30,

    #' @description
    #' Create a new HookMatcher.
    #'
    #' @param event The event type (must be one of [HookEvent])
    #' @param callback Function to call. Signature depends on event type:
    #'   * PreToolUse: `function(tool_name, tool_input, context)`
    #'   * PostToolUse: `function(tool_name, tool_result, tool_error, context)`
    #'   * Stop: `function(reason, context)`
    #'   * SubagentStop: `function(agent_name, task, result, context)`
    #'   * UserPromptSubmit: `function(prompt, context)`
    #' @param pattern Optional regex pattern to filter by tool name.
    #'   Only applies to PreToolUse and PostToolUse events.
    #' @param timeout Maximum callback execution time in seconds
    #' @return A new `HookMatcher` object
    #'
    #' @examples
    #' \dontrun{
    #' # Block dangerous bash commands
    #' HookMatcher$new(
    #'   event = "PreToolUse",
    #'   pattern = "^(run_bash|bash)$",
    #'   callback = function(tool_name, tool_input, context) {
    #'     if (grepl("rm -rf", tool_input$command)) {
    #'       HookResultPreToolUse(permission = "deny", reason = "Dangerous!")
    #'     } else {
    #'       HookResultPreToolUse(permission = "allow")
    #'     }
    #'   }
    #' )
    #' }
    initialize = function(event, callback, pattern = NULL, timeout = 30) {
      if (!event %in% HookEvent) {
        cli_abort(c(
          "Invalid hook event: {.val {event}}",
          "i" = "Valid events are: {.val {HookEvent}}"
        ))
      }

      if (!is.function(callback)) {
        cli_abort("{.arg callback} must be a function")
      }

      self$event <- event
      self$callback <- callback
      self$pattern <- pattern
      self$timeout <- timeout
    },

    #' @description
    #' Check if this hook matches a given tool name.
    #'
    #' @param tool_name The tool name to check (can be NULL)
    #' @return Logical indicating if the hook matches
    matches = function(tool_name = NULL) {
      # No pattern means match all
      if (is.null(self$pattern)) {
        return(TRUE)
      }

      # Can't match if no tool name provided
      if (is.null(tool_name)) {
        return(FALSE)
      }

      # Check regex pattern
      grepl(self$pattern, tool_name)
    },

    #' @description
    #' Print the hook matcher.
    print = function() {
      cat("<HookMatcher>\n")
      cat("  event:", self$event, "\n")
      cat(
        "  pattern:",
        if (is.null(self$pattern)) "<any>" else self$pattern,
        "\n"
      )
      cat("  timeout:", self$timeout, "seconds\n")
      invisible(self)
    }
  )
)

#' HookRegistry R6 Class
#'
#' @description
#' Manages a collection of hooks for an agent. Handles registration,
#' matching, and execution of hooks.
#'
#' @export
HookRegistry <- R6::R6Class(
  "HookRegistry",

  public = list(
    #' @description
    #' Create a new HookRegistry.
    initialize = function() {
      private$hooks <- list()
    },

    #' @description
    #' Add a hook to the registry.
    #'
    #' @param hook A [HookMatcher] object
    #' @return Invisible self for chaining
    add = function(hook) {
      if (!inherits(hook, "HookMatcher")) {
        cli_abort("{.arg hook} must be a HookMatcher object")
      }
      private$hooks <- c(private$hooks, list(hook))
      invisible(self)
    },

    #' @description
    #' Get all hooks for a specific event.
    #'
    #' @param event The event type
    #' @param tool_name Optional tool name for filtering
    #' @return List of matching HookMatcher objects
    get_hooks = function(event, tool_name = NULL) {
      matching <- list()
      for (hook in private$hooks) {
        if (hook$event == event && hook$matches(tool_name)) {
          matching <- c(matching, list(hook))
        }
      }
      matching
    },

    #' @description
    #' Fire hooks for an event and return the first non-NULL result.
    #'
    #' @param event The event type
    #' @param tool_name Optional tool name for filtering (also passed to callback)
    #' @param ... Arguments to pass to the callback
    #' @return The first non-NULL hook result, or NULL
    fire = function(event, tool_name = NULL, ...) {
      hooks <- self$get_hooks(event, tool_name)

      # Build args list including tool_name if provided
      args <- list(...)
      if (!is.null(tool_name)) {
        args <- c(list(tool_name = tool_name), args)
      }

      for (hook in hooks) {
        result <- tryCatch(
          {
            # Call with timeout if callr is available
            if (hook$timeout > 0 && rlang::is_installed("callr")) {
              callr::r(
                function(callback, args) do.call(callback, args),
                args = list(callback = hook$callback, args = args),
                timeout = hook$timeout
              )
            } else {
              do.call(hook$callback, args)
            }
          },
          error = function(e) {
            cli_warn(c(
              "Hook {.val {event}} failed",
              "x" = e$message
            ))
            # Fail-safe: deny for PreToolUse, NULL for others
            if (event == "PreToolUse") {
              return(HookResultPreToolUse(
                permission = "deny",
                reason = paste("Hook error:", e$message)
              ))
            }
            NULL
          }
        )

        # Return first non-NULL result
        if (!is.null(result)) {
          return(result)
        }
      }

      NULL
    },

    #' @description
    #' Get the number of registered hooks.
    #' @return Integer count
    count = function() {
      length(private$hooks)
    },

    #' @description
    #' Print the registry.
    print = function() {
      cat("<HookRegistry>\n")
      cat("  hooks:", self$count(), "registered\n")

      if (self$count() > 0) {
        # Group by event
        by_event <- list()
        for (hook in private$hooks) {
          event <- hook$event
          if (is.null(by_event[[event]])) {
            by_event[[event]] <- 0
          }
          by_event[[event]] <- by_event[[event]] + 1
        }

        for (event in names(by_event)) {
          cat("    ", event, ":", by_event[[event]], "\n")
        }
      }

      invisible(self)
    }
  ),

  private = list(
    hooks = list()
  )
)

#' Create a hook that logs all tool calls
#'
#' @description
#' Convenience function to create a PostToolUse hook that logs tool calls
#' using the cli package.
#'
#' @param verbose If TRUE, include tool result in log
#' @return A [HookMatcher] object
#'
#' @examples
#' \dontrun{
#' agent$add_hook(hook_log_tools())
#' }
#'
#' @export
hook_log_tools <- function(verbose = FALSE) {
  HookMatcher$new(
    event = "PostToolUse",
    timeout = 0, # Run in main process for cli output
    callback = function(tool_name, tool_result, tool_error, context) {
      if (!is.null(tool_error)) {
        cli::cli_alert_danger(paste0(
          "Tool ",
          tool_name,
          " failed: ",
          tool_error
        ))
      } else {
        cli::cli_alert_success(paste0("Tool ", tool_name, " completed"))
        if (verbose && !is.null(tool_result)) {
          result_preview <- truncate_string(as.character(tool_result), 100)
          cli::cli_alert_info(paste0("Result: ", result_preview))
        }
      }
      HookResultPostToolUse()
    }
  )
}

#' Create a hook that blocks dangerous bash commands
#'
#' @description
#' Convenience function to create a PreToolUse hook that blocks potentially
#' dangerous bash commands. Default patterns include:
#'
#' **File system destruction:**
#' `rm -rf`, `mkfs`, `dd if=`, writes to `/dev/`
#'
#' **Privilege escalation:**
#' `sudo`, `su -`, `chmod 777`, `chown`, `setuid`
#'
#' **Code execution:**
#' `eval`, `exec`, `source` (with variables), backticks
#'
#' **Process manipulation:**
#' `kill -9`, `killall`, `pkill`, fork bombs
#'
#' **System modification:**
#' `crontab`, `systemctl`, `/etc/passwd`, `/etc/shadow`
#'
#' **Network exfiltration:**
#' `curl -X POST`, `wget --post`, `nc -e`, `netcat`, reverse shells
#'
#' @param patterns Character vector of regex patterns to block.
#'   Default includes comprehensive dangerous patterns.
#' @param additional_patterns Optional character vector of additional
#'   patterns to block alongside defaults.
#' @return A [HookMatcher] object
#'
#' @examples
#' \dontrun{
#' # Use default patterns
#' agent$add_hook(hook_block_dangerous_bash())
#'
#' # Add custom patterns
#' agent$add_hook(hook_block_dangerous_bash(
#'   additional_patterns = c("my_custom_pattern", "another_pattern")
#' ))
#' }
#'
#' @export
hook_block_dangerous_bash <- function(
  patterns = NULL,
  additional_patterns = NULL
) {
  # Default dangerous patterns
  default_patterns <- c(
    # File system destruction
    "rm\\s+-rf",
    "rm\\s+-fr",
    "rm\\s+--no-preserve-root",
    "mkfs",
    "dd\\s+if=",
    ">\\s*/dev/",
    "shred\\s",

    # Privilege escalation
    "sudo\\s",
    "su\\s+-",
    "chmod\\s+777",
    "chmod\\s+\\+s",
    "chown\\s+root",
    "setuid",
    "setgid",

    # Code execution patterns
    "\\beval\\s",
    "\\bexec\\s",
    "source\\s+\\$",
    "`.*`",
    "\\$\\(.*\\)",

    # Process manipulation
    "kill\\s+-9",
    "killall\\s",
    "pkill\\s+-9",
    ":\\s*\\(\\s*\\)\\s*\\{",
    "\\|\\s*:\\s*&",

    # System modification
    "crontab\\s+-e",
    "crontab\\s.*<",
    "systemctl\\s+(disable|stop|mask)",
    "/etc/passwd",
    "/etc/shadow",
    "/etc/sudoers",
    "visudo",
    "usermod",
    "useradd.*-o",

    # Network exfiltration/reverse shells
    "curl\\s.*-X\\s*POST",
    "curl\\s.*--data",
    "curl\\s.*-d\\s",
    "wget\\s+--post",
    "nc\\s+-e",
    "nc\\s.*-c",
    "netcat",
    "ncat\\s+-e",
    "/dev/tcp/",
    "/dev/udp/",
    "bash\\s+-i\\s+>&",
    "python.*socket",
    "perl.*socket",

    # Environment/credential access
    "\\benv\\b.*=.*\\bexport\\b",
    "printenv",
    "cat\\s+.*\\.ssh/",
    "cat\\s+.*\\.aws/",
    "cat\\s+.*\\.env",
    "base64\\s+-d",

    # History manipulation
    "history\\s+-c",
    "unset\\s+HISTFILE",
    "export\\s+HISTFILE=/dev/null"
  )

  # Use provided patterns or defaults
  if (is.null(patterns)) {
    patterns <- default_patterns
  }

  # Add any additional patterns
  if (!is.null(additional_patterns)) {
    patterns <- c(patterns, additional_patterns)
  }

  combined_pattern <- paste(patterns, collapse = "|")

  HookMatcher$new(
    event = "PreToolUse",
    pattern = "^(run_bash|bash|tool_run_bash)$",
    timeout = 0, # Run in main process
    callback = function(tool_name, tool_input, context) {
      command <- tool_input$command %||% ""

      if (grepl(combined_pattern, command, ignore.case = TRUE)) {
        HookResultPreToolUse(
          permission = "deny",
          reason = "Blocked: potentially dangerous command pattern detected"
        )
      } else {
        HookResultPreToolUse(permission = "allow")
      }
    }
  )
}

#' Create a hook that limits file writes to a directory
#'
#' @description
#' Convenience function to create a PreToolUse hook that only allows
#' file writes within a specified directory.
#'
#' @param allowed_dir Directory where writes are allowed
#' @return A [HookMatcher] object
#'
#' @examples
#' \dontrun{
#' agent$add_hook(hook_limit_file_writes("./output"))
#' }
#'
#' @export
hook_limit_file_writes <- function(allowed_dir) {
  allowed_dir <- normalizePath(allowed_dir, mustWork = FALSE)

  HookMatcher$new(
    event = "PreToolUse",
    pattern = "^(write_file|tool_write_file)$",
    timeout = 0, # Run in main process
    callback = function(tool_name, tool_input, context) {
      path <- tool_input$path %||% tool_input$file_path %||% ""
      full_path <- normalizePath(path, mustWork = FALSE)

      if (!startsWith(full_path, allowed_dir)) {
        HookResultPreToolUse(
          permission = "deny",
          reason = paste("File writes only allowed in:", allowed_dir)
        )
      } else {
        HookResultPreToolUse(permission = "allow")
      }
    }
  )
}
