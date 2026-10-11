#' @include callback-result.R
NULL

# Interactive tools for human-in-the-loop workflows
#
# This implements Deputy's structured ask_user tool:
# - questions: a typed array of 1-4 questions (a string is rejected)
# - Each question has: question, header (<= 12 chars), options (2-4), multiSelect
# - Each option has: label, description
# - A handler returns a named list mapping question text to a character vector
# - The model receives JSON: the questions plus, per question in order,
#   `selected` (an array of option labels) and `other_text` (a string or null)

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
#'   `description`) and `multiSelect`. It returns a named list that maps each
#'   question's text to a character vector of answers, as described in
#'   [tools_interactive()]. `NULL` removes the callback.
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
#' A response made only of digits, commas, signs, dots and spaces is read as
#' option numbers. Each must be a whole number from 1 to the number of
#' options, and a single-select question takes exactly one. Any other text is
#' the person's own answer.
#'
#' @param response User's input string
#' @param options List of option objects with label and description
#' @param multi_select Whether multiple selections are allowed
#' @return A character vector: the chosen labels, in the order given, or the
#'   free text response. `NULL` when the response is option numbers that
#'   can't all be used, so the caller asks again.
#' @keywords internal
parse_user_response <- function(response, options, multi_select = FALSE) {
  response <- trimws(response)
  if (!grepl("^[0-9.,+[:space:]-]+$", response) || !grepl("[0-9]", response)) {
    return(response)
  }

  parts <- trimws(strsplit(response, ",", fixed = TRUE)[[1]])
  if (
    !length(parts) ||
      !all(grepl("^[0-9]+$", parts)) ||
      (!multi_select && length(parts) != 1L)
  ) {
    return(NULL)
  }
  indices <- as.numeric(parts)
  if (any(indices < 1 | indices > length(options))) {
    return(NULL)
  }
  vapply(
    unique(indices),
    function(index) options[[index]][["label"]],
    character(1)
  )
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
    question <- q[["question"]]
    options <- q[["options"]]
    multi_select <- isTRUE(q[["multiSelect"]])
    cli::cli_h3("{q[['header']]}: {question}")

    for (i in seq_along(options)) {
      cli::cli_text(
        "  {i}. {options[[i]][['label']]} - {options[[i]][['description']]}"
      )
    }

    if (multi_select) {
      cli::cli_text(
        "  (Enter numbers separated by commas, or type your own answer)"
      )
    } else {
      cli::cli_text("  (Enter a number, or type your own answer)")
    }

    repeat {
      response <- trimws(readline("> "))
      if (!nzchar(response)) {
        cli::cli_alert_warning("Please enter a response")
        next
      }
      answer <- parse_user_response(response, options, multi_select)
      if (!is.null(answer)) {
        answers[[question]] <- answer
        break
      }
      if (multi_select) {
        cli::cli_alert_warning(
          "Enter option numbers from 1 to {length(options)}, separated by commas, or type your own answer."
        )
      } else {
        cli::cli_alert_warning(
          "Enter one option number from 1 to {length(options)}, or type your own answer."
        )
      }
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
  questions <- validate_questions(questions)

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
        tryCatch(
          ask_user_result(questions, value, allow_deferred),
          error = ask_user_promise_failure
        )
      },
      onRejected = ask_user_promise_failure
    ))
  }
  if (!S7::S7_inherits(answers, AskUserDeferred)) {
    return(ask_user_json(questions, ask_user_answers(questions, answers)))
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

# A handler's promise that rejects, or resolves to answers of the wrong shape,
# is a rejection the model sees. A missing handler still reaches the host.
ask_user_promise_failure <- function(e) {
  if (inherits(e, c("deputy_human_input_unavailable", "ellmer_tool_reject"))) {
    rlang::cnd_signal(e)
  }
  ellmer::tool_reject(paste0(
    "Failed to get user input: ",
    conditionMessage(e)
  ))
}

ask_user_quote <- function(text) {
  encodeString(text, quote = "\"")
}

ask_user_answers_abort <- function(detail) {
  abort_deputy("{detail}", class = "ask_user_answers")
}

# Reads a handler's answers: a named list keyed by exact question text, each a
# character vector. Elements that are offered labels are `selected`, in option
# order; at most one other element is the person's own `other_text`.
ask_user_answers <- function(questions, answers) {
  texts <- vapply(questions, function(q) q[["question"]], character(1))
  if (!is.list(answers) || is.data.frame(answers)) {
    ask_user_answers_abort(paste0(
      "The handler must return a named list that maps each question's ",
      "text to a character vector of answers, not ",
      class(answers)[[1]],
      "."
    ))
  }
  keys <- names(answers)
  if (length(answers) && (is.null(keys) || anyNA(keys) || !all(nzchar(keys)))) {
    ask_user_answers_abort(
      "The handler must name each answer with its question's text."
    )
  }
  unknown <- setdiff(keys, texts)
  if (length(unknown)) {
    ask_user_answers_abort(paste0(
      "The handler answered ",
      ask_user_quote(unknown[[1]]),
      ", which isn't one of the questions asked."
    ))
  }
  repeated <- unique(keys[duplicated(keys)])
  if (length(repeated)) {
    ask_user_answers_abort(paste0(
      "The handler answered ",
      ask_user_quote(repeated[[1]]),
      " more than once."
    ))
  }

  lapply(questions, function(q) {
    text <- q[["question"]]
    values <- if (text %in% keys) answers[[text]] else character()
    if (!is.character(values)) {
      ask_user_answers_abort(paste0(
        "The handler's answer to ",
        ask_user_quote(text),
        " must be a character vector, not ",
        class(values)[[1]],
        "."
      ))
    }
    if (anyNA(values)) {
      ask_user_answers_abort(paste0(
        "The handler's answer to ",
        ask_user_quote(text),
        " contains NA."
      ))
    }
    # Padding from a text input doesn't turn a chosen label into free text.
    values <- trimws(as.character(values))
    values <- unique(values[nzchar(values)])
    labels <- vapply(q[["options"]], function(o) o[["label"]], character(1))
    chosen <- labels[trimws(labels) %in% values]
    other <- values[!values %in% trimws(labels)]
    if (length(other) > 1L) {
      ask_user_answers_abort(paste0(
        "The handler gave ",
        length(other),
        " answers to ",
        ask_user_quote(text),
        " that aren't option labels; give at most one."
      ))
    }
    if (!isTRUE(q[["multiSelect"]]) && length(values) > 1L) {
      ask_user_answers_abort(paste0(
        ask_user_quote(text),
        " takes one answer, but the handler gave ",
        length(values),
        "."
      ))
    }
    list(
      question = text,
      selected = chosen,
      other_text = if (length(other)) other else NULL
    )
  })
}

# What the model receives. `selected` stays an array even with one label, and
# a missing `other_text` is null rather than an empty object.
ask_user_json <- function(questions, answers) {
  answers <- lapply(answers, function(answer) {
    answer$selected <- I(answer$selected)
    answer
  })
  jsonlite::toJSON(
    list(questions = questions, answers = answers),
    auto_unbox = TRUE,
    null = "null"
  )
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

  mark_native_tool(ellmer::tool(
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
      "Present 1-4 different questions with 2-4 options each,",
      "as an array of objects rather than JSON text.",
      "The user picks one option, or several when multiSelect is true,",
      "and may also type their own answer.",
      "The result lists each question with `selected` (the chosen option labels)",
      "and `other_text` (what the user typed, or null)."
    ),
    arguments = list(questions = ask_user_questions_type()),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  ))
}

# The schema the model fills in. The tool uses `convert = FALSE`, so it gets
# the provider's arrays as lists rather than data frames.
ask_user_questions_type <- function() {
  ellmer::type_array(
    ellmer::type_object(
      question = ellmer::type_string(
        "The full question text, different from the other questions."
      ),
      header = ellmer::type_string(
        "A short label for the question, at most 12 characters."
      ),
      options = ellmer::type_array(
        ellmer::type_object(
          label = ellmer::type_string(
            "The option's short label, different from the question's other labels."
          ),
          description = ellmer::type_string("What choosing this option means.")
        ),
        "2 to 4 options."
      ),
      multiSelect = ellmer::type_boolean(
        "Whether the user may choose several options. Defaults to false.",
        required = FALSE
      )
    ),
    "1 to 4 questions."
  )
}

ask_user_reject <- function(...) {
  ellmer::tool_reject(paste0(...))
}

is_ask_user_array <- function(x) {
  is.list(x) && !is.data.frame(x) && is.null(names(x))
}

is_ask_user_object <- function(x) {
  is.list(x) && !is.data.frame(x) && !is.null(names(x))
}

# One non-empty string; the field is read by its exact name.
ask_user_text <- function(object, field, where) {
  value <- object[[field]]
  if (is.null(value)) {
    ask_user_reject(where, " is missing '", field, "'.")
  }
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(trimws(value))
  ) {
    ask_user_reject(where, " '", field, "' must be one non-empty string.")
  }
  as.character(value)
}

#' Validate questions structure
#'
#' Checks the typed questions array. A string is never parsed or read: it is
#' rejected like any other malformed value. Each failure is a tool rejection
#' whose message tells the model what to fix.
#'
#' @param questions List of question objects
#' @return The questions, each with exactly `question`, `header`, `options`
#'   (each with `label` and `description`) and a logical `multiSelect`.
#' @keywords internal
validate_questions <- function(questions) {
  if (is.character(questions)) {
    ask_user_reject(
      "questions must be an array of question objects, not a string; ",
      "send the array itself rather than JSON text."
    )
  }
  if (!is.list(questions) || is.data.frame(questions)) {
    ask_user_reject("questions must be an array of 1 to 4 question objects.")
  }
  if (!length(questions)) {
    ask_user_reject(
      "questions must be a non-empty array: ask 1 to 4 questions."
    )
  }
  if (!is_ask_user_array(questions)) {
    ask_user_reject(
      "questions must be an array of question objects, not a named object; ",
      "put a single question inside an array."
    )
  }
  if (length(questions) > 4L) {
    ask_user_reject(
      "Maximum 4 questions allowed per call; got ",
      length(questions),
      "."
    )
  }

  questions <- lapply(seq_along(questions), function(i) {
    q <- questions[[i]]
    where <- paste("Question", i)
    if (!is_ask_user_object(q)) {
      ask_user_reject(
        where,
        " must be an object with 'question', 'header' and 'options'."
      )
    }
    question <- ask_user_text(q, "question", where)
    header <- ask_user_text(q, "header", where)
    if (nchar(header, type = "chars") > 12L) {
      ask_user_reject(
        where,
        " 'header' has ",
        nchar(header, type = "chars"),
        " characters; use at most 12."
      )
    }

    options <- q[["options"]]
    if (is.null(options)) {
      ask_user_reject(where, " is missing 'options'.")
    }
    if (!is_ask_user_array(options)) {
      ask_user_reject(where, " 'options' must be an array of 2-4 options.")
    }
    if (length(options) < 2L || length(options) > 4L) {
      ask_user_reject(
        where,
        " must have 2-4 options; got ",
        length(options),
        "."
      )
    }
    options <- lapply(seq_along(options), function(j) {
      option <- options[[j]]
      at <- paste(where, "option", j)
      if (!is_ask_user_object(option)) {
        ask_user_reject(
          at,
          " must be an object with 'label' and 'description'."
        )
      }
      list(
        label = ask_user_text(option, "label", at),
        description = ask_user_text(option, "description", at)
      )
    })
    labels <- vapply(options, function(o) o[["label"]], character(1))
    if (anyDuplicated(labels)) {
      ask_user_reject(
        where,
        " has the option label ",
        ask_user_quote(labels[anyDuplicated(labels)]),
        " more than once; give each option a different label."
      )
    }

    multi_select <- q[["multiSelect"]]
    if (is.null(multi_select)) {
      multi_select <- FALSE
    }
    if (
      !is.logical(multi_select) ||
        length(multi_select) != 1L ||
        is.na(multi_select)
    ) {
      ask_user_reject(where, " 'multiSelect' must be true or false.")
    }

    list(
      question = question,
      header = header,
      options = options,
      multiSelect = multi_select
    )
  })

  texts <- vapply(questions, function(q) q[["question"]], character(1))
  if (anyDuplicated(texts)) {
    ask_user_reject(
      "Each question must be different; ",
      ask_user_quote(texts[anyDuplicated(texts)]),
      " is asked more than once."
    )
  }
  questions
}

#' Ask the user questions
#'
#' @description
#' A tool that lets the model ask the user one to four multiple-choice
#' questions and wait for the answers.
#'
#' @param questions A list of 1 to 4 questions. Each has `question` (the full
#'   text), `header` (a label of at most 12 characters), `options` (2 to 4,
#'   each with `label` and `description`) and, optionally, `multiSelect`
#'   (`TRUE` to allow several options). Every text is a non-empty string, no
#'   two questions have the same text, and no two options of a question have
#'   the same label. Questions that break these rules, or that arrive as a
#'   string such as JSON text, are sent back to the model to fix.
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return JSON text, which is what the model reads. It holds the `questions`
#'   and an `answers` array with one entry per question, in the same order:
#'   `question`, `selected` (an array of the chosen option labels, empty if
#'   none was chosen) and `other_text` (the answer the person typed instead
#'   of, or for a multi-select question as well as, choosing options; `null`
#'   if none). Read it in R with `jsonlite::parse_json()`. If the handler
#'   returns [AskUserDeferred()], the result is instead a list with the
#'   `questions`, `status` `"deferred"` and `instructions` for the model.
#'
#' @details
#' This tool asks through the callback set with [set_ask_user_callback()] if
#' there is one, and otherwise with `readline()` in an interactive session.
#' With neither, the call errors. In a Shiny app, or anywhere several agents
#' share one R process, use [tools_interactive()] to give each agent its own
#' handler.
#'
#' At the `readline()` prompt, the person enters an option number, several
#' numbers separated by commas for a multi-select question, or their own
#' answer. A number that doesn't match an option asks again.
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
#' @param callback A function of `questions` and `context` that returns the
#'   answers, a promise for them, or [AskUserDeferred()] when the answers will
#'   come in the person's next message. Shiny apps can't wait for input, so
#'   they return a promise or `AskUserDeferred()`. If `NULL`, the tool uses the
#'   [set_ask_user_callback()] callback if one is set, and otherwise
#'   `readline()` in an interactive session. See "Answers" below.
#' @param context A named list passed to `callback`, such as `agent_id` and
#'   `session_id` values that tell your app where to show the questions, or a
#'   function with no arguments that returns one. A function is called each
#'   time the model asks.
#'
#' @return A list of tools.
#'
#' @section Answers:
#' The answers are a named list. Each name is the exact text of a question,
#' and each value is a character vector:
#'
#' * the chosen option labels: one for an ordinary question, any number for a
#'   question with `multiSelect = TRUE`;
#' * at most one other string, the answer the person typed themselves. For an
#'   ordinary question it takes the place of a label.
#'
#' Leave a question out, or give it `character()`, if it wasn't answered.
#' Give each chosen label as its own element; a string that isn't a label is
#' the person's own answer. A name that isn't one of the questions, a value
#' that isn't a character vector, or too many answers for a question is an
#' error, and the model is told the answers couldn't be collected.
#'
#' The model receives, for each question, the `selected` labels and the
#' `other_text`; see [tool_ask_user] for the exact result.
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
