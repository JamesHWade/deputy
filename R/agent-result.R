#' @include value-properties.R run-usage.R
NULL

# Agent result and event types for deputy

#' Create an agent event
#'
#' @description
#' [Agent]`$run()` yields these events as the agent works, and an
#' [AgentResult] keeps them in `events`. Each event has a `type`, a
#' `timestamp` and a named list of `data`. Check `event$type` to tell events
#' apart, and read data fields directly with `$`, for example `event$text`. A
#' field that isn't there returns `NULL`. Events are read-only.
#'
#' @param type Event type (see the "Event types" section).
#' @param ... Named event data. Names must be unique and can't be `type`,
#'   `timestamp` or `data`.
#' @prop timestamp When the event was created, as a `POSIXct` value.
#' @prop data Named list of event data.
#' @return An `AgentEvent` object.
#'
#' @section Event types:
#' * `"start"`: the run started. `task`.
#' * `"request_start"`, `"request_end"`, `"request_error"`: a model request
#'   started, finished or failed, with the provider, model and request
#'   number. `"request_error"` carries the original `condition`. ellmer's HTTP
#'   retries are not separate requests.
#' * `"text"`: a streamed chunk of the reply. `text`, `is_complete`.
#' * `"text_complete"`: the full reply. `text`.
#' * `"content"`: other content from the provider. `content`, `content_type`.
#' * `"tool_start"`: a tool call is about to run. `tool_call_id`,
#'   `tool_name`, `tool_input`.
#' * `"tool_end"`: a tool call finished. `tool_call_id`, `tool_name`,
#'   `tool_result`, `tool_error`.
#' * `"turn"`: a turn finished. `turn`, `turn_number`.
#' * `"permission"`, `"hook"`: a permission decision or hook result.
#' * `"approval"`: a tool call is waiting for approval. `approval_id`, `path`,
#'   `tool_name`, `tool_input`, `reason`.
#' * `"trusted_result"`: a trusted tool returned a value (see
#'   [TrustedResults]). `result_id`, `result_type`, `tool_name`, `value`.
#' * `"compaction_start"`, `"compaction"`, `"compaction_error"`: automatic
#'   compaction started, finished or failed.
#' * `"fallback"`: a fallback Chat took over after a transient error.
#'   `fallback_index`, `condition`, `usage`.
#' * `"structured_attempt"`: one attempt at structured output, with the
#'   `value`, whether it was `valid` and any `feedback`. It may hold sensitive
#'   data.
#' * `"file_checkpoint"`: a file checkpoint was created at the start of the
#'   run. `checkpoint_id`, `name`.
#' * `"run_error"`: the run failed. `phase` and the original `condition`.
#' * `"usage"`: the run's usage. `usage`, `limits`.
#' * `"stop"`: the run ended. `reason`, `cost`, `usage`, and `limit` (details
#'   of the usage limit that stopped the run, or `NULL`).
#'
#' Events also carry the `run_id`. All but `"text"`, `"text_complete"` and
#' `"content"` carry `agent_id`, `session_id` and `run_context` too, plus
#' parent and delegation IDs in subagent runs.
#'
#' @examples
#' # Create a start event
#' AgentEvent("start", task = "Analyze data.csv")
#'
#' # Create a text event
#' event <- AgentEvent("text", text = "Hello", is_complete = FALSE)
#' event$text
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
      if (S7::S7_inherits(value, AgentUsage)) {
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
      } else if (S7::S7_inherits(value, UsageLimits)) {
        configured <- Filter(
          Negate(is.null),
          S7::props(value)[setdiff(names(S7::props(value)), "on_exceed")]
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

#' Create an agent run result
#'
#' @description
#' An `AgentResult` describes one finished run. [Agent]`$run_sync()`,
#' `$run_async()` and `$last_run()` return one; you rarely need to create it
#' yourself. It holds the final response, the conversation turns, every
#' [AgentEvent], usage and cost, and IDs that link the run to its agent and
#' session.
#'
#' Results are read-only. Read fields with `$`, for example
#' `result$response`, or use [result_n_turns()], [result_tool_calls()],
#' [result_tool_results()], [result_text_chunks()] and [result_is_success()].
#'
#' `usage` covers this run only, but `cost` covers every turn in the model
#' context, including earlier runs.
#'
#' @param response Final text response, or `NULL`.
#' @param turns List of ellmer turns in the model context when the run ended.
#' @param cost Cost summary (as from [Agent]`$cost()`), or `NULL`. `total` is
#'   `NA` if some responses had no cost.
#' @param events List of [AgentEvent] objects.
#' @param duration Run time in seconds, or `NULL`.
#' @param stop_reason Why the run stopped: `"complete"` if the model finished,
#'   otherwise a reason such as `"request_limit"`, `"interrupted"` or
#'   `"error"`.
#' @param structured_output Extracted structured data, if any.
#' @param session_id,run_id,agent_id,agent_name,parent_agent_id,parent_run_id,delegation_id
#'   Optional ID strings linking the run to its session and agent and, for a
#'   subagent, to the parent run and delegation.
#' @param usage [AgentUsage] for this run only, or `NULL`.
#' @param run_context The run's `run_context`, a named list.
#' @return An `AgentResult` object.
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
      S7::new_union(NULL, AgentUsage)
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

#' Count the turns in a result
#'
#' @param result An [AgentResult].
#' @return The number of turns in `result$turns`.
#' @export
result_n_turns <- S7::new_generic("result_n_turns", "result", function(result) {
  S7::S7_dispatch()
})

S7::method(result_n_turns, AgentResult) <- function(result) {
  length(result@turns)
}

#' Get the tool calls from a result
#'
#' @param result An [AgentResult].
#' @return A list of `"tool_start"` events.
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

#' Get the finished tool calls from a result
#'
#' @param result An [AgentResult].
#' @return A list of `"tool_end"` events.
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

#' Get the streamed text chunks from a result
#'
#' @param result An [AgentResult].
#' @return A character vector of text chunks in order, or `character()` if
#'   there were none.
#' @export
result_text_chunks <- S7::new_generic(
  "result_text_chunks",
  "result",
  function(result) {
    S7::S7_dispatch()
  }
)

S7::method(result_text_chunks, AgentResult) <- function(result) {
  text_events <- Filter(
    function(e) e$type == "text" && is.character(e$text),
    result@events
  )
  unlist(lapply(text_events, function(e) e$text), use.names = FALSE) %||%
    character()
}

#' Check whether a run completed
#'
#' @param result An [AgentResult].
#' @return `TRUE` if the stop reason is `"complete"`, meaning the model
#'   finished on its own. It doesn't check the answer.
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
