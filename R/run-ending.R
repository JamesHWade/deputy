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
#' An [AgentResult] carries a `RunEnding` in its `ending` property. It says
#' how the run ended and holds only what that ending has, so you can act on an
#' ending without reading the `stop_reason` string:
#'
#' * `RunEndingAnswered`: the model finished its answer.
#' * `RunEndingStopped`: someone or something stopped the run. `by` says who,
#'   and `reason` is the reason they gave.
#' * `RunEndingLimit`: the run reached a limit. `reason` names it, and `field`,
#'   `actual` and `limit` give the [UsageLimits] field, the figure reached and
#'   the figure allowed, when the limit has them.
#' * `RunEndingCutOff`: the provider cut the answer short. `finish_reason` says
#'   why. The result's `stop_reason` is still `"complete"`, since the run was
#'   not stopped.
#' * `RunEndingFailed`: an error ended the run. `error` is the condition, when
#'   there is one, and `phase` says where it came from.
#'
#' `RunEnding` is the parent class; use it to test for any ending with
#' `S7::S7_inherits(x, RunEnding)`. Agents create these values. You only need
#' the constructors to build an [AgentResult] yourself, for example in a test.
#'
#' Endings are read-only. Read a property with `$` (a missing one gives
#' `NULL`), `@` or [S7::prop()].
#'
#' @section Which ending a stop reason gives:
#'
#' * `"complete"`: answered, or cut off when the last response's finish reason
#'   is `"max_tokens"`, `"context_window"` or `"content_filter"`.
#' * `"request_limit"`, `"tool_call_limit"`, `"input_token_limit"`,
#'   `"output_token_limit"`, `"total_token_limit"`, `"cost_limit"`,
#'   `"cost_unavailable"`, `"tool_loop"`: a limit.
#' * `"error"`, `"provider_error"`, `"file_checkpoint_error"` and the reasons
#'   a failed delegation or batch gives: failed.
#' * Anything else: stopped. `by` is `"caller"` for `$interrupt()`, `"hook"`
#'   for a hook that stopped the run, `"permission"` for a denied call that
#'   asked to stop it, `"approval"` for a run waiting for an approval,
#'   `"parent"` for a subagent whose lead finished, `"delegation"` for a batch
#'   whose subagents were stopped, and `"abandoned"` for a stream nobody read
#'   to its end. A reason you pass to `$interrupt()` or return from a hook is
#'   kept in `reason`, and whoever gave it is credited in `by`, whatever the
#'   reason says.
#'
#' @param by Who or what stopped the run: one of `"caller"`, `"hook"`,
#'   `"permission"`, `"approval"`, `"parent"`, `"delegation"` or
#'   `"abandoned"`.
#' @param reason For `RunEndingStopped()`, the reason the stopper gave, or
#'   `NULL`. For `RunEndingLimit()`, the limit's stop reason, such as
#'   `"request_limit"`. For `RunEndingFailed()`, the failure's stop reason,
#'   `"error"` by default.
#' @param field The [UsageLimits] field that was reached, such as
#'   `"max_requests"`, or `NULL`.
#' @param actual The figure the run reached, or `NULL`. `NA` when it is
#'   unknown, as the cost is for `"cost_unavailable"`.
#' @param limit The figure the limit allowed, or `NULL`.
#' @param finish_reason The provider's finish reason, as ellmer names it: one
#'   of `"max_tokens"`, `"context_window"` or `"content_filter"`.
#' @param error The condition that ended the run, or `NULL`.
#' @param phase Where the run failed, such as `"initialization"` or
#'   `"stream"`, or `NULL`.
#' @return A `RunEnding` object of the class named.
#' @seealso [AgentResult]
#' @examples
#' result <- AgentResult(response = "Done")
#' result$ending
#'
#' stopped <- AgentResult(stop_reason = "interrupted")
#' S7::S7_inherits(stopped$ending, RunEndingStopped)
#' stopped$ending$by
#'
#' RunEndingLimit("request_limit", field = "max_requests", actual = 5, limit = 5)
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
  # Who asked is recorded when the stop is requested, and that wins: a reason
  # is an open string, so a hook or a caller may give one of deputy's own
  # words. The word decides only when nobody was recorded. The exception is a
  # parent's end, which reaches its child as an interrupt with this reason.
  if (identical(reason, "parent_completed")) {
    by <- "parent"
  } else if (is.null(by)) {
    known <- unname(run_ending_stop_reasons[reason])
    by <- if (!is.na(known)) known else "caller"
  }
  RunEndingStopped(by, reason = reason)
}
