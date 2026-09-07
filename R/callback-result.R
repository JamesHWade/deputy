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

#' Callback result value families
#'
#' @description
#' Abstract S7 bases for hook and permission results. Construct a concrete
#' result with [HookResultPreToolUse()], [HookResultPostToolUse()],
#' [HookResultPreCompact()], [PermissionResultAllow()], or
#' [PermissionResultDeny()]. Test family membership with `S7::S7_inherits()`.
#'
#' Result properties are read-only after construction. Read with `@`,
#' `S7::prop()`, or `$`; missing `$` fields return NULL. Use `S7::props()`
#' for a plain list of properties and construct a new result to change a
#' decision. S3 class tags and whole-result list indexing are not supported.
#' Objects stored in `updated_tool_output` retain their own reference
#' semantics; freezing a result does not freeze an environment inside it.
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
#' Return this from a PreToolUse hook callback to control tool execution.
#'
#' @param permission Either `"allow"` or `"deny"`
#' @param reason Reason for denial (shown to the LLM)
#' @param continue One non-missing logical value. If FALSE, stop the agent after this hook
#' @param additional_context Optional text to append to the running context
#' @param stop_reason Optional stop reason used when `continue = FALSE`
#' @seealso [CallbackResult] for read-only properties and S7 inspection.
#' @return A `HookResultPreToolUse` S7 object
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
#' Return this from a PostToolUse hook callback.
#'
#' @param continue One non-missing logical value. If FALSE, stop the agent after this hook
#' @param suppress_output Coerced with `isTRUE()`. Whether to suppress the result on Deputy's emitted
#'   `tool_end` event. This does not remove the result from model context.
#' @param updated_tool_output Optional replacement value for Deputy's emitted
#'   `tool_end` event. ellmer does not support rewriting the model-visible
#'   in-flight result from this callback.
#' @param additional_context Optional text to append to the running context
#' @param stop_reason Optional stop reason used when `continue = FALSE`
#' @seealso [CallbackResult] for read-only properties and S7 inspection.
#' @return A `HookResultPostToolUse` S7 object
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
#' Return this from a PreCompact hook callback to control whether compaction
#' should proceed.
#'
#' @param continue One non-missing logical value. If FALSE, cancels the compaction
#' @param summary Optional custom summary to use for compaction
#' @seealso [CallbackResult] for read-only properties and S7 inspection.
#' @return A `HookResultPreCompact` S7 object
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
#' Returns a permission result that allows the tool to execute.
#'
#' @param message Optional message to display
#' @seealso [CallbackResult] for read-only properties and S7 inspection.
#' @return A `PermissionResultAllow` S7 object
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
#' Returns a permission result that denies the tool from executing.
#'
#' @param reason Reason for denial (shown to the LLM)
#' @param interrupt One non-missing logical value. If TRUE, stop the entire conversation (default FALSE)
#' @seealso [CallbackResult] for read-only properties and S7 inspection.
#' @return A `PermissionResultDeny` S7 object
#'
#' @examples
#' # Deny a tool call
#' PermissionResultDeny(reason = "File write not allowed")
#'
#' # Deny and interrupt the conversation
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
