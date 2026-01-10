# Tests for interactive tools

test_that("tool_ask_user has correct structure", {
  expect_true(inherits(tool_ask_user, "ellmer::ToolDef"))

  # Check name
  expect_equal(tool_ask_user@name, "ask_user")

  # Check it has the right annotations
  annotations <- tool_ask_user@annotations
  expect_true(annotations$read_only_hint)
  expect_false(annotations$destructive_hint)
})

test_that("tools_interactive returns tool list", {
  tools <- tools_interactive()
  expect_true(is.list(tools))
  expect_true(length(tools) >= 1)

  # Should include ask_user
  tool_names <- vapply(tools, function(t) t@name, character(1))
  expect_true("ask_user" %in% tool_names)
})

test_that("set_ask_user_callback validates input", {
  # Should accept NULL
  expect_no_error(set_ask_user_callback(NULL))

  # Should accept function
  expect_no_error(set_ask_user_callback(function(q, c, t) "test"))

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

  # Set a callback
  cb1 <- function(q, c, t) "response1"
  old <- set_ask_user_callback(cb1)
  expect_null(old)

  # Set another callback
  cb2 <- function(q, c, t) "response2"
  old <- set_ask_user_callback(cb2)
  expect_true(is.function(old))

  # Clean up
  set_ask_user_callback(NULL)
})

test_that("get_ask_user_callback returns current callback", {
  # Start clean
  set_ask_user_callback(NULL)
  expect_null(get_ask_user_callback())

  # Set a callback
  cb <- function(q, c, t) "test"
  set_ask_user_callback(cb)
  expect_true(is.function(get_ask_user_callback()))

  # Clean up
  set_ask_user_callback(NULL)
})

test_that("ask_user_impl uses callback when set", {
  # Set up a mock callback
  captured_args <- NULL
  mock_callback <- function(question, choices, type) {
    captured_args <<- list(question = question, choices = choices, type = type)
    "mocked response"
  }

  set_ask_user_callback(mock_callback)
  withr::defer(set_ask_user_callback(NULL))

  # Call the implementation
  result <- ask_user_impl("Test question?", c("A", "B"), "choice")

  # Verify callback was called with correct args
  expect_equal(captured_args$question, "Test question?")
  expect_equal(captured_args$choices, c("A", "B"))
  expect_equal(captured_args$type, "choice")
  expect_equal(result, "mocked response")
})

test_that("ask_user_impl errors in non-interactive without callback", {
  # Ensure no callback is set
  set_ask_user_callback(NULL)

  # Skip if we're actually in an interactive session
  skip_if(interactive(), "Test requires non-interactive session")

  expect_error(
    ask_user_impl("question"),
    "not interactive"
  )
})

test_that("tool_ask_user works with callback", {
  # Set up callback
  set_ask_user_callback(function(q, c, t) "user choice")
  withr::defer(set_ask_user_callback(NULL))

  # Tools are directly callable (inherit from function)
  result <- tool_ask_user("What do you want?", NULL, "text")
  expect_true(grepl("user choice", result))
})

test_that("tool_ask_user validates type argument", {
  set_ask_user_callback(function(q, c, t) "test")
  withr::defer(set_ask_user_callback(NULL))

  # Invalid type should be rejected (tool_reject throws an error)
  expect_error(
    tool_ask_user("question", NULL, "invalid_type"),
    "Invalid type"
  )
})

test_that("tool_ask_user requires choices for choice type", {
  set_ask_user_callback(function(q, c, t) "test")
  withr::defer(set_ask_user_callback(NULL))

  # Choice type without choices should be rejected
  expect_error(
    tool_ask_user("question", NULL, "choice"),
    "choices must be provided"
  )

  # Empty choices should also be rejected
  expect_error(
    tool_ask_user("question", character(0), "choice"),
    "choices must be provided"
  )
})
