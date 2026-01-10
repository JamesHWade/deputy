# Structured error types for deputy
#
# This module provides a hierarchy of error types for programmatic error
# handling. All errors inherit from DeputyError and include structured
# context for debugging. Errors use cli formatting for nice output.

#' Deputy Error Classes
#'
#' @description
#' Structured error types for programmatic error handling in deputy.
#' All deputy errors inherit from `deputy_error` and include contextual
#' information for debugging. Errors use cli formatting for readable output.
#'
#' @section Error Hierarchy:
#'
#' - **deputy_error** - Base class for all deputy errors
#'   - **deputy_permission** - Permission-related failures
#'     - `deputy_permission_denied` - Tool/action not allowed by permissions
#'   - **deputy_tool** - Tool execution failures
#'     - `deputy_tool_execution` - Tool failed during execution
#'   - **deputy_budget** - Resource limit violations
#'     - `deputy_budget_exceeded` - Cost limit exceeded
#'     - `deputy_turn_limit` - Max turns exceeded
#'   - **deputy_provider** - LLM provider failures
#'   - **deputy_session** - Session management failures
#'     - `deputy_session_load` - Failed to load session
#'     - `deputy_session_save` - Failed to save session
#'   - **deputy_hook** - Hook execution failures
#'
#' @section Usage:
#'
#' Errors can be caught using `tryCatch()` with class-based matching:
#'
#' ```r
#' tryCatch(
#'   agent$run_sync("task"),
#'   deputy_budget_exceeded = function(e) {
#'     message("Budget exceeded: ", conditionMessage(e))
#'     message("Current cost: $", e$current_cost)
#'   },
#'   deputy_error = function(e) {
#'     message("Deputy error: ", conditionMessage(e))
#'   }
#' )
#' ```
#'
#' @name deputy-errors
#' @aliases DeputyError
NULL

#' Abort with a structured deputy error
#'
#' @description
#' Creates and signals a structured deputy error using cli formatting.
#' All deputy errors include a message, optional context, and inherit
#' from the `deputy_error` condition class.
#'
#' @param message The error message (supports cli formatting)
#' @param class Additional classes to add (will be prefixed with "deputy_")
#' @param ... Additional fields to include in the error condition
#' @param .envir Environment for cli interpolation
#'
#' @return Does not return; signals an error condition
#'
#' @examples
#' \dontrun{
#' # Signal an error
#' abort_deputy("Something went wrong", class = "custom")
#'
#' # Catch deputy errors
#' tryCatch(
#'   abort_deputy("test"),
#'   deputy_error = function(e) message("Caught: ", conditionMessage(e))
#' )
#' }
#'
#' @export
abort_deputy <- function(message, class = NULL, ..., .envir = parent.frame()) {
  # Build class hierarchy
  classes <- c(
    paste0("deputy_", class),
    "deputy_error"
  )
  # Remove any empty class names
  classes <- classes[nzchar(classes)]

  cli_abort(
    message,
    class = classes,
    ...,
    .envir = .envir
  )
}

#' Abort with a permission denied error
#'
#' @description
#' Signals that an operation was denied by the permission system.
#'
#' @param message The error message (supports cli formatting)
#' @param tool_name Name of the tool that was denied (optional)
#' @param permission_mode The current permission mode (optional)
#' @param reason Reason for denial (optional)
#' @param ... Additional context fields
#' @param .envir Environment for cli interpolation
#'
#' @examples
#' \dontrun{
#' abort_permission_denied(
#'   "Write operations not allowed in {.val {mode}} mode",
#'   tool_name = "write_file",
#'   permission_mode = "readonly"
#' )
#' }
#'
#' @export
abort_permission_denied <- function(
  message,
  tool_name = NULL,
  permission_mode = NULL,
  reason = NULL,
  ...,
  .envir = parent.frame()
) {
  abort_deputy(
    message,
    class = c("permission_denied", "permission"),
    tool_name = tool_name,
    permission_mode = permission_mode,
    reason = reason,
    ...,
    .envir = .envir
  )
}

#' Abort with a tool execution error
#'
#' @description
#' Signals that a tool failed during execution.
#'
#' @param message The error message (supports cli formatting)
#' @param tool_name Name of the tool that failed
#' @param tool_input The input that was passed to the tool (optional)
#' @param parent The parent error that caused the failure (optional)
#' @param ... Additional context fields
#' @param .envir Environment for cli interpolation
#'
#' @examples
#' \dontrun{
#' abort_tool_execution(
#'   c("Tool {.fn {tool_name}} failed", "x" = "File not found"),
#'   tool_name = "read_file",
#'   tool_input = list(path = "/nonexistent/file.txt")
#' )
#' }
#'
#' @export
abort_tool_execution <- function(
  message,
  tool_name,
  tool_input = NULL,
  parent = NULL,
  ...,
  .envir = parent.frame()
) {
  cli_abort(
    message,
    class = c("deputy_tool_execution", "deputy_tool", "deputy_error"),
    tool_name = tool_name,
    tool_input = tool_input,
    parent = parent,
    ...,
    .envir = .envir
  )
}

#' Abort with a budget exceeded error
#'
#' @description
#' Signals that the agent exceeded its cost budget.
#'
#' @param message The error message (supports cli formatting)
#' @param current_cost The current accumulated cost
#' @param max_cost The maximum allowed cost
#' @param ... Additional context fields
#' @param .envir Environment for cli interpolation
#'
#' @examples
#' \dontrun{
#' abort_budget_exceeded(
#'   "Cost limit exceeded: ${current_cost} > ${max_cost}",
#'   current_cost = 0.55,
#'   max_cost = 0.50
#' )
#' }
#'
#' @export
abort_budget_exceeded <- function(
  message,
  current_cost = NULL,
  max_cost = NULL,
  ...,
  .envir = parent.frame()
) {
  abort_deputy(
    message,
    class = c("budget_exceeded", "budget"),
    current_cost = current_cost,
    max_cost = max_cost,
    ...,
    .envir = .envir
  )
}

#' Abort with a turn limit error
#'
#' @description
#' Signals that the agent exceeded its maximum turn limit.
#'
#' @param message The error message (supports cli formatting)
#' @param current_turns The number of turns executed
#' @param max_turns The maximum allowed turns
#' @param ... Additional context fields
#' @param .envir Environment for cli interpolation
#'
#' @examples
#' \dontrun{
#' abort_turn_limit(
#'   "Maximum turns exceeded: {current_turns}/{max_turns}",
#'   current_turns = 25,
#'   max_turns = 25
#' )
#' }
#'
#' @export
abort_turn_limit <- function(
  message,
  current_turns = NULL,
  max_turns = NULL,
  ...,
  .envir = parent.frame()
) {
  abort_deputy(
    message,
    class = c("turn_limit", "budget"),
    current_turns = current_turns,
    max_turns = max_turns,
    ...,
    .envir = .envir
  )
}

#' Abort with a provider error
#'
#' @description
#' Signals that the LLM provider encountered an error.
#'
#' @param message The error message (supports cli formatting)
#' @param provider_name Name of the provider (e.g., "openai", "anthropic")
#' @param model The model being used (optional)
#' @param parent The parent error from the provider (optional)
#' @param ... Additional context fields
#' @param .envir Environment for cli interpolation
#'
#' @examples
#' \dontrun{
#' abort_provider(
#'   c("API error from {.val {provider_name}}", "x" = "Rate limit exceeded"),
#'   provider_name = "openai",
#'   model = "gpt-4o"
#' )
#' }
#'
#' @export
abort_provider <- function(
  message,
  provider_name = NULL,
  model = NULL,
  parent = NULL,
  ...,
  .envir = parent.frame()
) {
  abort_deputy(
    message,
    class = "provider",
    provider_name = provider_name,
    model = model,
    parent = parent,
    ...,
    .envir = .envir
  )
}

#' Abort with a session load error
#'
#' @description
#' Signals that loading a session file failed.
#'
#' @param message The error message (supports cli formatting)
#' @param path Path to the session file
#' @param parent The parent error that caused the failure (optional)
#' @param ... Additional context fields
#' @param .envir Environment for cli interpolation
#'
#' @examples
#' \dontrun{
#' abort_session_load(
#'   c("Failed to load session", "x" = "File corrupted"),
#'   path = "agent_session.rds"
#' )
#' }
#'
#' @export
abort_session_load <- function(
  message,
  path = NULL,
  parent = NULL,
  ...,
  .envir = parent.frame()
) {
  abort_deputy(
    message,
    class = c("session_load", "session"),
    path = path,
    parent = parent,
    ...,
    .envir = .envir
  )
}

#' Abort with a session save error
#'
#' @description
#' Signals that saving a session file failed.
#'
#' @param message The error message (supports cli formatting)
#' @param path Path where the session was being saved
#' @param parent The parent error that caused the failure (optional)
#' @param ... Additional context fields
#' @param .envir Environment for cli interpolation
#'
#' @examples
#' \dontrun{
#' abort_session_save(
#'   "Cannot write to {.path {path}}",
#'   path = "/readonly/path/session.rds"
#' )
#' }
#'
#' @export
abort_session_save <- function(
  message,
  path = NULL,
  parent = NULL,
  ...,
  .envir = parent.frame()
) {
  abort_deputy(
    message,
    class = c("session_save", "session"),
    path = path,
    parent = parent,
    ...,
    .envir = .envir
  )
}

#' Abort with a hook error
#'
#' @description
#' Signals that a hook callback failed during execution.
#'
#' @param message The error message (supports cli formatting)
#' @param hook_event The hook event type (e.g., "PreToolUse", "PostToolUse")
#' @param parent The parent error from the hook callback (optional)
#' @param ... Additional context fields
#' @param .envir Environment for cli interpolation
#'
#' @examples
#' \dontrun{
#' abort_hook(
#'   c("Hook {.val {hook_event}} failed", "x" = "Callback error"),
#'   hook_event = "PreToolUse"
#' )
#' }
#'
#' @export
abort_hook <- function(
  message,
  hook_event = NULL,
  parent = NULL,
  ...,
  .envir = parent.frame()
) {
  abort_deputy(
    message,
    class = "hook",
    hook_event = hook_event,
    parent = parent,
    ...,
    .envir = .envir
  )
}

#' Check if an object is a deputy error
#'
#' @description
#' Tests whether an object is a deputy error condition.
#'
#' @param x Object to test
#' @param class Optional specific error class to check for (without "deputy_" prefix)
#'
#' @return Logical indicating if `x` is a deputy error (of the specified class)
#'
#' @examples
#' \dontrun{
#' tryCatch(
#'   abort_deputy("test"),
#'   error = function(e) {
#'     is_deputy_error(e)
#'     # TRUE
#'   }
#' )
#' }
#'
#' @export
is_deputy_error <- function(x, class = NULL) {
  if (!inherits(x, "deputy_error")) {
    return(FALSE)
  }

  if (is.null(class)) {
    return(TRUE)
  }

  inherits(x, paste0("deputy_", class))
}
