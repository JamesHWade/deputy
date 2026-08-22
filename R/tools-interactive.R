# Interactive tools for human-in-the-loop workflows
#
# This implements Deputy's structured ask_user tool:
# - questions: array of 1-4 questions
# - Each question has: question, header, options (2-4), multiSelect
# - Each option has: label, description
# - Returns: answers mapping question text to selected label(s)

# Package-level storage for the legacy user input callback
.deputy_env <- new.env(parent = emptyenv())
.deputy_env$ask_user_callback <- NULL

validate_ask_user_callback <- function(callback, arg = "callback") {
  if (!is.null(callback) && !is.function(callback)) {
    cli::cli_abort("{.arg {arg}} must be a function or NULL")
  }
  callback
}

validate_ask_user_context <- function(context, arg = "context") {
  if (is.function(context)) {
    return(context)
  }
  if (!is.list(context)) {
    cli::cli_abort("{.arg {arg}} must be a named list or a function")
  }
  if (
    length(context) > 0 &&
      (is.null(names(context)) || !all(nzchar(names(context))))
  ) {
    cli::cli_abort("{.arg {arg}} must have non-empty names")
  }
  context
}

resolve_ask_user_context <- function(context) {
  if (is.function(context)) {
    context <- context()
  }
  validate_ask_user_context(context)
}

#' Set callback for non-interactive user input
#'
#' @description
#' Sets a legacy process-wide callback for non-interactive sessions. This
#' fallback cannot isolate concurrent Agents or Shiny sessions. New code should
#' bind a handler to a tool instance with [tools_interactive()].
#'
#' @param callback A function that takes `questions` in Deputy's structured
#'   question format. Each question has `question`, `header`,
#'   `options` (list with `label` and `description`), and `multiSelect`.
#'   Should return a named list mapping question text to selected label(s).
#'   For multi-select, join labels with ", ".
#'   Set to NULL to clear the callback.
#'
#' @return Invisibly returns the previous callback (or NULL).
#'
#' @examples
#' \dontrun{
#' # Legacy fallback for a single-Agent script:
#' set_ask_user_callback(function(questions) {
#'   # Display questions in modal and collect answers
#'   answers <- list()
#'   for (q in questions) {
#'     # Collect one answer for each question.
#'     answers[[q$question]] <- selected_label
#'   }
#'   answers
#' })
#' }
#'
#' @export
set_ask_user_callback <- function(callback) {
  callback <- validate_ask_user_callback(callback)
  old <- .deputy_env$ask_user_callback
  .deputy_env$ask_user_callback <- callback
  invisible(old)
}

#' Get the current user input callback
#'
#' @return The current callback function, or NULL if none set.
#' @noRd
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

    if (!anyNA(indices)) {
      # All parts are valid numbers
      valid_indices <- indices[indices >= 1 & indices <= length(options)]
      if (length(valid_indices) > 0) {
        labels <- vapply(
          valid_indices,
          function(i) options[[i]]$label,
          character(1)
        )
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
#' @param questions List of structured question objects
#' @param callback Optional instance-scoped handler. It receives `questions`
#'   and the resolved `context`. When omitted, the legacy process-wide fallback
#'   is used.
#' @param context Named routing context or a zero-argument function that returns
#'   it.
#' @return Named list mapping question text to selected answers
#' @keywords internal
ask_user_impl <- function(questions, callback = NULL, context = list()) {
  if (!is.null(callback)) {
    return(callback(questions, resolve_ask_user_context(context)))
  }

  legacy_callback <- get_ask_user_callback()
  if (!is.null(legacy_callback)) {
    return(legacy_callback(questions))
  }

  # Check if we're in an interactive session
  if (!interactive()) {
    abort_deputy(
      c(
        "Cannot ask user: no human-input handler is available",
        "i" = paste(
          "Use {.fn tools_interactive} with an instance-scoped",
          "{.arg callback} in non-interactive hosts."
        )
      ),
      class = "human_input_unavailable",
      questions = questions,
      context = resolve_ask_user_context(context)
    )
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
      cli::cli_text(
        "  (Enter numbers separated by commas, or type your own answer)"
      )
    } else {
      cli::cli_text("  (Enter a number, or type your own answer)")
    }

    # Get response
    repeat {
      response <- readline("> ")
      response_trimmed <- trimws(response)

      if (nchar(response_trimmed) > 0) {
        answer <- parse_user_response(
          response_trimmed,
          options,
          isTRUE(q$multiSelect)
        )
        answers[[q$question]] <- answer
        break
      }
      cli::cli_alert_warning("Please enter a response")
    }
  }

  answers
}

ask_user_tool_impl <- function(questions, callback = NULL, context = list()) {
  if (is.character(questions) && length(questions) == 1) {
    parsed <- tryCatch(
      jsonlite::fromJSON(questions, simplifyVector = FALSE),
      error = function(e) {
        ellmer::tool_reject(paste(
          "Failed to parse questions JSON:",
          e$message
        ))
      }
    )
    if (is.null(parsed)) {
      ellmer::tool_reject("JSON parsing returned NULL unexpectedly")
    }
    questions <- parsed
  }

  validate_questions(questions)

  tryCatch(
    {
      answers <- ask_user_impl(
        questions,
        callback = callback,
        context = context
      )
      list(
        questions = questions,
        answers = answers
      )
    },
    interrupt = function(e) {
      rlang::cnd_signal(e)
    },
    error = function(e) {
      if (inherits(e, "deputy_human_input_unavailable")) {
        rlang::cnd_signal(e)
      }
      error_class <- paste(class(e), collapse = ", ")
      ellmer::tool_reject(paste0(
        "Failed to get user input: ",
        e$message,
        " [",
        error_class,
        "]"
      ))
    }
  )
}

new_ask_user_tool <- function(callback = NULL, context = list()) {
  callback <- validate_ask_user_callback(callback)
  context <- validate_ask_user_context(context)

  ellmer::tool(
    fun = function(questions) {
      ask_user_tool_impl(
        questions,
        callback = callback,
        context = context
      )
    },
    name = "ask_user",
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
          "Question",
          i,
          "option",
          j,
          "must have 'label' and 'description'"
        ))
      }
    }
  }

  TRUE
}

#' Ask user tool
#'
#' @description
#' A tool that allows the agent to ask the user clarifying questions and
#' receive their responses. This enables human-in-the-loop workflows where
#' the agent can request clarification or choices from the user.
#'
#' @param questions JSON string or list of structured question objects.
#'   Each question should have: `question` (string), `header` (string, max 12 chars),
#'   `options` (list of objects with `label` and `description`), and optionally
#'   `multiSelect` (logical).
#'
#' @format A tool definition created with `ellmer::tool()`.
#'
#' @details
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
#' In interactive R sessions, the tool uses `readline()` to get input. The
#' exported object uses [set_ask_user_callback()] only as a legacy process-wide
#' fallback. Non-interactive and concurrent hosts should create an isolated
#' tool with [tools_interactive()].
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
#' @seealso [tools_interactive()] for instance-scoped non-interactive usage
#'
#' @export
tool_ask_user <- new_ask_user_tool()

#' Tools for interactive workflows
#'
#' @description
#' Returns a list of tools that enable human-in-the-loop interactions.
#' Currently includes `tool_ask_user` (`ask_user`) for asking
#' clarifying questions. Supply `callback` in non-interactive or concurrent
#' hosts so each Agent receives its own handler.
#'
#' @param callback Optional handler with signature `function(questions,
#'   context)`. It should return a named list that maps each question text to
#'   the selected label or labels. When omitted, interactive sessions use
#'   `readline()` and non-interactive sessions may use the legacy callback from
#'   [set_ask_user_callback()].
#' @param context Named list of stable host routing values, such as `agent_id`
#'   and `session_id`, or a zero-argument function returning that list. A
#'   function is resolved for each question request.
#'
#' @return A list of tool definitions.
#'
#' @examples
#' \dontrun{
#' agent_id <- "agent-review"
#' session_id <- "session-review"
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = c(
#'     tools_file(),
#'     tools_interactive(
#'       callback = function(questions, context) {
#'         collect_answers(questions, route = context$session_id)
#'       },
#'       context = list(agent_id = agent_id, session_id = session_id)
#'     )
#'   ),
#'   agent_id = agent_id,
#'   session_id = session_id
#' )
#' }
#'
#' @seealso [tool_ask_user], [set_ask_user_callback()]
#'
#' @export
tools_interactive <- function(callback = NULL, context = list()) {
  list(new_ask_user_tool(callback = callback, context = context))
}
