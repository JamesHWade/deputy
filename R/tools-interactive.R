# Interactive tools for human-in-the-loop workflows
#
# This implements AskUserQuestion following the Anthropic Agent SDK format:
# - questions: array of 1-4 questions
# - Each question has: question, header, options (2-4), multiSelect
# - Each option has: label, description
# - Returns: answers mapping question text to selected label(s)

# Package-level storage for the user input callback
.deputy_env <- new.env(parent = emptyenv())
.deputy_env$ask_user_callback <- NULL

#' Set callback for non-interactive user input
#'
#' @description
#' In non-interactive sessions (scripts, Shiny apps, etc.), set a callback
#' function that will be called when the agent needs user input via
#' `AskUserQuestion`.
#'
#' @param callback A function that takes `questions` (list matching the
#'   AskUserQuestion format). Each question has `question`, `header`,
#'   `options` (list with `label` and `description`), and `multiSelect`.
#'   Should return a named list mapping question text to selected label(s).
#'   For multi-select, join labels with ", ".
#'   Set to NULL to clear the callback.
#'
#' @return Invisibly returns the previous callback (or NULL).
#'
#' @examples
#' \dontrun{
#' # For a Shiny app:
#' set_ask_user_callback(function(questions) {
#'   # Display questions in modal and collect answers
#'   answers <- list()
#'   for (q in questions) {
#'     # Show q$question with q$options
#'     # Collect user selection
#'     answers[[q$question]] <- selected_label
#'   }
#'   answers
#' })
#' }
#'
#' @export
set_ask_user_callback <- function(callback) {
  if (!is.null(callback) && !is.function(callback)) {
    cli::cli_abort("{.arg callback} must be a function or NULL")
  }
  old <- .deputy_env$ask_user_callback
  .deputy_env$ask_user_callback <- callback
  invisible(old)
}

#' Get the current user input callback
#'
#' @return The current callback function, or NULL if none set.
#' @keywords internal
#' @export
get_ask_user_callback <- function() {
  .deputy_env$ask_user_callback
}

#' Parse user response as option number(s) or free text
#'
#' @param response User's input string
#' @param options List of option objects with label and description
#' @param multi_select Whether multiple selections are allowed
#' @return Selected label(s) or the free text response
#' @keywords internal
parse_user_response <- function(response, options, multi_select = FALSE) {
  response_trimmed <- trimws(response)

  if (multi_select) {
    # Try to parse as comma-separated numbers
    parts <- strsplit(response_trimmed, ",")[[1]]
    indices <- suppressWarnings(as.integer(trimws(parts)))

    if (!any(is.na(indices))) {
      # All parts are valid numbers
      valid_indices <- indices[indices >= 1 & indices <= length(options)]
      if (length(valid_indices) > 0) {
        labels <- vapply(valid_indices, function(i) options[[i]]$label, character(1))
        return(paste(labels, collapse = ", "))
      }
    }
  } else {
    # Try to parse as single number
    idx <- suppressWarnings(as.integer(response_trimmed))
    if (!is.na(idx) && idx >= 1 && idx <= length(options)) {
      return(options[[idx]]$label)
    }
  }

  # Return free text response
  response_trimmed
}

#' Ask user questions (internal implementation)
#'
#' @param questions List of question objects following the SDK format
#' @return Named list mapping question text to selected answers
#' @keywords internal
ask_user_impl <- function(questions) {
  # Check for custom callback first
  callback <- get_ask_user_callback()
  if (!is.null(callback)) {
    return(callback(questions))
  }

  # Check if we're in an interactive session
  if (!interactive()) {
    cli::cli_abort(c(
      "Cannot ask user: session is not interactive",
      "i" = "Use {.fn set_ask_user_callback} to provide a callback for non-interactive use"
    ))
  }

  answers <- list()

  for (q in questions) {
    cli::cli_h3("{q$header}: {q$question}")

    # Display options
    options <- q$options
    for (i in seq_along(options)) {
      opt <- options[[i]]
      cli::cli_text("  {i}. {opt$label} - {opt$description}")
    }

    # Show instructions
    if (isTRUE(q$multiSelect)) {
      cli::cli_text("  (Enter numbers separated by commas, or type your own answer)")
    } else {
      cli::cli_text("  (Enter a number, or type your own answer)")
    }

    # Get response
    repeat {
      response <- readline("> ")
      response_trimmed <- trimws(response)

      if (nchar(response_trimmed) > 0) {
        answer <- parse_user_response(response_trimmed, options, isTRUE(q$multiSelect))
        answers[[q$question]] <- answer
        break
      }
      cli::cli_alert_warning("Please enter a response")
    }
  }

  answers
}

#' Validate questions structure
#'
#' @param questions List of question objects
#' @return TRUE if valid, otherwise throws an error via tool_reject
#' @keywords internal
validate_questions <- function(questions) {
  # Validate questions array
  if (!is.list(questions) || length(questions) == 0) {
    ellmer::tool_reject("questions must be a non-empty array")
  }

  if (length(questions) > 4) {
    ellmer::tool_reject("Maximum 4 questions allowed per call")
  }

  # Validate each question
  for (i in seq_along(questions)) {
    q <- questions[[i]]

    if (is.null(q$question) || !is.character(q$question)) {
      ellmer::tool_reject(paste("Question", i, "missing 'question' field"))
    }

    if (is.null(q$header) || !is.character(q$header)) {
      ellmer::tool_reject(paste("Question", i, "missing 'header' field"))
    }

    if (nchar(q$header) > 12) {
      ellmer::tool_reject(paste("Question", i, "header exceeds 12 characters"))
    }

    if (is.null(q$options) || !is.list(q$options)) {
      ellmer::tool_reject(paste("Question", i, "missing 'options' array"))
    }

    if (length(q$options) < 2 || length(q$options) > 4) {
      ellmer::tool_reject(paste("Question", i, "must have 2-4 options"))
    }

    for (j in seq_along(q$options)) {
      opt <- q$options[[j]]
      if (is.null(opt$label) || is.null(opt$description)) {
        ellmer::tool_reject(paste(
          "Question", i, "option", j,
          "must have 'label' and 'description'"
        ))
      }
    }
  }

  TRUE
}

#' AskUserQuestion tool
#'
#' @description
#' A tool that allows the agent to ask the user clarifying questions and
#' receive their responses. This enables human-in-the-loop workflows where
#' the agent can request clarification or choices from the user.
#'
#' @param questions JSON string or list of question objects following the SDK format.
#'   Each question should have: `question` (string), `header` (string, max 12 chars),
#'   `options` (list of objects with `label` and `description`), and optionally
#'   `multiSelect` (logical).
#'
#' @format A tool definition created with `ellmer::tool()`.
#'
#' @details
#' This tool follows the Anthropic Agent SDK format:
#'
#' **Input format:**
#' - `questions`: Array of 1-4 question objects
#' - Each question has:
#'   - `question`: The full question text
#'   - `header`: Short label (max 12 chars)
#'   - `options`: Array of 2-4 options, each with `label` and `description`
#'   - `multiSelect`: Whether multiple selections are allowed
#'
#' **Output format:**
#' - Returns a list with two elements:
#'   - `questions`: The original questions array (echoed back)
#'   - `answers`: Named list mapping question text to selected label(s)
#' - For multi-select, labels are joined with ", "
#' - Users can also type free-form responses
#'
#' In interactive R sessions, the tool uses `readline()` to get input.
#' For non-interactive use (scripts, Shiny apps), set a callback with
#' [set_ask_user_callback()].
#'
#' @examples
#' \dontrun{
#' # Add to agent's tools
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = c(tools_file(), tool_ask_user)
#' )
#'
#' # The agent can ask structured questions like:
#' # {
#' #   "questions": [{
#' #     "question": "How should I format the output?",
#' #     "header": "Format",
#' #     "options": [
#' #       {"label": "Summary", "description": "Brief overview"},
#' #       {"label": "Detailed", "description": "Full explanation"}
#' #     ],
#' #     "multiSelect": false
#' #   }]
#' # }
#' }
#'
#' @seealso [set_ask_user_callback()] for non-interactive usage
#'
#' @export
tool_ask_user <- ellmer::tool(
  fun = function(questions) {
    # Handle JSON string input (from LLMs that pass stringified JSON)
    if (is.character(questions) && length(questions) == 1) {
      parsed <- tryCatch(
        jsonlite::fromJSON(questions, simplifyVector = FALSE),
        error = function(e) {
          ellmer::tool_reject(paste("Failed to parse questions JSON:", e$message))
        }
      )
      # Guard against unexpected NULL from parsing
      if (is.null(parsed)) {
        ellmer::tool_reject("JSON parsing returned NULL unexpectedly")
      }
      questions <- parsed
    }

    # Validate the questions structure
    validate_questions(questions)

    # Get user answers with specific error handling
    tryCatch(
      {
        answers <- ask_user_impl(questions)

        # Return in the expected format
        list(
          questions = questions,
          answers = answers
        )
      },
      interrupt = function(e) {
        # Let user interrupts (Ctrl+C) propagate normally
        stop(e)
      },
      error = function(e) {
        # Include error class for debugging callback issues
        error_class <- paste(class(e), collapse = ", ")
        ellmer::tool_reject(paste0(
          "Failed to get user input: ", e$message,
          " [", error_class, "]"
        ))
      }
    )
  },
  name = "AskUserQuestion",
  description = paste(
    "Ask the user clarifying questions when you need more information to proceed.",
    "Present 1-4 questions with 2-4 options each.",
    "Format: JSON array of question objects, each with:",
    "- question (string): The full question text",
    "- header (string, max 12 chars): Short label",
    "- options (array of 2-4 objects with 'label' and 'description')",
    "- multiSelect (boolean, optional): Allow multiple selections",
    "Example: [{\"question\": \"Which format?\", \"header\": \"Format\",",
    "\"options\": [{\"label\": \"JSON\", \"description\": \"JavaScript Object Notation\"},",
    "{\"label\": \"YAML\", \"description\": \"YAML format\"}]}]"
  ),
  arguments = list(
    questions = ellmer::type_string(
      paste(
        "JSON array of 1-4 question objects. Each object has: question, header,",
        "options (array of {label, description}), and optionally multiSelect."
      )
    )
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE,
    open_world_hint = FALSE
  )
)

#' Tools for interactive workflows
#'
#' @description
#' Returns a list of tools that enable human-in-the-loop interactions.
#' Currently includes `tool_ask_user` (AskUserQuestion) for asking
#' clarifying questions.
#'
#' @return A list of tool definitions.
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = c(tools_file(), tools_interactive())
#' )
#' }
#'
#' @seealso [tool_ask_user], [set_ask_user_callback()]
#'
#' @export
tools_interactive <- function() {
  list(tool_ask_user)
}
