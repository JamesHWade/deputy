#' @include value-properties.R
NULL

validate_callback_flag <- function(value, arg) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    cli_abort("{.arg {arg}} must be one non-missing logical value")
  }
  value
}

validate_callback_text <- function(value, arg, optional = TRUE) {
  if (is.null(value) && optional) {
    return(value)
  }
  if (!rlang::is_string(value)) {
    cli_abort(
      "{.arg {arg}} must be {if (optional) 'NULL or ' else ''}one non-missing string"
    )
  }
  value
}

#' Hook and permission results
#'
#' @description
#' `HookResult` and `PermissionResult` are the parent classes of the values
#' that hook and permission callbacks return. You don't create them directly;
#' use [HookResultPreToolUse()], [HookResultPostToolUse()],
#' [HookResultPreCompact()], [PermissionResultAllow()],
#' [PermissionResultDeny()] or [PermissionResultPending()]. To test which kind
#' a value is, use `S7::S7_inherits(x, PermissionResult)`.
#'
#' Results are read-only. Read fields with `$` (a missing field gives `NULL`),
#' `@` or `S7::prop()`, or get them all as a list with `S7::props()`. To change
#' a decision, create a new result.
#' @name CallbackResult
#' @export
HookResult <- S7::new_class("HookResult", package = "deputy", abstract = TRUE)

#' @rdname CallbackResult
#' @export
PermissionResult <- S7::new_class(
  "PermissionResult",
  package = "deputy",
  abstract = TRUE
)

local({
  S7::method(`$`, HookResult) <- function(x, name) S7::props(x)[[name]]
  S7::method(`$`, PermissionResult) <- function(x, name) S7::props(x)[[name]]
})

#' Create a PreToolUse hook result
#'
#' @description
#' Return this from a PreToolUse hook to allow or deny a tool call. A hook can
#' only deny calls that the permission policy has already allowed.
#'
#' @param permission Either `"allow"` or `"deny"`.
#' @param reason Why the call was denied. The model sees it.
#' @param continue `TRUE` or `FALSE`. `FALSE` stops the run.
#' @param additional_context Optional text to add to the agent's system prompt.
#'   It stays there for later turns; the same text is only added once.
#' @param stop_reason Optional stop reason used when `continue = FALSE`.
#'   Defaults to `"hook_requested_stop"`.
#' @seealso [CallbackResult] for reading result fields.
#' @return A `HookResultPreToolUse` object.
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
HookResultPreToolUse <- S7::new_class(
  "HookResultPreToolUse",
  parent = HookResult,
  package = "deputy",
  properties = list(
    permission = readonly_property("permission", S7::class_character),
    reason = readonly_property(
      "reason",
      S7::new_union(S7::class_character, NULL)
    ),
    continue = readonly_property("continue", S7::class_logical),
    additional_context = readonly_property(
      "additional_context",
      S7::new_union(S7::class_character, NULL)
    ),
    stop_reason = readonly_property(
      "stop_reason",
      S7::new_union(S7::class_character, NULL)
    )
  ),
  constructor = function(
    permission = c("allow", "deny"),
    reason = NULL,
    continue = TRUE,
    additional_context = NULL,
    stop_reason = NULL
  ) {
    value <- S7::new_object(
      S7::S7_object(),
      permission = match.arg(permission),
      reason = validate_callback_text(reason, "reason"),
      continue = validate_callback_flag(continue, "continue"),
      additional_context = validate_callback_text(
        additional_context,
        "additional_context"
      ),
      stop_reason = validate_callback_text(stop_reason, "stop_reason")
    )
    freeze_value(value)
  }
)

#' Create a PostToolUse hook result
#'
#' @description
#' Return this from a PostToolUse hook to stop the run or to change what the
#' agent's `tool_end` event reports. The model always sees the tool's real
#' result.
#'
#' @param continue `TRUE` or `FALSE`. `FALSE` stops the run after this tool
#'   call.
#' @param suppress_output If `TRUE`, leave the result out of the `tool_end`
#'   event.
#' @param updated_tool_output Optional value to report in the `tool_end` event
#'   instead of the tool's result.
#' @param additional_context Optional text to add to the agent's system prompt.
#'   It stays there for later turns; the same text is only added once.
#' @param stop_reason Optional stop reason used when `continue = FALSE`.
#'   Defaults to `"hook_requested_stop"`.
#' @seealso [CallbackResult] for reading result fields.
#' @return A `HookResultPostToolUse` object.
#'
#' @examples
#' # Continue execution
#' HookResultPostToolUse()
#'
#' # Stop after this tool
#' HookResultPostToolUse(continue = FALSE)
#'
#' @export
HookResultPostToolUse <- S7::new_class(
  "HookResultPostToolUse",
  parent = HookResult,
  package = "deputy",
  properties = list(
    continue = readonly_property("continue", S7::class_logical),
    suppress_output = readonly_property("suppress_output", S7::class_logical),
    updated_tool_output = readonly_property(
      "updated_tool_output",
      S7::class_any
    ),
    additional_context = readonly_property(
      "additional_context",
      S7::new_union(S7::class_character, NULL)
    ),
    stop_reason = readonly_property(
      "stop_reason",
      S7::new_union(S7::class_character, NULL)
    )
  ),
  constructor = function(
    continue = TRUE,
    suppress_output = FALSE,
    updated_tool_output = NULL,
    additional_context = NULL,
    stop_reason = NULL
  ) {
    value <- S7::new_object(
      S7::S7_object(),
      continue = validate_callback_flag(continue, "continue"),
      suppress_output = isTRUE(suppress_output),
      updated_tool_output = updated_tool_output,
      additional_context = validate_callback_text(
        additional_context,
        "additional_context"
      ),
      stop_reason = validate_callback_text(stop_reason, "stop_reason")
    )
    freeze_value(value)
  }
)

#' Create a PreCompact hook result
#'
#' @description
#' Return this from a PreCompact hook to cancel compaction or to supply the
#' summary yourself.
#'
#' @param continue `TRUE` or `FALSE`. `FALSE` cancels the compaction.
#' @param summary Optional summary to use instead of generating one.
#' @seealso [CallbackResult] for reading result fields.
#' @return A `HookResultPreCompact` object.
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
HookResultPreCompact <- S7::new_class(
  "HookResultPreCompact",
  parent = HookResult,
  package = "deputy",
  properties = list(
    continue = readonly_property("continue", S7::class_logical),
    summary = readonly_property(
      "summary",
      S7::new_union(S7::class_character, NULL)
    )
  ),
  constructor = function(continue = TRUE, summary = NULL) {
    value <- S7::new_object(
      S7::S7_object(),
      continue = validate_callback_flag(continue, "continue"),
      summary = validate_callback_text(summary, "summary")
    )
    freeze_value(value)
  }
)

#' Create an allow permission result
#'
#' @description
#' Return this from a `can_use_tool` callback or a PermissionRequest hook to
#' allow a tool call.
#'
#' @param message Optional note stored on the result. Deputy doesn't show it
#'   to the model or the user.
#' @seealso [CallbackResult] for reading result fields.
#' @return A `PermissionResultAllow` object.
#'
#' @examples
#' # Allow a tool call
#' PermissionResultAllow()
#'
#' # Allow with a message
#' PermissionResultAllow(message = "Tool approved by custom callback")
#'
#' @export
PermissionResultAllow <- S7::new_class(
  "PermissionResultAllow",
  parent = PermissionResult,
  package = "deputy",
  properties = list(
    decision = readonly_property("decision", S7::class_character),
    message = readonly_property(
      "message",
      S7::new_union(S7::class_character, NULL)
    )
  ),
  constructor = function(message = NULL) {
    value <- S7::new_object(
      S7::S7_object(),
      decision = "allow",
      message = validate_callback_text(message, "message")
    )
    freeze_value(value)
  }
)

#' Create a deny permission result
#'
#' @description
#' Return this from a `can_use_tool` callback or a PermissionRequest hook to
#' deny a tool call.
#'
#' @param reason Why the call was denied. The model sees it.
#' @param interrupt `TRUE` or `FALSE`. `TRUE` also stops the run, with stop
#'   reason `"permission_denied"`.
#' @seealso [CallbackResult] for reading result fields.
#' @return A `PermissionResultDeny` object.
#'
#' @examples
#' # Deny a tool call
#' PermissionResultDeny(reason = "File write not allowed")
#'
#' # Deny and stop the run
#' PermissionResultDeny(reason = "Critical security violation", interrupt = TRUE)
#'
#' @export
PermissionResultDeny <- S7::new_class(
  "PermissionResultDeny",
  parent = PermissionResult,
  package = "deputy",
  properties = list(
    decision = readonly_property("decision", S7::class_character),
    reason = readonly_property("reason", S7::class_character),
    interrupt = readonly_property("interrupt", S7::class_logical)
  ),
  constructor = function(reason, interrupt = FALSE) {
    value <- S7::new_object(
      S7::S7_object(),
      decision = "deny",
      reason = validate_callback_text(reason, "reason", optional = FALSE),
      interrupt = validate_callback_flag(interrupt, "interrupt")
    )
    freeze_value(value)
  }
)
