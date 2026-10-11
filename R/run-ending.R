#' @include value-properties.R
NULL

# The stop and failure reasons deputy sets, grouped by the ending they map to.
# `run_ending_for()` reads these; the tests read them too.
run_ending_limit_reasons <- c(
  "request_limit",
  "tool_call_limit",
  "input_token_limit",
  "output_token_limit",
  "total_token_limit",
  "cost_limit",
  "cost_unavailable",
  "tool_loop"
)

run_ending_failure_reasons <- c(
  "error",
  "provider_error",
  "file_checkpoint_error",
  "delegation_error",
  "batch_error",
  "setup_error",
  "setup_failed"
)

run_ending_stop_by <- c(
  "caller",
  "hook",
  "permission",
  "approval",
  "parent",
  "delegation",
  "abandoned"
)

run_ending_cut_off_reasons <- c(
  "max_tokens",
  "context_window",
  "content_filter"
)

run_ending_stop_reasons <- c(
  interrupted = "caller",
  hook_requested_stop = "hook",
  permission_denied = "permission",
  approval_pending = "approval",
  parent_completed = "parent",
  delegation_stopped = "delegation",
  not_started = "delegation",
  abandoned = "abandoned"
)

# An optional string field: NULL, or one non-missing string.
ending_optional_text <- function(value, arg) {
  if (!is.null(value) && !rlang::is_string(value)) {
    cli_abort("{.arg {arg}} must be NULL or one non-missing string")
  }
  value
}

#' How an agent run ended
#'
#' @description
#' `RunEnding` is the parent class of the values an [AgentResult] carries in
#' its `ending` property. It says how the run ended and holds only what that
#' ending has. You don't create it directly; use [RunEndingAnswered()],
#' [RunEndingStopped()], [RunEndingLimit()], [RunEndingCutOff()] or
#' [RunEndingFailed()]. Read a property with `$`, `@` or [S7::prop()].
#' @name RunEnding
#' @export
RunEnding <- S7::new_class("RunEnding", package = "deputy", abstract = TRUE)

#' @rdname RunEnding
#' @export
RunEndingAnswered <- S7::new_class(
  "RunEndingAnswered",
  parent = RunEnding,
  package = "deputy",
  constructor = function() {
    value <- S7::new_object(S7::S7_object())
    freeze_value(value)
  }
)

#' @rdname RunEnding
#' @export
RunEndingStopped <- S7::new_class(
  "RunEndingStopped",
  parent = RunEnding,
  package = "deputy",
  properties = list(
    by = readonly_property("by", S7::class_character),
    reason = readonly_property(
      "reason",
      S7::new_union(S7::class_character, NULL)
    )
  ),
  constructor = function(by, reason = NULL) {
    by <- match.arg(by, run_ending_stop_by)
    value <- S7::new_object(
      S7::S7_object(),
      by = by,
      reason = ending_optional_text(reason, "reason")
    )
    freeze_value(value)
  }
)

#' @rdname RunEnding
#' @export
RunEndingLimit <- S7::new_class(
  "RunEndingLimit",
  parent = RunEnding,
  package = "deputy",
  properties = list(
    reason = readonly_property("reason", S7::class_character),
    field = readonly_property(
      "field",
      S7::new_union(S7::class_character, NULL)
    ),
    actual = readonly_property(
      "actual",
      S7::new_union(S7::class_numeric, NULL)
    ),
    limit = readonly_property(
      "limit",
      S7::new_union(S7::class_numeric, NULL)
    )
  ),
  constructor = function(reason, field = NULL, actual = NULL, limit = NULL) {
    reason <- match.arg(reason, run_ending_limit_reasons)
    if (!is.null(actual) && (!is.numeric(actual) || length(actual) != 1L)) {
      cli_abort("{.arg actual} must be NULL or one number")
    }
    if (
      !is.null(limit) &&
        (!is.numeric(limit) || length(limit) != 1L || is.na(limit))
    ) {
      cli_abort("{.arg limit} must be NULL or one non-missing number")
    }
    value <- S7::new_object(
      S7::S7_object(),
      reason = reason,
      field = ending_optional_text(field, "field"),
      actual = actual,
      limit = limit
    )
    freeze_value(value)
  }
)

#' @rdname RunEnding
#' @export
RunEndingCutOff <- S7::new_class(
  "RunEndingCutOff",
  parent = RunEnding,
  package = "deputy",
  properties = list(
    finish_reason = readonly_property("finish_reason", S7::class_character)
  ),
  constructor = function(finish_reason) {
    finish_reason <- match.arg(finish_reason, run_ending_cut_off_reasons)
    value <- S7::new_object(
      S7::S7_object(),
      finish_reason = finish_reason
    )
    freeze_value(value)
  }
)

#' @rdname RunEnding
#' @export
RunEndingFailed <- S7::new_class(
  "RunEndingFailed",
  parent = RunEnding,
  package = "deputy",
  properties = list(
    reason = readonly_property("reason", S7::class_character),
    error = readonly_property("error", S7::class_any),
    phase = readonly_property(
      "phase",
      S7::new_union(S7::class_character, NULL)
    )
  ),
  constructor = function(reason = "error", error = NULL, phase = NULL) {
    if (!is_nonempty_string(reason)) {
      cli_abort("{.arg reason} must be one non-empty string")
    }
    if (!is.null(error) && !inherits(error, "condition")) {
      cli_abort("{.arg error} must be NULL or a condition")
    }
    value <- S7::new_object(
      S7::S7_object(),
      reason = reason,
      error = error,
      phase = ending_optional_text(phase, "phase")
    )
    freeze_value(value)
  }
)

local({
  S7::method(`$`, RunEnding) <- function(x, name) S7::props(x)[[name]]
})

S7::method(print, RunEnding) <- function(x, ...) {
  values <- S7::props(x)
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<{S7::S7_class(x)@name}>")
    cli::cli_div(theme = list(div = list("margin-left" = 2)))
    for (name in names(values)) {
      value <- values[[name]]
      if (is.null(value)) {
        next
      }
      if (inherits(value, "condition")) {
        value <- conditionMessage(value)
      }
      cli::cli_text("{name}: {value}")
    }
  }))
  invisible(x)
}

# Maps a run's stop reason, and the facts behind it, to its ending. Every
# stop reason deputy sets lands on exactly one class here.
run_ending_for <- function(
  reason,
  by = NULL,
  limit_status = NULL,
  finish_reason = NULL,
  error = NULL,
  phase = NULL
) {
  if (identical(reason, "complete")) {
    finish_reason <- as.character(finish_reason)
    if (
      length(finish_reason) == 1L &&
        !is.na(finish_reason) &&
        finish_reason %in% run_ending_cut_off_reasons
    ) {
      return(RunEndingCutOff(finish_reason))
    }
    return(RunEndingAnswered())
  }
  if (is.null(by) && reason %in% run_ending_limit_reasons) {
    same <- identical(limit_status$reason, reason)
    return(RunEndingLimit(
      reason,
      field = if (same) limit_status$field,
      actual = if (same) limit_status$actual,
      limit = if (same) limit_status$limit
    ))
  }
  if (is.null(by) && reason %in% run_ending_failure_reasons) {
    return(RunEndingFailed(reason, error = error, phase = phase))
  }
  known <- unname(run_ending_stop_reasons[reason])
  by <- if (!is.na(known)) known else by %||% "caller"
  RunEndingStopped(by, reason = reason)
}
