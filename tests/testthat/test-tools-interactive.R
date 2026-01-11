# Tests for interactive tools

test_that("tool_ask_user has correct structure", {
  expect_true(inherits(tool_ask_user, "ellmer::ToolDef"))

  # Check name - matches Anthropic SDK naming

  expect_equal(tool_ask_user@name, "AskUserQuestion")

  # Check it has the right annotations
  annotations <- tool_ask_user@annotations
  expect_true(annotations$read_only_hint)
  expect_false(annotations$destructive_hint)
})

test_that("tools_interactive returns tool list", {
  tools <- tools_interactive()
  expect_true(is.list(tools))
  expect_true(length(tools) >= 1)

  # Should include AskUserQuestion
  tool_names <- vapply(tools, function(t) t@name, character(1))
  expect_true("AskUserQuestion" %in% tool_names)
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

test_that("ask_user_impl errors in non-interactive without callback", {
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

  expect_error(
    ask_user_impl(test_questions),
    "not interactive"
  )
})

test_that("tool_ask_user works with callback", {
  # Set up callback that returns answers in the expected format
  set_ask_user_callback(function(questions) {
    answers <- list()
    for (q in questions) {
      answers[[q$question]] <- "Selected option"
    }
    answers
  })
  withr::defer(set_ask_user_callback(NULL))

  # Create questions in the new format
  test_questions <- list(
    list(
      question = "What do you prefer?",
      header = "Preference",
      options = list(
        list(label = "Option A", description = "First option"),
        list(label = "Option B", description = "Second option")
      ),
      multiSelect = FALSE
    )
  )

  # Tools are directly callable (inherit from function)
  result <- tool_ask_user(test_questions)

  # Result should have questions and answers
  expect_true(is.list(result))
  expect_true("questions" %in% names(result))
  expect_true("answers" %in% names(result))
  expect_equal(result$answers[["What do you prefer?"]], "Selected option")
})

test_that("tool_ask_user validates questions array", {
  set_ask_user_callback(function(questions) list())
  withr::defer(set_ask_user_callback(NULL))

  # Empty questions should be rejected
  expect_error(
    tool_ask_user(list()),
    "non-empty array"
  )

  # Too many questions should be rejected (max 4)
  too_many <- lapply(1:5, function(i) {
    list(
      question = paste("Question", i),
      header = paste0("Q", i),
      options = list(
        list(label = "A", description = "Option A"),
        list(label = "B", description = "Option B")
      )
    )
  })
  expect_error(
    tool_ask_user(too_many),
    "Maximum 4 questions"
  )
})

test_that("tool_ask_user validates question structure", {
  set_ask_user_callback(function(questions) list())
  withr::defer(set_ask_user_callback(NULL))

  # Missing question field
  expect_error(
    tool_ask_user(list(list(
      header = "H",
      options = list(
        list(label = "A", description = "A"),
        list(label = "B", description = "B")
      )
    ))),
    "missing 'question'"
  )

  # Missing header field
  expect_error(
    tool_ask_user(list(list(
      question = "Q?",
      options = list(
        list(label = "A", description = "A"),
        list(label = "B", description = "B")
      )
    ))),
    "missing 'header'"
  )

  # Header too long (max 12 chars)
  expect_error(
    tool_ask_user(list(list(
      question = "Q?",
      header = "This header is way too long",
      options = list(
        list(label = "A", description = "A"),
        list(label = "B", description = "B")
      )
    ))),
    "exceeds 12 characters"
  )

  # Missing options
  expect_error(
    tool_ask_user(list(list(question = "Q?", header = "H"))),
    "missing 'options'"
  )
})

test_that("tool_ask_user validates options count", {
  set_ask_user_callback(function(questions) list())
  withr::defer(set_ask_user_callback(NULL))

  # Too few options (need at least 2)
  expect_error(
    tool_ask_user(list(list(
      question = "Q?",
      header = "H",
      options = list(list(label = "A", description = "A"))
    ))),
    "must have 2-4 options"
  )

  # Too many options (max 4)
  expect_error(
    tool_ask_user(list(list(
      question = "Q?",
      header = "H",
      options = list(
        list(label = "A", description = "A"),
        list(label = "B", description = "B"),
        list(label = "C", description = "C"),
        list(label = "D", description = "D"),
        list(label = "E", description = "E")
      )
    ))),
    "must have 2-4 options"
  )
})

test_that("tool_ask_user validates option structure", {
  set_ask_user_callback(function(questions) list())
  withr::defer(set_ask_user_callback(NULL))

  # Option missing label
  expect_error(
    tool_ask_user(list(list(
      question = "Q?",
      header = "H",
      options = list(
        list(description = "A"),
        list(label = "B", description = "B")
      )
    ))),
    "must have 'label' and 'description'"
  )

  # Option missing description
  expect_error(
    tool_ask_user(list(list(
      question = "Q?",
      header = "H",
      options = list(
        list(label = "A"),
        list(label = "B", description = "B")
      )
    ))),
    "must have 'label' and 'description'"
  )
})

test_that("parse_user_response handles single selection", {
  options <- list(
    list(label = "JSON", description = "JavaScript Object Notation"),
    list(label = "YAML", description = "YAML Ain't Markup Language")
  )

  # Numeric selection
  expect_equal(parse_user_response("1", options, FALSE), "JSON")
  expect_equal(parse_user_response("2", options, FALSE), "YAML")

  # Free text response
  expect_equal(
    parse_user_response("custom answer", options, FALSE),
    "custom answer"
  )
})

test_that("parse_user_response handles multi-selection", {
  options <- list(
    list(label = "A", description = "Option A"),
    list(label = "B", description = "Option B"),
    list(label = "C", description = "Option C")
  )

  # Multiple numeric selections
  expect_equal(parse_user_response("1,2", options, TRUE), "A, B")
  expect_equal(parse_user_response("1, 3", options, TRUE), "A, C")

  # Free text still works
  expect_equal(parse_user_response("all of them", options, TRUE), "all of them")
})

# JSON string input tests (critical for LLM integration)
test_that("tool_ask_user handles valid JSON string input", {
  set_ask_user_callback(function(questions) {
    list("What format?" = "JSON")
  })
  withr::defer(set_ask_user_callback(NULL))

  json_input <- '[{"question": "What format?", "header": "Format", "options": [{"label": "JSON", "description": "JS Object Notation"}, {"label": "YAML", "description": "YAML format"}]}]'

  result <- tool_ask_user(json_input)
  expect_equal(result$answers[["What format?"]], "JSON")
  expect_true("questions" %in% names(result))
})

test_that("tool_ask_user rejects malformed JSON", {
  set_ask_user_callback(function(questions) list())
  withr::defer(set_ask_user_callback(NULL))

  expect_error(
    tool_ask_user("{ invalid json }"),
    "Failed to parse questions JSON"
  )
})

test_that("tool_ask_user rejects empty JSON array", {
  set_ask_user_callback(function(questions) list())
  withr::defer(set_ask_user_callback(NULL))

  expect_error(
    tool_ask_user("[]"),
    "non-empty array"
  )
})

# Callback error propagation tests
test_that("tool_ask_user handles callback errors gracefully", {
  set_ask_user_callback(function(questions) {
    stop("Callback error: modal cancelled")
  })
  withr::defer(set_ask_user_callback(NULL))

  test_questions <- list(list(
    question = "Q?",
    header = "H",
    options = list(
      list(label = "A", description = "A"),
      list(label = "B", description = "B")
    )
  ))

  expect_error(
    tool_ask_user(test_questions),
    "Failed to get user input.*Callback error"
  )
})

# Edge case tests for parse_user_response
test_that("parse_user_response handles out-of-range indices", {
  options <- list(
    list(label = "A", description = "Option A"),
    list(label = "B", description = "Option B")
  )

  # Out-of-range falls back to free text
  expect_equal(parse_user_response("5", options, FALSE), "5")
  expect_equal(parse_user_response("0", options, FALSE), "0")
  expect_equal(parse_user_response("-1", options, FALSE), "-1")
})

test_that("parse_user_response handles mixed valid/invalid multi-select", {
  options <- list(
    list(label = "A", description = "Option A"),
    list(label = "B", description = "Option B")
  )

  # "1,5" - 5 is invalid, only valid indices are used
  expect_equal(parse_user_response("1,5", options, TRUE), "A")

  # All invalid falls back to free text
  expect_equal(parse_user_response("5,6", options, TRUE), "5,6")
})

# Multiple questions workflow test
test_that("tool_ask_user handles multiple questions", {
  captured <- NULL
  set_ask_user_callback(function(questions) {
    captured <<- questions
    list(
      "First question?" = "Option A",
      "Second question?" = "Option X"
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

  # Verify callback received both questions
  expect_equal(length(captured), 2)

  # Verify both answers are in result
  expect_equal(result$answers[["First question?"]], "Option A")
  expect_equal(result$answers[["Second question?"]], "Option X")

  # Verify questions are echoed back
  expect_equal(length(result$questions), 2)
})
