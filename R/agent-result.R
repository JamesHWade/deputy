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

#' Agent Result R6 Class
#'
#' @description
#' Contains the result of an agent task execution, including the final response,
#' conversation history, cost information, and all events that occurred during
#' execution.
#'
#' @export
AgentResult <- R6::R6Class(
  "AgentResult",

  public = list(
    #' @field response The final text response from the agent
    response = NULL,

    #' @field turns List of conversation turns
    turns = NULL,

    #' @field cost Cost information with input, output, cached, total,
    #'   complete, and missing fields. An incomplete total is `NA_real_`.
    cost = NULL,

    #' @field events List of all AgentEvent objects from execution
    events = NULL,

    #' @field duration Execution duration in seconds
    duration = NULL,

    #' @field stop_reason Reason the agent stopped
    stop_reason = NULL,

    #' @field structured_output Data converted by ellmer using the requested type (if any)
    structured_output = NULL,

    #' @field session_id Stable session identifier for run correlation
    session_id = NULL,

    #' @field run_id Unique identifier shared by events from this run
    run_id = NULL,

    #' @field agent_id Immutable identifier for the Agent instance
    agent_id = NULL,

    #' @field agent_name Optional human-readable Agent name
    agent_name = NULL,

    #' @field parent_agent_id Parent Agent identifier for delegated runs
    parent_agent_id = NULL,

    #' @field parent_run_id Parent run identifier for delegated runs
    parent_run_id = NULL,

    #' @field delegation_id Delegation identifier for delegated runs
    delegation_id = NULL,

    #' @field usage Run-scoped [AgentUsage]
    usage = NULL,

    #' @description
    #' Create a new AgentResult object.
    #'
    #' @param response Final text response
    #' @param turns List of conversation turns
    #' @param cost Cost information, including provider coverage metadata
    #' @param events List of AgentEvent objects
    #' @param duration Execution duration in seconds
    #' @param stop_reason Reason for stopping
    #' @param structured_output Parsed structured output (if any)
    #' @param session_id Stable session identifier (if any)
    #' @param run_id Unique run identifier (if any)
    #' @param usage Run-scoped [AgentUsage]
    #' @param agent_id Agent instance identifier (if any)
    #' @param agent_name Optional human-readable Agent name
    #' @param parent_agent_id Parent Agent identifier for delegated runs
    #' @param parent_run_id Parent run identifier for delegated runs
    #' @param delegation_id Delegation identifier for delegated runs
    #' @param run_context Immutable product context for this run
    #' @return A new `AgentResult` object
    initialize = function(
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
      self$response <- response
      self$turns <- turns
      self$cost <- cost
      self$events <- events
      self$duration <- duration
      self$stop_reason <- stop_reason
      self$structured_output <- structured_output
      self$session_id <- session_id
      self$run_id <- run_id
      self$agent_id <- agent_id
      self$agent_name <- agent_name
      self$parent_agent_id <- parent_agent_id
      self$parent_run_id <- parent_run_id
      self$delegation_id <- delegation_id
      private$.run_context <- normalize_run_context(run_context)
      self$usage <- usage
    },

    #' @description
    #' Get the number of turns in the conversation.
    #' @return Integer count of turns
    n_turns = function() {
      length(self$turns)
    },

    #' @description
    #' Get all tool calls made during execution.
    #' @return List of tool_start events
    tool_calls = function() {
      Filter(function(e) e$type == "tool_start", self$events)
    },

    #' @description
    #' Get all completed tool events from execution.
    #' @return List of `tool_end` events
    tool_results = function() {
      Filter(function(e) e$type == "tool_end", self$events)
    },

    #' @description
    #' Get all text chunks from the response.
    #' @return Character vector of text chunks
    text_chunks = function() {
      text_events <- Filter(function(e) e$type == "text", self$events)
      sapply(text_events, function(e) e$text)
    },

    #' @description
    #' Check if the agent completed successfully.
    #' @return Logical indicating success
    is_success = function() {
      self$stop_reason == "complete"
    },

    #' @description
    #' Print the result summary.
    print = function() {
      cli::cat_line(cli::cli_format_method({
        cli::cli_text("<AgentResult>")
        cli::cli_div(theme = list(div = list("margin-left" = 2)))
        cli::cli_text("status: {self$stop_reason}")
        cli::cli_text("turns: {self$n_turns()}")
        cli::cli_text("tool_calls: {length(self$tool_calls())}")

        if (!is.null(self$duration)) {
          cli::cli_text("duration: {round(self$duration, 2)} seconds")
        }

        if (!is.null(self$cost) && !is.null(self$cost$total)) {
          cli::cli_text("cost: {format_cost(self$cost$total)}")
        }

        if (!is.null(self$response)) {
          cli::cli_text("response: {truncate_string(self$response, 60)}")
        }
        if (!is.null(self$session_id)) {
          cli::cli_text("session_id: {self$session_id}")
        }
        if (!is.null(self$run_id)) {
          cli::cli_text("run_id: {self$run_id}")
        }
        if (!is.null(self$agent_id)) {
          cli::cli_text("agent_id: {self$agent_id}")
        }
        if (!is.null(self$delegation_id)) {
          cli::cli_text("delegation_id: {self$delegation_id}")
        }
        if (!is.null(self$usage)) {
          cli::cli_text("requests: {self$usage$requests}")
          cli::cli_text("tokens: {self$usage$total_tokens}")
        }
        if (!is.null(self$structured_output)) {
          cli::cli_text(
            "  structured_output: <{class(self$structured_output)[[1L]]}>"
          )
        }
      }))
      invisible(self)
    }
  ),

  active = list(
    #' @field run_context Canonical product context for the run. Read-only.
    run_context = function(value) {
      if (missing(value)) {
        return(clone_run_context(private$.run_context))
      }
      cli_abort("Cannot modify AgentResult: run_context is immutable")
    }
  ),

  private = list(
    .run_context = list()
  )
)
