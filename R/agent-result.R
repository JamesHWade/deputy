#' @include value-properties.R
NULL

# Agent result and event types for deputy

#' Create an agent event
#'
#' @description
#' Agent events are yielded by the `run()` generator to provide streaming
#' updates on agent progress. Events are S7 values with read-only `type`,
#' `timestamp`, and `data` properties. Use `S7::prop(event, "data")` to obtain
#' the named payload; `event$text` and other `$` reads are conveniences for
#' looking up payload fields. Missing fields return `NULL`.
#'
#' Select an event with its `type` property, not an S3 subtype class. Read-only
#' properties protect the record, but environments, provider objects, and
#' conditions inside the payload retain their own reference semantics.
#'
#' @param type Event type (see Event Types section)
#' @param ... Named event data with unique names. The envelope names `type`,
#'   `timestamp`, and `data` are reserved.
#' @prop timestamp Construction time as a `POSIXct` value. Read-only.
#' @prop data Named list of event-specific data. Read-only.
#' @return An `AgentEvent` object
#'
#' @section Event Types:
#' * `"start"` - Task started. Contains: `task`
#' * `"tool_start"` - Tool execution starting. Contains: `tool_call_id`,
#'   `tool_name`, and `tool_input`
#' * `"tool_end"` - Tool execution completed. Contains: `tool_call_id`,
#'   `tool_name`, `tool_result`, and `tool_error`
#' * `"text"` - Text chunk from LLM. Contains: `text`, `is_complete`
#' * `"text_complete"` - Full text response. Contains: `text`
#' * `"turn"` - Turn completed. Contains: `turn`, `turn_number`
#' * `"warning"` - Warning condition occurred. Contains: `message`, `details`
#' * `"content"` - Non-text provider content. Contains: `content`,
#'   `content_type`
#' * `"request_start"`, `"request_end"`, `"request_error"` - Governed model
#'   dispatch evidence with provider, model, request number, and original
#'   HTTP/transport conditions on errors. These are not individual HTTP retry
#'   attempts. Unclassified application errors are retained as `"run_error"`.
#' * `"run_error"` - Terminal initialization, streaming, or structured-output
#'   failure, with its phase and original condition. Application callbacks and
#'   validation do not turn a successful response into a `"request_error"`.
#' * `"fallback"` - Explicit Chat selection, prior condition, and usage.
#' * `"structured_attempt"` - Structured value, available turn, validation
#'   outcome, feedback, and condition. May contain sensitive application data.
#' * `"permission"`, `"hook"`, `"compaction"` - Governance decisions and lifecycle.
#' * `"file_checkpoint"` - Automatic run-boundary checkpoint. Contains:
#'   `checkpoint_id`, `name`
#' * `"usage"` - Run usage snapshot. Contains: `usage`, `limits`
#' * `"stop"` - Agent stopped. Contains: `reason`, `total_turns`, `cost`,
#'   `usage`, and `run_id`
#'
#' Run-boundary and tool lifecycle events also carry `agent_id`, `run_id`,
#' immutable `run_context`, and delegated-run correlation fields when
#' applicable.
#'
#' @examples
#' # Create a start event
#' AgentEvent("start", task = "Analyze data.csv")
#'
#' # Create a text event
#' AgentEvent("text", text = "Hello", is_complete = FALSE
#' )
#'
#' @export
AgentEvent <- S7::new_class(
  "AgentEvent",
  package = "deputy",
  properties = list(
    type = readonly_property("type", S7::class_character),
    timestamp = readonly_property("timestamp", S7::new_S3_class("POSIXct")),
    data = readonly_property("data", S7::class_list)
  ),
  constructor = function(type, ...) {
    if (!is_nonempty_string(type)) {
      cli_abort("{.arg type} must be one non-empty string")
    }
    data <- list(...)
    fields <- names(data)
    if (
      length(data) > 0L &&
        (is.null(fields) ||
          anyNA(fields) ||
          !all(nzchar(fields)) ||
          anyDuplicated(fields) > 0L)
    ) {
      cli_abort("Event data must have unique, non-empty names")
    }
    if (any(fields %in% c("type", "timestamp", "data"))) {
      cli_abort(
        "Event data cannot replace {.arg type}, {.arg timestamp}, or {.arg data}"
      )
    }
    value <- S7::new_object(
      S7::S7_object(),
      type = type,
      timestamp = Sys.time(),
      data = data
    )
    freeze_value(value)
  }
)

# Read convenience for streaming consumers. Assignment uses S7 properties and
# remains read-only; this does not restore the old list or subtype classes.
# Scope replacement registration so it does not bind `$` in Deputy's
# namespace, which makes codetools treat every field name as a variable.
local({
  S7::method(`$`, AgentEvent) <- function(x, name) {
    if (name %in% c("type", "timestamp", "data")) {
      return(S7::prop(x, name))
    }
    x@data[[name]]
  }
})

S7::method(print, AgentEvent) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<AgentEvent: {x$type} >")
    cli::cli_div(theme = list(div = list("margin-left" = 2)))
    cli::cli_text("timestamp: {format(x$timestamp, \"%Y-%m-%d %H:%M:%S\")}")

    # Print type-specific fields
    fields <- names(x@data)
    for (field in fields) {
      value <- x@data[[field]]
      if (inherits(value, "AgentUsage")) {
        value <- paste0(
          "requests=",
          value$requests,
          ", tool_calls=",
          value$tool_calls,
          ", tokens=",
          value$total_tokens,
          ", cost_usd=",
          format_cost(value$cost_usd)
        )
      } else if (inherits(value, "UsageLimits")) {
        configured <- Filter(
          Negate(is.null),
          value[setdiff(names(value), "on_exceed")]
        )
        value <- paste0(
          paste(
            paste0(names(configured), "=", unlist(configured)),
            collapse = ", "
          ),
          if (length(configured) > 0L) ", " else "",
          "on_exceed=",
          value$on_exceed
        )
      } else if (!is.atomic(value)) {
        value <- paste0("<", class(value)[[1L]] %||% "list", ">")
      } else {
        value <- paste(as.character(value), collapse = ", ")
      }
      if (is.character(value) && length(value) == 1L && nchar(value) > 80) {
        value <- truncate_string(value, 80)
      }
      cli::cli_text("{field}: {value}")
    }
  }))
  invisible(x)
}

#' Create a completed agent result
#'
#' @description
#' A read-only S7 snapshot of a governed run. It contains original ellmer turns,
#' Deputy events, usage, and correlation metadata. Read properties with
#' `S7::prop(result, "response")` or `$`; use [result_n_turns()],
#' [result_tool_calls()], [result_tool_results()], [result_text_chunks()], and
#' [result_is_success()] for inspection.
#'
#' All properties are read-only, including previously writable R6 fields.
#' Ordinary nested lists use R value semantics. Embedded provider objects,
#' conditions, environments, and closures retain their own reference semantics;
#' the result does not deep-copy or sanitize their contents. Run context is
#' separately normalized to canonical JSON-compatible values.
#'
#' @param response Final text response, or `NULL`.
#' @param turns List of original conversation turns.
#' @param cost Cost information, including provider coverage metadata, or
#'   `NULL`. An incomplete total is `NA_real_`.
#' @param events List of [AgentEvent] objects.
#' @param duration Finite, nonnegative duration in seconds, or `NULL`.
#' @param stop_reason One nonempty stop-reason string.
#' @param structured_output Parsed structured output, if any.
#' @param session_id,run_id,agent_id,agent_name,parent_agent_id,parent_run_id,delegation_id
#'   Optional nonempty correlation and identity strings.
#' @param usage Run-scoped [AgentUsage], or `NULL`.
#' @param run_context Canonical product context for the run.
#' @return An `AgentResult` S7 object.
#' @examples
#' result <- AgentResult(response = "Done", events = list(
#'   AgentEvent("text", text = "Done")
#' ))
#' result_is_success(result)
#' result_text_chunks(result)
#' @export
AgentResult <- S7::new_class(
  "AgentResult",
  package = "deputy",
  properties = list(
    response = readonly_property(
      "response",
      S7::new_union(NULL, S7::class_character)
    ),
    turns = readonly_property("turns", S7::class_list),
    cost = readonly_property(
      "cost",
      S7::new_union(NULL, S7::class_list)
    ),
    events = readonly_property("events", S7::class_list),
    duration = readonly_property(
      "duration",
      S7::new_union(NULL, S7::class_numeric)
    ),
    stop_reason = readonly_property("stop_reason", S7::class_character),
    structured_output = readonly_property("structured_output", S7::class_any),
    session_id = readonly_property(
      "session_id",
      S7::new_union(NULL, S7::class_character)
    ),
    run_id = readonly_property(
      "run_id",
      S7::new_union(NULL, S7::class_character)
    ),
    usage = readonly_property(
      "usage",
      S7::new_union(NULL, S7::new_S3_class("AgentUsage"))
    ),
    agent_id = readonly_property(
      "agent_id",
      S7::new_union(NULL, S7::class_character)
    ),
    agent_name = readonly_property(
      "agent_name",
      S7::new_union(NULL, S7::class_character)
    ),
    parent_agent_id = readonly_property(
      "parent_agent_id",
      S7::new_union(NULL, S7::class_character)
    ),
    parent_run_id = readonly_property(
      "parent_run_id",
      S7::new_union(NULL, S7::class_character)
    ),
    delegation_id = readonly_property(
      "delegation_id",
      S7::new_union(NULL, S7::class_character)
    ),
    run_context = readonly_property("run_context", S7::class_list)
  ),
  constructor = function(
    response = NULL,
    turns = list(),
    cost = list(
      input = 0,
      output = 0,
      cached = 0,
      total = 0,
      complete = TRUE,
      missing = 0L
    ),
    events = list(),
    duration = NULL,
    stop_reason = "complete",
    structured_output = NULL,
    session_id = NULL,
    run_id = NULL,
    usage = AgentUsage(),
    agent_id = NULL,
    agent_name = NULL,
    parent_agent_id = NULL,
    parent_run_id = NULL,
    delegation_id = NULL,
    run_context = list()
  ) {
    ids <- list(
      session_id = session_id,
      run_id = run_id,
      agent_id = agent_id,
      agent_name = agent_name,
      parent_agent_id = parent_agent_id,
      parent_run_id = parent_run_id,
      delegation_id = delegation_id
    )
    for (name in names(ids)) {
      if (!is.null(ids[[name]]) && !is_nonempty_string(ids[[name]])) {
        cli_abort("{.arg {name}} must be NULL or one non-empty string")
      }
    }
    if (!is_nonempty_string(stop_reason)) {
      cli_abort("{.arg stop_reason} must be one non-empty string")
    }
    if (
      !is.null(response) &&
        (!is.character(response) || length(response) != 1L || is.na(response))
    ) {
      cli_abort("{.arg response} must be NULL or one non-missing string")
    }
    if (
      !is.null(duration) &&
        (!is.numeric(duration) ||
          length(duration) != 1L ||
          !is.finite(duration) ||
          duration < 0)
    ) {
      cli_abort("{.arg duration} must be NULL or one finite nonnegative number")
    }
    if (
      !is.list(events) ||
        !all(vapply(events, S7::S7_inherits, logical(1), class = AgentEvent))
    ) {
      cli_abort("{.arg events} must be a list of AgentEvent objects")
    }
    run_context <- normalize_run_context(run_context)
    value <- S7::new_object(
      S7::S7_object(),
      response = response,
      turns = turns,
      cost = cost,
      events = events,
      duration = duration,
      stop_reason = stop_reason,
      structured_output = structured_output,
      session_id = session_id,
      run_id = run_id,
      usage = usage,
      agent_id = agent_id,
      agent_name = agent_name,
      parent_agent_id = parent_agent_id,
      parent_run_id = parent_run_id,
      delegation_id = delegation_id,
      run_context = run_context
    )
    freeze_value(value)
  }
)

local({
  S7::method(`$`, AgentResult) <- function(x, name) S7::prop(x, name)
})

#' Count conversation turns
#'
#' @param result An [AgentResult] S7 value.
#' @return Integer count of turns.
#' @export
result_n_turns <- S7::new_generic("result_n_turns", "result", function(result) {
  S7::S7_dispatch()
})

S7::method(result_n_turns, AgentResult) <- function(result) {
  length(result@turns)
}

#' Inspect tool calls
#'
#' @param result An [AgentResult] S7 value.
#' @return List of `tool_start` events.
#' @export
result_tool_calls <- S7::new_generic(
  "result_tool_calls",
  "result",
  function(result) {
    S7::S7_dispatch()
  }
)

S7::method(result_tool_calls, AgentResult) <- function(result) {
  Filter(function(e) e$type == "tool_start", result@events)
}

#' Inspect completed tool calls
#'
#' @param result An [AgentResult] S7 value.
#' @return List of `tool_end` events.
#' @export
result_tool_results <- S7::new_generic(
  "result_tool_results",
  "result",
  function(result) {
    S7::S7_dispatch()
  }
)

S7::method(result_tool_results, AgentResult) <- function(result) {
  Filter(function(e) e$type == "tool_end", result@events)
}

#' Inspect streamed text
#'
#' @param result An [AgentResult] S7 value.
#' @return Character vector of text chunks; empty when none were emitted.
#' @export
result_text_chunks <- S7::new_generic(
  "result_text_chunks",
  "result",
  function(result) {
    S7::S7_dispatch()
  }
)

S7::method(result_text_chunks, AgentResult) <- function(result) {
  text_events <- Filter(function(e) e$type == "text", result@events)
  vapply(text_events, function(e) e$text, character(1))
}

#' Inspect run success
#'
#' @param result An [AgentResult] S7 value.
#' @return Whether the stop reason is `"complete"`.
#' @export
result_is_success <- S7::new_generic(
  "result_is_success",
  "result",
  function(result) {
    S7::S7_dispatch()
  }
)

S7::method(result_is_success, AgentResult) <- function(result) {
  result@stop_reason == "complete"
}

S7::method(print, AgentResult) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<AgentResult>")
    cli::cli_div(theme = list(div = list("margin-left" = 2)))
    cli::cli_text("status: {x@stop_reason}")
    cli::cli_text("turns: {result_n_turns(x)}")
    cli::cli_text("tool_calls: {length(result_tool_calls(x))}")

    if (!is.null(x@duration)) {
      cli::cli_text("duration: {round(x@duration, 2)} seconds")
    }

    if (!is.null(x@cost) && !is.null(x@cost$total)) {
      cli::cli_text("cost: {format_cost(x@cost$total)}")
    }

    if (!is.null(x@response)) {
      cli::cli_text("response: {truncate_string(x@response, 60)}")
    }
    if (!is.null(x@session_id)) {
      cli::cli_text("session_id: {x@session_id}")
    }
    if (!is.null(x@run_id)) {
      cli::cli_text("run_id: {x@run_id}")
    }
    if (!is.null(x@agent_id)) {
      cli::cli_text("agent_id: {x@agent_id}")
    }
    if (!is.null(x@delegation_id)) {
      cli::cli_text("delegation_id: {x@delegation_id}")
    }
    if (!is.null(x@usage)) {
      cli::cli_text("requests: {x@usage$requests}")
      cli::cli_text("tokens: {x@usage$total_tokens}")
    }
    if (!is.null(x@structured_output)) {
      cli::cli_text(
        "  structured_output: <{class(x@structured_output)[[1L]]}>"
      )
    }
  }))
  invisible(x)
}
