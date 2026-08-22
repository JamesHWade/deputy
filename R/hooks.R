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
#' - `context`: Common correlation fields plus `tool_call_id` and
#'   `tool_annotations` (if available)
#' - Return: [HookResultPreToolUse()] to allow/deny
#'
#' **PostToolUse** - After a tool completes
#'
#' Callback signature: `function(tool_name, tool_result, tool_error, context)`
#' - `tool_name`: Name of the tool that was called (character)
#' - `tool_result`: Result returned by the tool (or NULL on error)
#' - `tool_error`: Error message if tool failed (or NULL on success)
#' - `context`: Common correlation fields plus `tool_call_id`
#' - Return: [HookResultPostToolUse()] to continue/stop
#'
#' **PostToolUseFailure** - After a tool reports an error
#'
#' Callback signature: `function(tool_name, tool_result, tool_error, context)`
#' - Same arguments as PostToolUse, fired only when `tool_error` is not NULL
#'
#' **Stop** - When the agent stops
#'
#' Callback signature: `function(reason, context)`
#' - `reason`: Why the agent stopped (for example `"complete"`,
#'   `"request_limit"`, `"cost_limit"`, or `"provider_error"`)
#' - `context`: Common correlation fields plus `usage` and `cost`; native
#'   `run()` also includes `total_turns`
#' - Return: NULL (informational only)
#'
#' **SubagentStop** - When a sub-agent completes (LeadAgent only)
#'
#' Callback signature: `function(agent_name, task, result, context)`
#' - `agent_name`: Name of the sub-agent that completed (character)
#' - `task`: The task that was delegated (character)
#' - `result`: Result returned by the sub-agent
#' - `context`: Common correlation fields plus parent/child Agent and run IDs
#' - Return: NULL (informational only)
#'
#' **SubagentStart** - When a delegated sub-agent starts (LeadAgent only)
#'
#' Callback signature: `function(agent_name, task, context)`
#' - `agent_name`: Name of the sub-agent that started
#' - `task`: The delegated task
#' - `context`: Common correlation fields plus parent/child Agent IDs
#'
#' **PermissionRequest** - When permission policy denies a tool call
#'
#' Callback signature: `function(tool_name, tool_input, permission_result, context)`
#' - Return: [PermissionResultAllow()] to override the denial, or
#'   [PermissionResultDeny()] to replace the denial reason
#'
#' **ConfigChange** - When runtime configuration changes
#'
#' Callback signature: `function(key, old_value, new_value, context)`
#'
#' **UserPromptSubmit** - When a user prompt is submitted
#'
#' Callback signature: `function(prompt, context)`
#' - `prompt`: The user's prompt text (character)
#' - `context`: Common correlation fields
#' - Return: NULL (informational only)
#'
#' **Notification** - Informational runtime notice
#'
#' Callback signature: `function(message, context)`
#' - `message`: The notification text (character)
#' - `context`: Common correlation fields plus `level`, `code`, and any
#'   event-specific metadata
#' - Return: NULL (informational only)
#'
#' **PreCompact** - Before conversation compaction
#'
#' Callback signature: `function(turns_to_compact, turns_to_keep, context)`
#' - `turns_to_compact`: List of turns that will be compacted into a summary
#' - `turns_to_keep`: List of recent turns that will be preserved
#' - `context`: Common correlation fields plus `total_turns` and `compact_count`
#' - Return: [HookResultPreCompact()] to allow/cancel or provide custom summary
#'
#' **SessionStart** - When an agent session begins
#'
#' Callback signature: `function(context)`
#' - `context`: Common correlation fields plus `permissions`, `provider`, and
#'   `tools_count`
#' - Return: NULL (informational only)
#'
#' **SessionEnd** - When an agent session ends
#'
#' Callback signature: `function(reason, context)`
#' - `reason`: Why the agent stopped (for example `"complete"`,
#'   `"request_limit"`, `"cost_limit"`, or `"hook_requested_stop"`)
#' - `context`: Common correlation fields plus `usage` and `cost`; native
#'   `run()` also includes `total_turns`
#' - Return: NULL (informational only)
#'
#' @section Context Structure:
#'
#' The context parameter is always a named list. Common fields:
#' - `working_dir`: The agent's current working directory
#' - `run_context`: Immutable canonical product context for the active run
#' - `agent_id`: Stable identifier for the Agent instance
#' - `agent_name`: Optional human-readable Agent name
#' - `parent_agent_id`: Parent Agent identifier for delegated runs
#' - `parent_run_id`: Parent run identifier for delegated runs
#' - `delegation_id`: Delegation identifier for delegated runs and tools
#' - `tool_annotations`: (PreToolUse only) Tool annotations from ellmer if available
#' - `tool_call_id`: Canonical tool lifecycle identifier
#' - `usage`: Run-scoped [AgentUsage] for tool and terminal lifecycle hooks
#' - `usage_limits`: Active [UsageLimits] for tool lifecycle hooks
#' - `run_id`: Identifier for the active run
#' - `total_turns`: (native Stop, PreCompact, native SessionEnd) Conversation turns
#' - `cost`: (Stop, SessionEnd) List with `input`, `output`, `cached`, and `total`
#' - `compact_count`: (PreCompact only) Number of turns being compacted
#' - `level`: (Notification only) Informational severity such as `"info"` or `"warning"`
#' - `code`: (Notification only) Stable notification code when available
#' - `permissions`: (SessionStart only) The agent's permissions configuration
#' - `provider`: (SessionStart only) List with `name` and `model`
#' - `tools_count`: (SessionStart only) Number of registered tools
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
  "PostToolUseFailure",

  "Stop",
  "SubagentStart",
  "SubagentStop",
  "UserPromptSubmit",
  "Notification",
  "PermissionRequest",
  "ConfigChange",
  "PreCompact",

  "SessionStart",
  "SessionEnd"
)

#' Create a PreToolUse hook result
#'
#' @description
#' Return this from a PreToolUse hook callback to control tool execution.
#'
#' @param permission Either `"allow"` or `"deny"`
#' @param reason Reason for denial (shown to the LLM)
#' @param continue If FALSE, stop the agent after this hook
#' @param additional_context Optional text to append to the running context
#' @param stop_reason Optional stop reason used when `continue = FALSE`
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
  continue = TRUE,
  additional_context = NULL,
  stop_reason = NULL
) {
  permission <- match.arg(permission)

  structure(
    list(
      permission = permission,
      reason = reason,
      continue = continue,
      additional_context = additional_context,
      stop_reason = stop_reason
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
#' @param suppress_output Whether to suppress the result on Deputy's emitted
#'   `tool_end` event. This does not remove the result from model context.
#' @param updated_tool_output Optional replacement value for Deputy's emitted
#'   `tool_end` event. ellmer does not support rewriting the model-visible
#'   in-flight result from this callback.
#' @param additional_context Optional text to append to the running context
#' @param stop_reason Optional stop reason used when `continue = FALSE`
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
HookResultPostToolUse <- function(
  continue = TRUE,
  suppress_output = FALSE,
  updated_tool_output = NULL,
  additional_context = NULL,
  stop_reason = NULL
) {
  structure(
    list(
      continue = continue,
      suppress_output = isTRUE(suppress_output),
      updated_tool_output = updated_tool_output,
      additional_context = additional_context,
      stop_reason = stop_reason
    ),
    class = c("HookResultPostToolUse", "HookResult", "list")
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
#' **Security Note:** Hook matcher configuration is read-only from the public
#' API after construction so callbacks and matching rules cannot be swapped out
#' accidentally at runtime.
#'
#' @export
HookMatcher <- R6::R6Class(
  "HookMatcher",

  public = list(
    #' @description
    #' Create a new HookMatcher.
    #'
    #' @param event The event type (must be one of [HookEvent])
    #' @param callback Function to call. Signature depends on event type:
    #'   * PreToolUse: `function(tool_name, tool_input, context)`
    #'   * PostToolUse: `function(tool_name, tool_result, tool_error, context)`
    #'   * PostToolUseFailure: `function(tool_name, tool_result, tool_error, context)`
    #'   * Stop: `function(reason, context)`
    #'   * SubagentStart: `function(agent_name, task, context)`
    #'   * SubagentStop: `function(agent_name, task, result, context)`
    #'   * UserPromptSubmit: `function(prompt, context)`
    #'   * Notification: `function(message, context)`
    #'   * PermissionRequest: `function(tool_name, tool_input, permission_result, context)`
    #'   * ConfigChange: `function(key, old_value, new_value, context)`
    #'   * PreCompact: `function(turns_to_compact, turns_to_keep, context)`
    #'   * SessionStart: `function(context)`
    #'   * SessionEnd: `function(reason, context)`
    #' @param pattern Optional regex pattern to filter by tool name.
    #'   Only applies to PreToolUse and PostToolUse events.
    #' @param timeout Maximum callback execution time in seconds. The default,
    #'   `0`, runs the callback in the caller's process. Positive values run the
    #'   callback in a clean [callr::r()] subprocess, where caller-process state
    #'   and side effects are not available.
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
    initialize = function(event, callback, pattern = NULL, timeout = 0) {
      if (!event %in% HookEvent) {
        cli_abort(c(
          "Invalid hook event: {.val {event}}",
          "i" = "Valid events are: {.val {HookEvent}}"
        ))
      }

      if (!is.function(callback)) {
        cli_abort("{.arg callback} must be a function")
      }

      validate_hook_callback(event, callback)
      validate_hook_pattern(pattern)
      timeout <- validate_hook_timeout(timeout)

      private$.event <- event
      private$.callback <- callback
      private$.pattern <- pattern
      private$.timeout <- timeout
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
  ),

  active = list(
    #' @field event The hook event type (see [HookEvent]). Read-only after construction.
    event = function(value) {
      if (missing(value)) {
        return(private$.event)
      }
      cli_abort(
        "Cannot modify hook matcher: event is immutable after construction"
      )
    },

    #' @field pattern Optional regex pattern for tool name filtering. Read-only after construction.
    pattern = function(value) {
      if (missing(value)) {
        return(private$.pattern)
      }
      cli_abort(
        "Cannot modify hook matcher: pattern is immutable after construction"
      )
    },

    #' @field callback The function to call when the hook fires. Read-only after construction.
    callback = function(value) {
      if (missing(value)) {
        return(private$.callback)
      }
      cli_abort(
        "Cannot modify hook matcher: callback is immutable after construction"
      )
    },

    #' @field timeout Maximum execution time for the callback in seconds. Zero
    #'   runs in the caller's process; a positive value uses a clean subprocess.
    #'   Read-only after construction.
    timeout = function(value) {
      if (missing(value)) {
        return(private$.timeout)
      }
      cli_abort(
        "Cannot modify hook matcher: timeout is immutable after construction"
      )
    }
  ),

  private = list(
    .event = NULL,
    .pattern = NULL,
    .callback = NULL,
    .timeout = NULL
  )
)

#' HookRegistry R6 Class
#'
#' @description
#' Manages a collection of hooks for an agent. Handles registration,
#' matching, and execution of hooks.
#'
#' @keywords internal
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
    #' Hook errors are handled as follows:

    #' - **PreToolUse**: Errors result in denial (fail-safe security behavior)
    #' - **Other events**: Errors are logged prominently and stored in the
    #'   `last_errors` field, but execution continues to prevent cascade failures
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
              # Warn once if timeout requested but callr not installed
              if (
                hook$timeout > 0 &&
                  !rlang::is_installed("callr") &&
                  !isTRUE(private$callr_warned)
              ) {
                private$callr_warned <- TRUE
                cli::cli_warn(c(
                  "Hook timeout ignored: {.pkg callr} not installed",
                  "i" = "Install {.pkg callr} to enforce timeout: {.code install.packages('callr')}",
                  "i" = "Or set {.code timeout = 0} to suppress this warning"
                ))
              }
              do.call(hook$callback, args)
            }
          },
          error = function(e) {
            error_message <- conditionMessage(e)

            # Track the error for programmatic access
            error_info <- list(
              event = event,
              tool_name = tool_name,
              error = error_message,
              timestamp = Sys.time()
            )
            private$hook_errors <- c(private$hook_errors, list(error_info))

            # Use prominent error logging for all hook failures
            # PreToolUse failures are security-critical
            if (event == "PreToolUse") {
              cli::cli_alert_danger(c(
                "PreToolUse hook failed - denying tool for safety",
                "x" = error_message
              ))
              return(HookResultPreToolUse(
                permission = "deny",
                reason = paste("Hook error:", error_message)
              ))
            }

            # For other events, log prominently but continue execution
            # These could be logging/audit hooks that shouldn't crash the agent
            severity <- switch(
              event,
              "PostToolUse" = "PostToolUse hook failed (audit/logging may be incomplete)",
              "Stop" = "Stop hook failed (cleanup may be incomplete)",
              "SessionEnd" = "SessionEnd hook failed (state may not be saved)",
              "SessionStart" = "SessionStart hook failed (initialization may be incomplete)",
              paste0(event, " hook failed")
            )

            cli::cli_alert_danger(c(
              severity,
              "x" = error_message,
              "i" = "Use registry$last_errors to inspect hook failures"
            ))

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
    #' Get errors from recent hook executions.
    #'
    #' Useful for programmatic checking of hook health, especially for
    #' audit/logging hooks where failures are logged but not fatal.
    #'
    #' @return List of error records, each containing event, tool_name, error, timestamp
    last_errors = function() {
      private$hook_errors
    },

    #' @description
    #' Clear the error history.
    clear_errors = function() {
      private$hook_errors <- list()
      invisible(self)
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
    hooks = list(),
    hook_errors = list(),
    callr_warned = FALSE
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
#' **Obfuscation detection:**
#' Variable expansion in commands, base64 piping, hex/octal escapes,
#' quote splitting, backslash escapes
#'
#' **Security Note:** This is defense-in-depth and cannot catch all possible
#' obfuscation techniques. For high-security environments, consider:
#' 1. Using sandboxed execution (Docker, firejail)
#' 2. Disabling bash entirely via [Permissions]
#' 3. Using a command whitelist instead of blacklist
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
    "export\\s+HISTFILE=/dev/null",

    # === OBFUSCATION DETECTION ===

    # Variable-based command execution (CMD=rm; $CMD -rf)
    "\\$[A-Za-z_][A-Za-z0-9_]*\\s*-", # $VAR followed by flags
    "\\$\\{[^}]+\\}\\s*-", # ${VAR} followed by flags

    # Dangerous variable assignments followed by execution
    "=['\"]?rm['\"]?\\s*[;&|]", # VAR=rm; or VAR='rm' &&
    "=['\"]?sudo['\"]?\\s*[;&|]",
    "=['\"]?dd['\"]?\\s*[;&|]",
    "=['\"]?chmod['\"]?\\s*[;&|]",
    "=['\"]?mkfs['\"]?\\s*[;&|]",

    # Base64/encoding piping to shell
    "base64.*\\|.*\\b(ba)?sh\\b", # base64 -d | bash
    "base64.*\\|.*\\bsh\\b",
    "\\|\\s*(ba)?sh\\s*$", # anything | bash at end
    "\\|\\s*/bin/(ba)?sh", # pipe to /bin/bash
    "xxd.*\\|.*\\b(ba)?sh\\b", # xxd -r | bash (hex decoding)
    "printf.*\\\\x.*\\|", # printf with hex escapes piped

    # Quote splitting obfuscation (r"m" or 'r''m')
    "['\"][a-z]['\"]['\"]?[a-z]", # "r""m" style splitting
    "\\\\[a-z]", # \r\m backslash escaping in commands

    # Hex/octal escape sequences in commands
    "\\$'\\\\x[0-9a-fA-F]", # $'\x72\x6d' style
    "\\$'\\\\[0-7]{3}", # $'\162\155' octal style
    "echo\\s+-e.*\\\\x", # echo -e with hex
    "printf.*%s.*\\\\x", # printf with hex

    # IFS manipulation (space replacement attacks)
    "IFS=", # IFS manipulation
    "\\$\\{IFS\\}", # ${IFS} usage

    # Brace expansion attacks
    "\\{[a-z],[a-z]\\}", # {r,m} style

    # Here-string/here-doc to shell
    "<<<.*\\b(ba)?sh\\b", # <<< to bash
    "<<\\s*['\"]?EOF", # heredoc markers (suspicious in single commands)

    # Aliases and functions for evasion
    "alias\\s+[a-z]+=", # alias definitions
    "function\\s+[a-z]+\\s*\\(", # function definitions

    # Network data exfiltration via DNS/other channels
    "dig\\s+.*\\$", # DNS exfiltration with variables
    "nslookup\\s+.*\\$",
    "host\\s+.*\\$",

    # Additional shell escapes
    "xargs.*\\b(ba)?sh\\b", # xargs feeding to shell
    "find.*-exec.*\\b(ba)?sh\\b", # find -exec bash
    "awk.*system\\s*\\(", # awk system() calls
    "perl\\s+-e", # perl one-liners
    "python\\s+-c", # python one-liners
    "ruby\\s+-e", # ruby one-liners

    # Process substitution attacks
    "<\\(.*\\b(ba)?sh\\b", # <(bash ...) process substitution
    ">\\(.*\\b(ba)?sh\\b" # >(bash ...) process substitution
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
#' Convenience function to create a PreToolUse hook that applies Deputy's
#' canonical file-write permission policy to `write_file`, `edit_file`, and
#' `multi_edit`. Prefer configuring [Permissions] as the Agent's authority
#' policy; this helper is useful as an additional hook-level restriction.
#'
#' @param allowed_dir Existing directory where writes are allowed. The path is
#'   canonicalized when the hook is created.
#' @return A [HookMatcher] object
#'
#' @examples
#' \dontrun{
#' dir.create("output", showWarnings = FALSE)
#' agent$add_hook(hook_limit_file_writes("output"))
#' }
#'
#' @seealso [Permissions]
#' @export
hook_limit_file_writes <- function(allowed_dir) {
  allowed_dir <- normalizePath(allowed_dir, mustWork = TRUE)
  permissions <- Permissions$new(
    file_write = allowed_dir,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE
  )

  HookMatcher$new(
    event = "PreToolUse",
    pattern = "^(write_file|edit_file|multi_edit)$",
    timeout = 0, # Run in main process
    callback = function(tool_name, tool_input, context) {
      result <- permissions$check(tool_name, tool_input, context)
      if (identical(result$decision, "deny")) {
        HookResultPreToolUse(
          permission = "deny",
          reason = result$reason
        )
      } else {
        HookResultPreToolUse(permission = "allow")
      }
    }
  )
}
