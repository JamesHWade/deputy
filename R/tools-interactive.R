#' @include callback-result.R
NULL

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

#' Set a process-wide handler for ask_user
#'
#' @description
#' Sets a callback that answers questions for every `ask_user` tool without its
#' own handler, including [tool_ask_user]. It is used instead of `readline()`,
#' even in interactive sessions. Because it is shared by the whole R process, it
#' can't tell concurrent agents or Shiny sessions apart; for those, give each
#' agent its own handler with [tools_interactive()].
#'
#' @param callback A function that takes `questions`, a list in which each
#'   question has `question`, `header`, `options` (each with `label` and
#'   `description`) and `multiSelect`. It returns a named list mapping each
#'   question's text to the chosen label; join several labels with `", "`.
#'   `NULL` removes the callback.
#'
#' @return The previous callback (or `NULL`), invisibly.
#'
#' @examples
#' \dontrun{
#' # For a single-agent script: always pick the first option
#' set_ask_user_callback(function(questions) {
#'   answers <- list()
#'   for (q in questions) {
#'     answers[[q$question]] <- q$options[[1]]$label
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
#' @param questions List of question objects.
#' @param callback Optional handler for this tool. It receives `questions` and
#'   the resolved `context`. When omitted, the callback from
#'   [set_ask_user_callback()] is used, then `readline()`.
#' @param context Named list, or a function with no arguments that returns one.
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

ask_user_tool_impl <- function(
  questions,
  callback = NULL,
  context = list(),
  allow_deferred = TRUE
) {
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
      ask_user_result(questions, answers, allow_deferred)
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

# A host handler returns answers, a promise for answers, or AskUserDeferred().
ask_user_result <- function(questions, answers, allow_deferred = TRUE) {
  if (promises::is.promising(answers)) {
    return(promises::then(
      answers,
      onFulfilled = function(value) {
        ask_user_result(questions, value, allow_deferred)
      },
      onRejected = function(e) {
        ellmer::tool_reject(paste0(
          "Failed to get user input: ",
          conditionMessage(e)
        ))
      }
    ))
  }
  if (!S7::S7_inherits(answers, AskUserDeferred)) {
    return(list(questions = questions, answers = answers))
  }
  if (!allow_deferred) {
    abort_deputy(
      c(
        "Delegated agents cannot defer human input to a later turn.",
        "i" = "Return the answers, or a promise for them, from the handler."
      ),
      class = "human_input_unavailable",
      questions = questions
    )
  }
  value <- list(
    questions = questions,
    status = "deferred",
    instructions = answers@instructions
  )
  if (!length(answers@extra)) {
    return(value)
  }
  ellmer::ContentToolResult(value = value, extra = answers@extra)
}

#' Defer answers to a later user turn
#'
#' @description
#' Return `AskUserDeferred()` from a [tools_interactive()] handler when your app
#' shows the questions without waiting for the answers, as a chat interface
#' does. The tool result tells the model that the questions are on screen and
#' that it should end its turn; the person's answers arrive as their next
#' message.
#'
#' A handler that must wait within the run can instead return a
#' `promises::promise()` for the answers. Deferring keeps runs short, and the
#' answers arrive as an ordinary user message. Subagents can't defer; their
#' handler must return the answers or a promise.
#'
#' @param instructions One string telling the model what happens next. The
#'   default asks it to end its turn without answering for the person.
#' @param extra Optional named list stored in the tool result's `extra` field
#'   (see `ellmer::ContentToolResult()`), for example data your app uses to
#'   display the questions.
#' @return A read-only `AskUserDeferred` S7 object.
#' @seealso [tools_interactive()]
#' @examples
#' handler <- function(questions, context) {
#'   # Show `questions` in your app, then return without waiting.
#'   AskUserDeferred()
#' }
#' tools <- tools_interactive(callback = handler)
#' @export
AskUserDeferred <- S7::new_class(
  "AskUserDeferred",
  package = "deputy",
  properties = list(
    instructions = readonly_property("instructions", S7::class_character),
    extra = readonly_property("extra", S7::class_list)
  ),
  constructor = function(
    instructions = paste(
      "The questions are now displayed to the person.",
      "End your turn with at most one short sentence.",
      "Do not answer the questions for them or assume a choice;",
      "their answers will arrive in their next message."
    ),
    extra = list()
  ) {
    instructions <- validate_callback_text(
      instructions,
      "instructions",
      optional = FALSE
    )
    if (!is.list(extra) || (length(extra) && !rlang::is_named(extra))) {
      cli::cli_abort("{.arg extra} must be a named list")
    }
    value <- S7::new_object(
      S7::S7_object(),
      instructions = instructions,
      extra = extra
    )
    freeze_value(value)
  }
)

new_ask_user_tool <- function(
  callback = NULL,
  context = list(),
  allow_deferred = TRUE
) {
  callback <- validate_ask_user_callback(callback)
  context <- validate_ask_user_context(context)

  ellmer::tool(
    fun = function(questions) {
      ask_user_tool_impl(
        questions,
        callback = callback,
        context = context,
        allow_deferred = allow_deferred
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

#' Ask the user questions
#'
#' @description
#' A tool that lets the model ask the user one to four multiple-choice
#' questions and wait for the answers.
#'
#' @param questions A JSON string or list of 1 to 4 questions. Each has
#'   `question` (the full text), `header` (a label of at most 12 characters),
#'   `options` (2 to 4, each with `label` and `description`) and, optionally,
#'   `multiSelect`.
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return A list with the `questions` and a named `answers` list that maps
#'   each question's text to the chosen label. Several labels are joined with
#'   `", "`, and a person can also type their own answer.
#'
#' @details
#' This tool asks through the callback set with [set_ask_user_callback()] if
#' there is one, and otherwise with `readline()` in an interactive session.
#' With neither, the call errors. In a Shiny app, or anywhere several agents
#' share one R process, use [tools_interactive()] to give each agent its own
#' handler.
#'
#' @examples
#' \dontrun{
#' # Add to agent's tools
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
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
#' @seealso [tools_interactive()] to give each agent its own handler.
#'
#' @export
tool_ask_user <- new_ask_user_tool()

#' Create an ask_user tool with its own handler
#'
#' @description
#' Returns a list holding one `ask_user` tool (see [tool_ask_user]) that sends
#' questions to `callback`. Give each agent its own tool when several agents or
#' Shiny sessions share one R process, or when the session isn't interactive.
#'
#' @param callback A function of `questions` and `context` that returns a
#'   named list mapping each question's text to the chosen label or labels, a
#'   promise for that list, or [AskUserDeferred()] when the answers will come in
#'   the person's next message. Shiny apps can't wait for input, so they return
#'   a promise or `AskUserDeferred()`. If `NULL`, the tool uses the
#'   [set_ask_user_callback()] callback if one is set, and otherwise
#'   `readline()` in an interactive session.
#' @param context A named list passed to `callback`, such as `agent_id` and
#'   `session_id` values that tell your app where to show the questions, or a
#'   function with no arguments that returns one. A function is called each
#'   time the model asks.
#'
#' @return A list of tools.
#'
#' @examples
#' \dontrun{
#' agent_id <- "agent-review"
#' session_id <- "session-review"
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
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
