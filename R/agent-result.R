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
#' * `"tool_start"` - Tool execution starting. Contains: `tool_name`, `tool_input`
#' * `"tool_end"` - Tool execution completed. Contains: `tool_name`, `tool_result`, `tool_error`
#' * `"text"` - Text chunk from LLM. Contains: `text`, `is_complete`
#' * `"text_complete"` - Full text response. Contains: `text`
#' * `"turn"` - Turn completed. Contains: `turn`, `turn_number`
#' * `"warning"` - Warning condition occurred. Contains: `message`, `details`
#' * `"stop"` - Agent stopped. Contains: `reason`, `total_turns`, `cost`
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
    if (is.character(value) && nchar(value) > 50) {
      value <- truncate_string(value, 50)
    }
    cat("  ", field, ": ", as.character(value), "\n", sep = "")
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
    #' @return A new `AgentResult` object
    initialize = function(
      response = NULL,
      turns = list(),
      cost = list(input = 0, output = 0, cached = 0, total = 0),
      events = list(),
      duration = NULL,
      stop_reason = "complete",
      structured_output = NULL
    ) {
      self$response <- response
      self$turns <- turns
      self$cost <- cost
      self$events <- events
      self$duration <- duration
      self$stop_reason <- stop_reason
      self$structured_output <- structured_output
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
      if (!is.null(self$structured_output)) {
        status <- "unknown"
        if (isTRUE(self$structured_output$valid)) {
          status <- "valid"
        } else if (identical(self$structured_output$valid, FALSE)) {
          status <- "invalid"
        }
        cat("  structured_output:", status, "\n")
      }

      invisible(self)
    }
  )
)
