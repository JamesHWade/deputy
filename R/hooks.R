# Hook system for deputy agents

#' Hook events supported by deputy
#'
#' @description
#' Hook events are fired at specific points during agent execution:
#' * `"PreToolUse"` - Before a tool is executed (can deny)
#' * `"PostToolUse"` - After a tool completes
#' * `"Stop"` - When the agent stops
#' * `"UserPromptSubmit"` - When a user prompt is submitted
#' * `"PreCompact"` - Before conversation compaction (future)
#'
#' @export
HookEvent <- c(
"PreToolUse",
"PostToolUse",
  "Stop",
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
      cat("  pattern:", if (is.null(self$pattern)) "<any>" else self$pattern, "\n")
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
    timeout = 0,  # Run in main process for cli output
    callback = function(tool_name, tool_result, tool_error, context) {
      if (!is.null(tool_error)) {
        cli::cli_alert_danger(paste0("Tool ", tool_name, " failed: ", tool_error))
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
#' dangerous bash commands like `rm -rf`, `sudo`, etc.
#'
#' @param patterns Character vector of regex patterns to block
#' @return A [HookMatcher] object
#'
#' @examples
#' \dontrun{
#' agent$add_hook(hook_block_dangerous_bash())
#' }
#'
#' @export
hook_block_dangerous_bash <- function(
  patterns = c("rm\\s+-rf", "sudo", "chmod\\s+777", "mkfs", "dd\\s+if=", ">\\s*/dev/")
) {
  combined_pattern <- paste(patterns, collapse = "|")

  HookMatcher$new(
    event = "PreToolUse",
    pattern = "^(run_bash|bash|tool_run_bash)$",
    timeout = 0,  # Run in main process
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
    timeout = 0,  # Run in main process
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
