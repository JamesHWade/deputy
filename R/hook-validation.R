# Internal validation for HookMatcher configuration.

hook_callback_arguments <- list(
  PreToolUse = c("tool_name", "tool_input", "context"),
  PostToolUse = c("tool_name", "tool_result", "tool_error", "context"),
  PostToolUseFailure = c(
    "tool_name",
    "tool_result",
    "tool_error",
    "context"
  ),
  Stop = c("reason", "context"),
  SubagentStart = c("agent_name", "task", "context"),
  SubagentStop = c("agent_name", "task", "result", "context"),
  UserPromptSubmit = c("prompt", "context"),
  Notification = c("message", "context"),
  PermissionRequest = c(
    "tool_name",
    "tool_input",
    "permission_result",
    "context"
  ),
  ConfigChange = c("key", "old_value", "new_value", "context"),
  PreCompact = c("turns_to_compact", "turns_to_keep", "context"),
  SessionStart = "context",
  SessionEnd = c("reason", "context")
)

validate_hook_callback <- function(event, callback) {
  callback_formals <- formals(callback)
  expected <- hook_callback_arguments[[event]]
  signature <- paste0("function(", paste(expected, collapse = ", "), ")")

  if (!is.null(callback_formals) && "..." %in% names(callback_formals)) {
    return(invisible(callback))
  }

  actual <- names(callback_formals)
  missing_expected <- setdiff(expected, actual)
  extra <- setdiff(actual, expected)
  required_extra <- extra[vapply(
    callback_formals[extra],
    function(value) identical(value, quote(expr = )),
    logical(1)
  )]

  if (
    is.null(callback_formals) ||
      length(missing_expected) > 0L ||
      length(required_extra) > 0L
  ) {
    cli_abort(c(
      "Invalid callback for {.val {event}} hook.",
      "i" = paste0(
        "Expected signature: ",
        signature,
        " or a callback accepting `...`."
      )
    ))
  }

  invisible(callback)
}

validate_hook_pattern <- function(pattern) {
  if (is.null(pattern)) {
    return(invisible(pattern))
  }
  if (
    !is.character(pattern) ||
      length(pattern) != 1L ||
      is.na(pattern)
  ) {
    cli_abort("{.arg pattern} must be NULL or one non-missing string")
  }

  valid <- tryCatch(
    {
      suppressWarnings(grepl(pattern, ""))
      TRUE
    },
    error = function(error) FALSE
  )
  if (!valid) {
    cli_abort("Invalid hook pattern: {.val {pattern}}")
  }

  invisible(pattern)
}
