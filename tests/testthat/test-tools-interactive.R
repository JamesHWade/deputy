# Tests for interactive tools

interaction_test_questions <- function() {
  list(list(
    question = "Which format?",
    header = "Format",
    options = list(
      list(label = "JSON", description = "Structured JSON"),
      list(label = "YAML", description = "Readable YAML")
    ),
    multiSelect = FALSE
  ))
}

# A multi-select question whose first label holds a comma, a single-select
# question, and a question that can be left unanswered.
interaction_shape_questions <- function() {
  list(
    list(
      question = "Which outputs?",
      header = "Outputs",
      options = list(
        list(label = "Tables, charts", description = "Figures and tables"),
        list(label = "Text", description = "A written summary"),
        list(label = "Slides", description = "A short deck")
      ),
      multiSelect = TRUE
    ),
    interaction_test_questions()[[1]],
    list(
      question = "Anything else?",
      header = "Else",
      options = list(
        list(label = "No", description = "Nothing more"),
        list(label = "Yes", description = "Something more")
      ),
      multiSelect = FALSE
    )
  )
}

# The first test question with fields replaced; a NULL value removes a field.
interaction_question_with <- function(...) {
  question <- interaction_test_questions()[[1]]
  changes <- list(...)
  for (field in names(changes)) {
    question[[field]] <- changes[[field]]
  }
  list(question)
}

# What the model reads: the tool's JSON text, parsed without simplification.
interaction_model_view <- function(result) {
  expect_s3_class(result, "json")
  jsonlite::parse_json(result)
}

interaction_answer <- function(result, index = 1L) {
  interaction_model_view(result)$answers[[index]]
}

interaction_answering_tool <- function(answers) {
  force(answers)
  tools_interactive(callback = function(questions, context) answers)[[1]]
}

expect_questions_rejected <- function(questions, message) {
  asked <- FALSE
  tool <- tools_interactive(callback = function(questions, context) {
    asked <<- TRUE
    list()
  })[[1]]
  condition <- rlang::catch_cnd(tool(questions), "error")
  expect_s3_class(condition, "ellmer_tool_reject")
  expect_match(conditionMessage(condition), message, fixed = TRUE)
  expect_false(asked)
}

expect_answers_rejected <- function(answers, message) {
  condition <- rlang::catch_cnd(
    interaction_answering_tool(answers)(interaction_shape_questions()),
    "error"
  )
  expect_s3_class(condition, "ellmer_tool_reject")
  expect_match(
    conditionMessage(condition),
    "Failed to get user input: ",
    fixed = TRUE
  )
  expect_match(conditionMessage(condition), message, fixed = TRUE)
}

# The content of each tool result the model was sent in one recorded request.
sent_tool_results <- function(server, request) {
  messages <- server$requests()[[request]]$body$messages
  results <- Filter(function(message) identical(message$role, "tool"), messages)
  vapply(results, function(message) message$content, character(1))
}

test_that("tool_ask_user has correct structure", {
  expect_true(inherits(tool_ask_user, "ellmer::ToolDef"))

  expect_equal(tool_ask_user@name, "ask_user")

  # Check it has the right annotations
  annotations <- tool_ask_user@annotations
  expect_true(annotations$read_only_hint)
  expect_false(annotations$destructive_hint)
})

test_that("ask_user declares a typed questions array and receives it as sent", {
  questions <- tool_ask_user@arguments@properties$questions
  question <- questions@items
  option <- question@properties$options@items

  expect_false(tool_ask_user@convert)
  expect_true(S7::S7_inherits(questions, ellmer::TypeArray))
  expect_true(S7::S7_inherits(question, ellmer::TypeObject))
  expect_named(
    question@properties,
    c("question", "header", "options", "multiSelect")
  )
  expect_true(S7::S7_inherits(question@properties$question, ellmer::TypeBasic))
  expect_identical(question@properties$question@type, "string")
  expect_identical(question@properties$header@type, "string")
  expect_identical(question@properties$multiSelect@type, "boolean")
  expect_false(question@properties$multiSelect@required)
  expect_true(question@properties$header@required)
  expect_named(option@properties, c("label", "description"))
})

test_that("tools_interactive returns tool list", {
  tools <- tools_interactive()
  expect_true(is.list(tools))
  expect_true(length(tools) >= 1)

  tool_names <- vapply(tools, function(t) t@name, character(1))
  expect_true("ask_user" %in% tool_names)
})

test_that("tools_interactive isolates handlers and routing context", {
  set_ask_user_callback(NULL)
  seen <- list()
  make_handler <- function(key) {
    force(key)
    function(questions, context) {
      seen[[key]] <<- context
      stats::setNames(list(key), questions[[1]]$question)
    }
  }

  chat_a <- create_mock_chat()
  chat_b <- create_mock_chat()
  agent_a <- Agent$new(
    chat = chat_a,
    tools = tools_interactive(
      callback = make_handler("agent-a"),
      context = list(agent_id = "agent-a", session_id = "session-a")
    ),
    agent_id = "agent-a",
    session_id = "session-a"
  )
  agent_b <- Agent$new(
    chat = chat_b,
    tools = tools_interactive(
      callback = make_handler("agent-b"),
      context = list(agent_id = "agent-b", session_id = "session-b")
    ),
    agent_id = "agent-b",
    session_id = "session-b"
  )

  result_a <- chat_a$get_tools()[["ask_user"]](interaction_test_questions())
  result_b <- chat_b$get_tools()[["ask_user"]](interaction_test_questions())

  expect_s3_class(agent_a, "Agent")
  expect_s3_class(agent_b, "Agent")
  expect_identical(interaction_answer(result_a)$other_text, "agent-a")
  expect_identical(interaction_answer(result_b)$other_text, "agent-b")
  expect_identical(seen[["agent-a"]]$session_id, "session-a")
  expect_identical(seen[["agent-b"]]$session_id, "session-b")
})

test_that("per-tool handler takes precedence over the legacy global fallback", {
  set_ask_user_callback(function(questions) {
    stats::setNames(list("global"), questions[[1]]$question)
  })
  withr::defer(set_ask_user_callback(NULL))

  tool <- tools_interactive(
    callback = function(questions, context) {
      stats::setNames(list(context$route), questions[[1]]$question)
    },
    context = list(route = "instance")
  )[[1]]
  result <- tool(interaction_test_questions())

  expect_identical(interaction_answer(result)$other_text, "instance")
})

test_that("tools_interactive resolves dynamic context for each request", {
  current_run <- "run-one"
  seen <- character()
  tool <- tools_interactive(
    callback = function(questions, context) {
      seen <<- c(seen, context$run_id)
      stats::setNames(list(context$run_id), questions[[1]]$question)
    },
    context = function() list(run_id = current_run)
  )[[1]]

  first <- tool(interaction_test_questions())
  current_run <- "run-two"
  second <- tool(interaction_test_questions())

  expect_identical(interaction_answer(first)$other_text, "run-one")
  expect_identical(interaction_answer(second)$other_text, "run-two")
  expect_identical(seen, c("run-one", "run-two"))
})

test_that("tools_interactive validates handler dependencies", {
  callback_condition <- rlang::catch_cnd(
    tools_interactive(callback = "not a function")
  )
  context_condition <- rlang::catch_cnd(
    tools_interactive(
      callback = function(questions, context) list(),
      context = "route"
    )
  )

  expect_s3_class(callback_condition, "error")
  expect_match(conditionMessage(callback_condition), "callback", fixed = TRUE)
  expect_s3_class(context_condition, "error")
  expect_match(conditionMessage(context_condition), "context", fixed = TRUE)
})

test_that("missing non-interactive handler is a structured Deputy error", {
  set_ask_user_callback(NULL)
  skip_if(interactive(), "Test requires non-interactive session")
  tool <- tools_interactive()[[1]]

  condition <- rlang::catch_cnd(tool(interaction_test_questions()))

  expect_s3_class(condition, "deputy_human_input_unavailable")
  expect_s3_class(condition, "deputy_error")
  expect_match(conditionMessage(condition), "handler", fixed = TRUE)
})

test_that("set_ask_user_callback validates input", {
  # Should accept NULL
  expect_no_error(set_ask_user_callback(NULL))

  # Should accept function (new signature: just questions)
  expect_no_error(set_ask_user_callback(function(questions) list()))

  # Should reject non-function
  expect_error(
    set_ask_user_callback("not a function"),
    "must be a function"
  )

  # Clean up
  set_ask_user_callback(NULL)
})

test_that("set_ask_user_callback returns previous value", {
  # Start clean
  set_ask_user_callback(NULL)

  # Set a callback (new signature: just questions, returns answers list)
  cb1 <- function(questions) list()
  old <- set_ask_user_callback(cb1)
  expect_null(old)

  # Set another callback
  cb2 <- function(questions) list()
  old <- set_ask_user_callback(cb2)
  expect_true(is.function(old))

  # Clean up
  set_ask_user_callback(NULL)
})

test_that("get_ask_user_callback returns current callback", {
  # Start clean
  set_ask_user_callback(NULL)
  expect_null(get_ask_user_callback())

  # Set a callback (new signature)
  cb <- function(questions) list()
  set_ask_user_callback(cb)
  expect_true(is.function(get_ask_user_callback()))

  # Clean up
  set_ask_user_callback(NULL)
})

test_that("ask_user_impl uses callback when set", {
  # Set up a mock callback that captures the questions and returns answers
  captured_questions <- NULL
  mock_callback <- function(questions) {
    captured_questions <<- questions
    # Return answers mapping question text to selected label
    answers <- list()
    for (q in questions) {
      answers[[q$question]] <- q$options[[1]]$label
    }
    answers
  }

  set_ask_user_callback(mock_callback)
  withr::defer(set_ask_user_callback(NULL))

  # Create a test question in the new format
  test_questions <- list(
    list(
      question = "What format do you prefer?",
      header = "Format",
      options = list(
        list(label = "JSON", description = "JavaScript Object Notation"),
        list(label = "YAML", description = "YAML Ain't Markup Language")
      ),
      multiSelect = FALSE
    )
  )

  # Call the implementation
  result <- ask_user_impl(test_questions)

  # Verify callback was called with correct args
  expect_equal(length(captured_questions), 1)
  expect_equal(captured_questions[[1]]$question, "What format do you prefer?")
  expect_equal(captured_questions[[1]]$header, "Format")
  expect_equal(length(captured_questions[[1]]$options), 2)

  # Verify result has the expected structure
  expect_true(is.list(result))
  expect_equal(result[["What format do you prefer?"]], "JSON")
})

test_that("ask_user_impl reports missing non-interactive handler", {
  # Ensure no callback is set
  set_ask_user_callback(NULL)

  # Skip if we're actually in an interactive session
  skip_if(interactive(), "Test requires non-interactive session")

  test_questions <- list(
    list(
      question = "Test?",
      header = "Test",
      options = list(
        list(label = "A", description = "Option A"),
        list(label = "B", description = "Option B")
      )
    )
  )

  condition <- rlang::catch_cnd(ask_user_impl(test_questions))

  expect_s3_class(condition, "deputy_human_input_unavailable")
  expect_match(conditionMessage(condition), "handler", fixed = TRUE)
})

test_that("tool_ask_user answers through the process-wide callback", {
  captured <- NULL
  set_ask_user_callback(function(questions) {
    captured <<- questions
    list("Which format?" = "YAML")
  })
  withr::defer(set_ask_user_callback(NULL))

  questions <- interaction_test_questions()
  questions[[1]]$multiSelect <- NULL
  result <- tool_ask_user(questions)

  # The handler receives every field, with multiSelect filled in.
  expect_identical(captured, interaction_test_questions())
  expect_identical(
    interaction_model_view(result),
    list(
      questions = list(list(
        question = "Which format?",
        header = "Format",
        options = list(
          list(label = "JSON", description = "Structured JSON"),
          list(label = "YAML", description = "Readable YAML")
        ),
        multiSelect = FALSE
      )),
      answers = list(list(
        question = "Which format?",
        selected = list("YAML"),
        other_text = NULL
      ))
    )
  )
})

test_that("the process-wide callback's answers are checked like any handler's", {
  set_ask_user_callback(function(questions) list("Which format" = "JSON"))
  withr::defer(set_ask_user_callback(NULL))

  condition <- rlang::catch_cnd(tool_ask_user(interaction_test_questions()))

  expect_s3_class(condition, "ellmer_tool_reject")
  expect_match(
    conditionMessage(condition),
    "answered \"Which format\", which isn't one of the questions asked",
    fixed = TRUE
  )
})

test_that("tool_ask_user validates the questions array", {
  expect_questions_rejected(list(), "questions must be a non-empty array")
  expect_questions_rejected(
    42,
    "questions must be an array of 1 to 4 question objects"
  )
  expect_questions_rejected(
    TRUE,
    "questions must be an array of 1 to 4 question objects"
  )
  expect_questions_rejected(
    interaction_test_questions()[[1]],
    "put a single question inside an array"
  )

  too_many <- lapply(1:5, function(i) {
    question <- interaction_test_questions()[[1]]
    question$question <- paste("Question", i)
    question
  })
  expect_questions_rejected(
    too_many,
    "Maximum 4 questions allowed per call; got 5."
  )
  expect_questions_rejected(
    list("Which format?"),
    "Question 1 must be an object with 'question', 'header' and 'options'."
  )
})

test_that("tool_ask_user requires each text field to be one non-empty string", {
  expect_questions_rejected(
    interaction_question_with(question = NULL),
    "Question 1 is missing 'question'."
  )
  expect_questions_rejected(
    interaction_question_with(header = NULL),
    "Question 1 is missing 'header'."
  )
  for (bad in list(NA_character_, "", "  ", c("A?", "B?"), 1, list("A?"))) {
    expect_questions_rejected(
      interaction_question_with(question = bad),
      "Question 1 'question' must be one non-empty string."
    )
  }
  # An empty header once failed outside the tool's own checks.
  for (bad in list(character(0), NA_character_, TRUE)) {
    expect_questions_rejected(
      interaction_question_with(header = bad),
      "Question 1 'header' must be one non-empty string."
    )
  }
  expect_questions_rejected(
    interaction_question_with(header = "This header is way too long"),
    "Question 1 'header' has 27 characters; use at most 12."
  )
})

test_that("tool_ask_user reads fields by their exact names", {
  question <- interaction_test_questions()[[1]]
  names(question)[names(question) == "question"] <- "questionText"

  expect_questions_rejected(
    list(question),
    "Question 1 is missing 'question'."
  )
})

test_that("tool_ask_user validates the options of each question", {
  options <- interaction_test_questions()[[1]]$options
  expect_questions_rejected(
    interaction_question_with(options = NULL),
    "Question 1 is missing 'options'."
  )
  expect_questions_rejected(
    interaction_question_with(options = "JSON"),
    "Question 1 'options' must be an array of 2-4 options."
  )
  expect_questions_rejected(
    interaction_question_with(
      options = list(first = options[[1]], second = options[[2]])
    ),
    "Question 1 'options' must be an array of 2-4 options."
  )
  expect_questions_rejected(
    interaction_question_with(options = options[1]),
    "Question 1 must have 2-4 options; got 1."
  )
  expect_questions_rejected(
    interaction_question_with(options = rep(options, 3)),
    "Question 1 must have 2-4 options; got 6."
  )
  expect_questions_rejected(
    interaction_question_with(options = list("JSON", "YAML")),
    "Question 1 option 1 must be an object with 'label' and 'description'."
  )
  expect_questions_rejected(
    interaction_question_with(
      options = list(list(description = "A"), options[[2]])
    ),
    "Question 1 option 1 is missing 'label'."
  )
  expect_questions_rejected(
    interaction_question_with(options = list(options[[1]], list(label = "B"))),
    "Question 1 option 2 is missing 'description'."
  )
  expect_questions_rejected(
    interaction_question_with(
      options = list(options[[1]], list(label = NA, description = "B"))
    ),
    "Question 1 option 2 'label' must be one non-empty string."
  )
  expect_questions_rejected(
    interaction_question_with(
      options = list(options[[1]], list(label = "B", description = ""))
    ),
    "Question 1 option 2 'description' must be one non-empty string."
  )
})

test_that("tool_ask_user rejects repeated option labels and questions", {
  expect_questions_rejected(
    interaction_question_with(
      options = list(
        list(label = "JSON", description = "One"),
        list(label = "JSON", description = "Two")
      )
    ),
    "Question 1 has the option label \"JSON\" more than once"
  )
  expect_questions_rejected(
    c(interaction_test_questions(), interaction_test_questions()),
    "Each question must be different; \"Which format?\" is asked more than once."
  )
})

test_that("tool_ask_user requires multiSelect to be true or false", {
  for (bad in list("yes", NA, c(TRUE, FALSE), 1)) {
    expect_questions_rejected(
      interaction_question_with(multiSelect = bad),
      "Question 1 'multiSelect' must be true or false."
    )
  }
})

test_that("answers keep labels apart and pass the person's own text", {
  tool <- interaction_answering_tool(list(
    "Which outputs?" = c("Text", "Tables, charts", "Maps"),
    "Which format?" = c("YAML", "")
  ))

  result <- tool(interaction_shape_questions())
  view <- interaction_model_view(result)

  expect_identical(
    view$answers,
    list(
      list(
        question = "Which outputs?",
        selected = list("Tables, charts", "Text"),
        other_text = "Maps"
      ),
      list(
        question = "Which format?",
        selected = list("YAML"),
        other_text = NULL
      ),
      list(question = "Anything else?", selected = list(), other_text = NULL)
    )
  )
  expect_length(view$questions, 3L)
  # One label is still an array, and an empty other_text is null.
  expect_match(
    result,
    "\"selected\":[\"YAML\"],\"other_text\":null",
    fixed = TRUE
  )
  expect_match(result, "\"selected\":[],\"other_text\":null", fixed = TRUE)
})

test_that("padding around a chosen label doesn't make it typed text", {
  result <- interaction_answering_tool(list(
    "Which outputs?" = c(" Text", "Slides  ", " Maps "),
    "Which format?" = "YAML\n"
  ))(interaction_shape_questions())

  expect_identical(
    interaction_answer(result, 1L),
    list(
      question = "Which outputs?",
      selected = list("Text", "Slides"),
      other_text = "Maps"
    )
  )
  expect_identical(interaction_answer(result, 2L)$selected, list("YAML"))
})

test_that("labels are trimmed, so padded copies of one label are rejected", {
  expect_questions_rejected(
    interaction_question_with(
      options = list(
        list(label = "JSON", description = "Structured JSON"),
        list(label = " JSON ", description = "The same, padded")
      )
    ),
    "more than once"
  )

  seen <- NULL
  tool <- tools_interactive(callback = function(questions, context) {
    seen <<- questions[[1]]$options[[2]]$label
    list("Which format?" = "YAML")
  })[[1]]
  result <- tool(interaction_question_with(
    options = list(
      list(label = "JSON", description = "Structured JSON"),
      list(label = " YAML ", description = "Readable YAML")
    )
  ))
  expect_identical(seen, "YAML")
  expect_identical(interaction_answer(result)$selected, list("YAML"))
})

test_that("the person's own text can take the place of a single label", {
  result <- interaction_answering_tool(list("Which format?" = "TOML"))(
    interaction_shape_questions()
  )

  expect_identical(
    interaction_answer(result, 2L),
    list(question = "Which format?", selected = list(), other_text = "TOML")
  )
})

test_that("labels joined into one string reach the model as typed text", {
  result <- interaction_answering_tool(list(
    "Which outputs?" = "Text, Slides"
  ))(interaction_shape_questions())

  expect_identical(
    interaction_answer(result, 1L),
    list(
      question = "Which outputs?",
      selected = list(),
      other_text = "Text, Slides"
    )
  )
})

test_that("handler answers in the wrong shape become tool rejections", {
  expect_answers_rejected(
    c("Which format?" = "JSON"),
    "The handler must return a named list"
  )
  expect_answers_rejected(
    list("JSON"),
    "The handler must name each answer with its question's text."
  )
  expect_answers_rejected(
    list("Which format" = "JSON"),
    "The handler answered \"Which format\", which isn't one of the questions asked."
  )
  expect_answers_rejected(
    list("Which format?" = "JSON", "Which format?" = "YAML"),
    "The handler answered \"Which format?\" more than once."
  )
  for (bad in list(1, NULL, list("JSON"), factor("JSON"))) {
    expect_answers_rejected(
      list("Which format?" = bad),
      "The handler's answer to \"Which format?\" must be a character vector"
    )
  }
  expect_answers_rejected(
    list("Which format?" = NA_character_),
    "The handler's answer to \"Which format?\" contains NA."
  )
  expect_answers_rejected(
    list("Which outputs?" = c("Text", "Maps", "Graphs")),
    "The handler gave 2 answers to \"Which outputs?\" that aren't option labels"
  )
  expect_answers_rejected(
    list("Which format?" = c("JSON", "YAML")),
    "\"Which format?\" takes one answer, but the handler gave 2."
  )
  expect_answers_rejected(
    list("Which format?" = c("JSON", "my own")),
    "\"Which format?\" takes one answer, but the handler gave 2."
  )
})

test_that("parse_user_response handles single selection", {
  options <- list(
    list(label = "JSON", description = "JavaScript Object Notation"),
    list(label = "YAML", description = "YAML Ain't Markup Language")
  )

  # Numeric selection
  expect_identical(parse_user_response("1", options, FALSE), "JSON")
  expect_identical(parse_user_response(" 2 ", options, FALSE), "YAML")

  # Free text response
  expect_identical(
    parse_user_response("custom answer", options, FALSE),
    "custom answer"
  )
  # Two numbers for one choice are asked again.
  expect_null(parse_user_response("1,2", options, FALSE))
})

test_that("parse_user_response returns each multi-selected label", {
  options <- list(
    list(label = "Tables, charts", description = "Option A"),
    list(label = "B", description = "Option B"),
    list(label = "C", description = "Option C")
  )

  expect_identical(
    parse_user_response("1,2", options, TRUE),
    c("Tables, charts", "B")
  )
  expect_identical(
    parse_user_response("3, 1", options, TRUE),
    c("C", "Tables, charts")
  )
  expect_identical(parse_user_response("2,2", options, TRUE), "B")
  expect_identical(parse_user_response("2", options, TRUE), "B")

  # Free text still works
  expect_identical(
    parse_user_response("all of them", options, TRUE),
    "all of them"
  )
  expect_identical(parse_user_response("1 and 2", options, TRUE), "1 and 2")
})

test_that("tool_ask_user rejects a string, including a path or URL, unread", {
  asked <- FALSE
  set_ask_user_callback(function(questions) {
    asked <<- TRUE
    list("Which format?" = "JSON")
  })
  withr::defer(set_ask_user_callback(NULL))
  json <- as.character(jsonlite::toJSON(
    interaction_test_questions(),
    auto_unbox = TRUE
  ))
  saved <- withr::local_tempfile(fileext = ".json")
  writeLines(json, saved)
  texts <- list(
    json,
    "[]",
    "{ invalid json }",
    saved,
    "http://127.0.0.1:9/questions.json",
    NA_character_,
    c(json, json)
  )

  for (text in texts) {
    condition <- rlang::catch_cnd(tool_ask_user(text), "error")
    expect_s3_class(condition, "ellmer_tool_reject")
    expect_match(
      conditionMessage(condition),
      paste(
        "questions must be an array of question objects, not a string;",
        "send the array itself rather than JSON text."
      ),
      fixed = TRUE
    )
  }
  expect_false(asked)
})

# Callback error propagation tests
test_that("tool_ask_user handles callback errors gracefully", {
  set_ask_user_callback(function(questions) {
    stop("Callback error: modal cancelled")
  })
  withr::defer(set_ask_user_callback(NULL))

  expect_error(
    tool_ask_user(interaction_test_questions()),
    "Failed to get user input.*Callback error"
  )
})

# Edge case tests for parse_user_response
test_that("parse_user_response asks again for numbers that aren't options", {
  options <- list(
    list(label = "A", description = "Option A"),
    list(label = "B", description = "Option B")
  )

  for (response in c("5", "0", "-1", "1.5", "+1", "1,2")) {
    expect_null(parse_user_response(response, options, FALSE))
  }
  # Nothing is dropped or truncated from a multi-select answer.
  for (response in c("1,5", "1,9", "5,6", "1.5", "1,,2", "1, 2.0", "1 2")) {
    expect_null(parse_user_response(response, options, TRUE))
  }
})

# Multiple questions workflow test
test_that("tool_ask_user answers every question in order", {
  captured <- NULL
  set_ask_user_callback(function(questions) {
    captured <<- questions
    list(
      "Second question?" = "Option X",
      "First question?" = "Option A"
    )
  })
  withr::defer(set_ask_user_callback(NULL))

  questions <- list(
    list(
      question = "First question?",
      header = "Q1",
      options = list(
        list(label = "Option A", description = "First option"),
        list(label = "Option B", description = "Second option")
      )
    ),
    list(
      question = "Second question?",
      header = "Q2",
      options = list(
        list(label = "Option X", description = "X option"),
        list(label = "Option Y", description = "Y option")
      )
    )
  )

  result <- tool_ask_user(questions)
  view <- interaction_model_view(result)

  expect_equal(length(captured), 2)
  expect_identical(
    vapply(view$answers, function(answer) answer$question, character(1)),
    c("First question?", "Second question?")
  )
  expect_identical(view$answers[[1]]$selected, list("Option A"))
  expect_identical(view$answers[[2]]$selected, list("Option X"))
  expect_equal(length(view$questions), 2)
})

test_that("the model receives typed answers through an Agent", {
  questions <- interaction_shape_questions()
  server <- local_runtime_server(list(
    runtime_tool_calls_reply(list(
      list(
        id = "call_shapes",
        name = "ask_user",
        arguments = list(questions = questions)
      ),
      list(
        id = "call_format",
        name = "ask_user",
        arguments = list(questions = interaction_test_questions())
      )
    )),
    runtime_reply("done")
  ))
  seen <- list()
  agent <- Agent$new(
    runtime_chat(server),
    tools = tools_interactive(function(questions, context) {
      seen[[length(seen) + 1L]] <<- questions
      if (length(questions) == 1L) {
        return(list("Which format?" = "JSON"))
      }
      list("Which outputs?" = c("Tables, charts", "Slides", "Maps"))
    })
  )

  result <- agent$run_sync("Ask me")

  expect_identical(trimws(result$response), "done")
  # Provider arrays arrive as lists, with multiSelect filled in.
  expect_identical(seen[[1]], questions)
  expect_identical(seen[[2]], interaction_test_questions())
  sent <- sent_tool_results(server, 2L)
  expect_length(sent, 2L)
  expect_identical(
    jsonlite::parse_json(sent[[1]])$answers,
    list(
      list(
        question = "Which outputs?",
        selected = list("Tables, charts", "Slides"),
        other_text = "Maps"
      ),
      list(question = "Which format?", selected = list(), other_text = NULL),
      list(question = "Anything else?", selected = list(), other_text = NULL)
    )
  )
  expect_match(
    sent[[2]],
    "\"answers\":[{\"question\":\"Which format?\",\"selected\":[\"JSON\"],\"other_text\":null}]",
    fixed = TRUE
  )
})

test_that("a model that sends invalid questions is told what to fix", {
  text <- as.character(jsonlite::toJSON(
    interaction_test_questions(),
    auto_unbox = TRUE
  ))
  server <- local_runtime_server(list(
    runtime_tool_calls_reply(list(
      list(
        id = "call_text",
        name = "ask_user",
        arguments = list(questions = text)
      ),
      list(
        id = "call_header",
        name = "ask_user",
        arguments = list(questions = interaction_question_with(header = ""))
      )
    )),
    runtime_reply("done")
  ))
  agent <- Agent$new(
    runtime_chat(server),
    tools = tools_interactive(function(questions, context) {
      stop("The handler must not run")
    })
  )

  expect_warning(agent$run_sync("Ask me"), "Failed to evaluate")

  sent <- sent_tool_results(server, 2L)
  expect_length(sent, 2L)
  expect_match(
    sent[[1]],
    "questions must be an array of question objects, not a string;",
    fixed = TRUE
  )
  expect_match(
    sent[[2]],
    "Question 1 'header' must be one non-empty string.",
    fixed = TRUE
  )
  expect_no_match(paste(sent, collapse = "\n"), "must not run", fixed = TRUE)
})

test_that("AskUserDeferred is a read-only value with default instructions", {
  deferred <- AskUserDeferred()

  expect_true(S7::S7_inherits(deferred, AskUserDeferred))
  expect_match(deferred@instructions, "next message", fixed = TRUE)
  expect_identical(deferred@extra, list())
  expect_error(deferred@instructions <- "x", "read-only")
  expect_error(AskUserDeferred(instructions = NA_character_), "instructions")
  expect_error(AskUserDeferred(extra = list(1)), "named list")
})

test_that("a deferred handler returns the questions without answers", {
  seen <- NULL
  tool <- tools_interactive(
    callback = function(questions, context) {
      seen <<- questions
      AskUserDeferred(instructions = "Wait for the reply.")
    }
  )[[1]]

  result <- tool(interaction_test_questions())

  expect_identical(seen, interaction_test_questions())
  expect_identical(result$status, "deferred")
  expect_identical(result$instructions, "Wait for the reply.")
  expect_identical(result$questions, interaction_test_questions())
  expect_null(result$answers)
})

test_that("a deferred handler can attach a host display", {
  display <- list(display = list(title = "Questions for you"))
  tool <- tools_interactive(
    callback = function(questions, context) AskUserDeferred(extra = display)
  )[[1]]

  result <- tool(interaction_test_questions())

  expect_true(S7::S7_inherits(result, ellmer::ContentToolResult))
  expect_identical(result@extra, display)
  expect_identical(result@value$status, "deferred")
})

test_that("a promise handler resolves to structured answers", {
  tool <- tools_interactive(
    callback = function(questions, context) {
      promises::promise_resolve(
        stats::setNames(list("YAML"), questions[[1]]$question)
      )
    }
  )[[1]]

  result <- resolve_async_value(tool(interaction_test_questions()))

  expect_identical(
    interaction_model_view(result),
    list(
      questions = interaction_test_questions(),
      answers = list(list(
        question = "Which format?",
        selected = list("YAML"),
        other_text = NULL
      ))
    )
  )
})

test_that("a promise for answers in the wrong shape becomes a tool rejection", {
  tool <- tools_interactive(
    callback = function(questions, context) {
      promises::promise_resolve(list("Which format?" = 2))
    }
  )[[1]]

  failure <- NULL
  promises::catch(tool(interaction_test_questions()), function(e) {
    failure <<- e
  })
  while (is.null(failure)) {
    later::run_now(0.01)
  }

  expect_s3_class(failure, "ellmer_tool_reject")
  expect_match(
    conditionMessage(failure),
    "Failed to get user input: The handler's answer to \"Which format?\" must be a character vector",
    fixed = TRUE
  )
})

test_that("a rejected promise handler becomes a tool rejection", {
  tool <- tools_interactive(
    callback = function(questions, context) {
      promises::promise_reject(simpleError("dialog closed"))
    }
  )[[1]]

  failure <- NULL
  promises::catch(tool(interaction_test_questions()), function(e) {
    failure <<- e
  })
  while (is.null(failure)) {
    later::run_now(0.01)
  }

  expect_s3_class(failure, "ellmer_tool_reject")
  expect_match(
    conditionMessage(failure),
    "Failed to get user input: dialog closed"
  )
})

test_that("delegated handlers cannot defer answers to a later turn", {
  tool <- new_ask_user_tool(
    callback = function(questions, context) AskUserDeferred(),
    allow_deferred = FALSE
  )

  expect_error(
    tool(interaction_test_questions()),
    class = "deputy_human_input_unavailable"
  )
  failure <- NULL
  promised <- new_ask_user_tool(
    callback = function(questions, context) {
      promises::promise_resolve(AskUserDeferred())
    },
    allow_deferred = FALSE
  )
  promises::catch(promised(interaction_test_questions()), function(e) {
    failure <<- e
  })
  while (is.null(failure)) {
    later::run_now(0.01)
  }
  expect_s3_class(failure, "deputy_human_input_unavailable")
})

test_that("a subagent's model receives typed answers from human_input", {
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "ask_user",
      arguments = list(questions = interaction_shape_questions())
    ),
    runtime_reply("done")
  ))
  routed <- NULL
  lead <- LeadAgent$new(
    runtime_chat(server),
    sub_agents = list(agent_definition(
      "a",
      "A",
      "worker",
      tools = tools_interactive(function(...) {
        stop("stale handler must not run")
      })
    )),
    delegation_policy = DelegationPolicy(human_input = function(
      questions,
      context
    ) {
      routed <<- questions
      promises::promise_resolve(list(
        "Which outputs?" = c("Tables, charts", "Text"),
        "Which format?" = "my own"
      ))
    })
  )

  suppressMessages(resolve_async_value(
    lead$get_tools()$delegate_to_agent("a", "Ask the user"),
    max_polls = 10000L
  ))

  expect_identical(routed, interaction_shape_questions())
  sent <- sent_tool_results(server, 2L)
  expect_identical(
    jsonlite::parse_json(sent)$answers,
    list(
      list(
        question = "Which outputs?",
        selected = list("Tables, charts", "Text"),
        other_text = NULL
      ),
      list(
        question = "Which format?",
        selected = list(),
        other_text = "my own"
      ),
      list(question = "Anything else?", selected = list(), other_text = NULL)
    )
  )
  expect_match(
    sent,
    "\"selected\":[\"Tables, charts\",\"Text\"],\"other_text\":null",
    fixed = TRUE
  )
})

test_that("a subagent's model is told when human_input answers are malformed", {
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "ask_user",
      arguments = list(questions = interaction_test_questions())
    ),
    runtime_reply("done")
  ))
  lead <- LeadAgent$new(
    runtime_chat(server),
    sub_agents = list(agent_definition(
      "a",
      "A",
      "worker",
      tools = tools_interactive()
    )),
    delegation_policy = DelegationPolicy(
      human_input = function(questions, context) list(`Which format?` = 1)
    )
  )

  expect_warning(
    suppressMessages(resolve_async_value(
      lead$get_tools()$delegate_to_agent("a", "Ask the user"),
      max_polls = 10000L
    )),
    "Failed to evaluate"
  )

  expect_match(
    sent_tool_results(server, 2L),
    "Failed to get user input: The handler's answer to \"Which format?\" must be a character vector, not numeric.",
    fixed = TRUE
  )
})
