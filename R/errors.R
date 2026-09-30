# Structured error types for deputy
#
# This module provides a hierarchy of error types for programmatic error
# handling. All errors inherit from DeputyError and include structured
# context for debugging. Errors use cli formatting for nice output.

#' Deputy error classes
#'
#' @description
#' Errors signalled by deputy have class `deputy_error` plus more specific
#' classes, so you can catch them by class with `tryCatch()`. Many carry extra
#' fields, such as `tool_name` or `limit`. Errors from ellmer or the provider,
#' such as HTTP errors, are passed through unchanged.
#'
#' @section Error classes:
#'
#' - `deputy_error`: every deputy error.
#'   - `deputy_permission_denied` (also `deputy_permission`): an action
#'     wasn't allowed.
#'   - `deputy_tool_execution` (also `deputy_tool`): a tool failed.
#'   - `deputy_budget`: a usage limit was reached. Only signalled when
#'     [UsageLimits()] has `on_exceed = "error"`.
#'     - `deputy_request_limit`: `max_requests` was reached.
#'     - `deputy_cost_unavailable`: `max_cost_usd` is set but a response's cost
#'       is unknown.
#'     - `deputy_budget_exceeded`: a tool-call, token or cost limit was
#'       reached. The error's `budget_type`, `actual` and `limit` fields say
#'       which.
#'   - `deputy_session_load`, `deputy_session_save` (also `deputy_session`):
#'     loading or saving a session file failed.
#'   - `deputy_human_input_unavailable`: an `ask_user` request couldn't reach
#'     a person, for example in a non-interactive session with no handler.
#'
#' Other deputy errors, such as `deputy_run_active` (the agent is already
#' running), also inherit from `deputy_error`.
#'
#' @section Usage:
#'
#' ```r
#' tryCatch(
#'   agent$run_sync("task"),
#'   deputy_budget = function(e) {
#'     message("Usage limit reached: ", conditionMessage(e))
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

#' Signal a Deputy error
#'
#' @description
#' Signals an error of class `deputy_error`, plus `deputy_<class>` for each
#' extra class, with the message formatted by cli.
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
#' # Catch Deputy errors
#' tryCatch(
#'   abort_deputy("test"),
#'   deputy_error = function(e) message("Caught: ", conditionMessage(e))
#' )
#' }
#'
#' @noRd
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

#' Signal a permission denied error
#'
#' @description
#' Signals that an action was not allowed.
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
#'   "Write operations not allowed in {.val readonly} mode",
#'   tool_name = "write_file",
#'   permission_mode = "readonly"
#' )
#' }
#'
#' @noRd
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

#' Signal a tool execution error
#'
#' @description
#' Signals that a tool failed while running.
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
#' @noRd
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

#' Signal a budget exceeded error
#'
#' @description
#' Signals that a run reached a tool-call, token or cost limit.
#'
#' @param message The error message (supports cli formatting)
#' @param current_cost The run's cost, for cost limits
#' @param max_cost The cost limit, for cost limits
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
#' @noRd
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

abort_cost_unavailable <- function(
  message,
  max_cost,
  ...,
  .envir = parent.frame()
) {
  abort_deputy(
    message,
    class = c("cost_unavailable", "budget"),
    max_cost = max_cost,
    ...,
    .envir = .envir
  )
}

#' Signal a request limit error
#'
#' @description
#' Signals that a run reached its model request limit.
#'
#' @param message The error message (supports cli formatting)
#' @param current_requests The number of model requests made
#' @param max_requests The maximum allowed model requests
#' @param ... Additional context fields
#' @param .envir Environment for cli interpolation
#'
#' @examples
#' \dontrun{
#' abort_request_limit(
#'   "Maximum requests exceeded: {current_requests}/{max_requests}",
#'   current_requests = 25,
#'   max_requests = 25
#' )
#' }
#'
#' @noRd
abort_request_limit <- function(
  message,
  current_requests = NULL,
  max_requests = NULL,
  ...,
  .envir = parent.frame()
) {
  abort_deputy(
    message,
    class = c("request_limit", "budget"),
    current_requests = current_requests,
    max_requests = max_requests,
    ...,
    .envir = .envir
  )
}

#' Signal a provider error
#'
#' @description
#' Signals that the LLM provider returned an error.
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
#'   model = "gpt-6-luna"
#' )
#' }
#'
#' @noRd
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

#' Signal a session load error
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
#' @noRd
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

#' Signal a session save error
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
#' @noRd
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

#' Signal a hook error
#'
#' @description
#' Signals that a hook callback failed.
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
#' @noRd
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

#' Check whether a condition is a Deputy error
#'
#' @description
#' Tests whether `x` is an error signalled by Deputy, optionally of a specific
#' class. See [deputy-errors] for the classes.
#'
#' @param x Object to test.
#' @param class Optional error class to check for, without the `"deputy_"`
#'   prefix, such as `"budget"`.
#'
#' @return `TRUE` if `x` has class `deputy_error` (and `deputy_<class>` when
#'   `class` is given), otherwise `FALSE`.
#'
#' @examples
#' \dontrun{
#' result <- tryCatch(
#'   agent$run_sync("Summarise the logs"),
#'   error = function(e) e
#' )
#' if (is_deputy_error(result, "budget")) {
#'   message("A usage limit stopped the run.")
#' }
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
