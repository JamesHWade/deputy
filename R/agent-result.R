# Agent result and event types for deputy

#' Create an agent event
#'
#' @description
#' Agent events are yielded by the `run()` generator to provide streaming
#' updates on agent progress.
#'
#' @param type Event type (see Event Types section)
#' @param ... Additional event data
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
AgentEvent <- function(type, ...) {
  data <- list(...)
  structure(
    c(
      list(
        type = type,
        timestamp = Sys.time()
      ),
      data
    ),
    class = c(
      paste0("AgentEvent", tools::toTitleCase(type)),
      "AgentEvent",
      "list"
    )
  )
}

#' @export
print.AgentEvent <- function(x, ...) {
  cat("<AgentEvent:", x$type, ">\n")
  cat("  timestamp:", format(x$timestamp, "%Y-%m-%d %H:%M:%S"), "\n")

  # Print type-specific fields
  fields <- setdiff(names(x), c("type", "timestamp"))
  for (field in fields) {
    value <- x[[field]]
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
    } else if (is.list(value)) {
      value <- paste0("<", class(value)[[1L]] %||% "list", ">")
    } else {
      value <- paste(as.character(value), collapse = ", ")
    }
    if (is.character(value) && length(value) == 1L && nchar(value) > 80) {
      value <- truncate_string(value, 80)
    }
    cat("  ", field, ": ", value, "\n", sep = "")
  }
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

    #' @field cost Cost information (list with input, output, cached, total)
    cost = NULL,

    #' @field events List of all AgentEvent objects from execution
    events = NULL,

    #' @field duration Execution duration in seconds
    duration = NULL,

    #' @field stop_reason Reason the agent stopped
    stop_reason = NULL,

    #' @field structured_output Parsed/validated structured output (if requested)
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
    #' @param cost Cost information
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
      cost = list(input = 0, output = 0, cached = 0, total = 0),
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
      cat("<AgentResult>\n")
      cat("  status:", self$stop_reason, "\n")
      cat("  turns:", self$n_turns(), "\n")
      cat("  tool_calls:", length(self$tool_calls()), "\n")

      if (!is.null(self$duration)) {
        cat("  duration:", round(self$duration, 2), "seconds\n")
      }

      if (!is.null(self$cost) && !is.null(self$cost$total)) {
        cat("  cost:", format_cost(self$cost$total), "\n")
      }

      if (!is.null(self$response)) {
        cat("  response:", truncate_string(self$response, 60), "\n")
      }
      if (!is.null(self$session_id)) {
        cat("  session_id:", self$session_id, "\n")
      }
      if (!is.null(self$run_id)) {
        cat("  run_id:", self$run_id, "\n")
      }
      if (!is.null(self$agent_id)) {
        cat("  agent_id:", self$agent_id, "\n")
      }
      if (!is.null(self$delegation_id)) {
        cat("  delegation_id:", self$delegation_id, "\n")
      }
      if (!is.null(self$usage)) {
        cat("  requests:", self$usage$requests, "\n")
        cat("  tokens:", self$usage$total_tokens, "\n")
      }
      if (!is.null(self$structured_output)) {
        status <- "unknown"
        if (isTRUE(self$structured_output$valid)) {
          status <- "valid"
        } else if (identical(self$structured_output$valid, FALSE)) {
          status <- "invalid"
        }
        if (isTRUE(self$structured_output$schema_validation_skipped)) {
          cat("  structured_output:", status, "(validation skipped)\n")
        } else {
          cat("  structured_output:", status, "\n")
        }
      }

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
