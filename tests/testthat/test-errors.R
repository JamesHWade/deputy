# Tests for structured error types

test_that("abort_deputy creates structured error with cli formatting", {
  err <- tryCatch(
    abort_deputy("Test error message"),
    error = function(e) e
  )

  expect_s3_class(err, "deputy_error")
  expect_s3_class(err, "rlang_error")
  expect_true(grepl("Test error message", conditionMessage(err)))
})

test_that("abort_deputy accepts custom classes", {
  err <- tryCatch(
    abort_deputy("Test", class = "custom"),
    error = function(e) e
  )

  expect_s3_class(err, "deputy_custom")
  expect_s3_class(err, "deputy_error")
})

test_that("abort_deputy accepts additional fields", {
  err <- tryCatch(
    abort_deputy(
      "Test",
      custom_field = "value",
      another_field = 123
    ),
    error = function(e) e
  )

  expect_equal(err$custom_field, "value")
  expect_equal(err$another_field, 123)
})

test_that("abort_permission_denied has correct structure", {
  err <- tryCatch(
    abort_permission_denied(
      "Write not allowed",
      tool_name = "write_file",
      permission_mode = "readonly",
      reason = "Mode is readonly"
    ),
    error = function(e) e
  )

  expect_s3_class(err, "deputy_permission_denied")
  expect_s3_class(err, "deputy_permission")
  expect_s3_class(err, "deputy_error")
  expect_equal(err$tool_name, "write_file")
  expect_equal(err$permission_mode, "readonly")
  expect_equal(err$reason, "Mode is readonly")
})

test_that("abort_tool_execution has correct structure", {
  err <- tryCatch(
    abort_tool_execution(
      "File not found",
      tool_name = "read_file",
      tool_input = list(path = "/test.txt")
    ),
    error = function(e) e
  )

  expect_s3_class(err, "deputy_tool_execution")
  expect_s3_class(err, "deputy_tool")
  expect_s3_class(err, "deputy_error")
  expect_equal(err$tool_name, "read_file")
  expect_equal(err$tool_input$path, "/test.txt")
})

test_that("abort_budget_exceeded has correct structure", {
  err <- tryCatch(
    abort_budget_exceeded(
      "Cost limit exceeded",
      current_cost = 0.55,
      max_cost = 0.50
    ),
    error = function(e) e
  )

  expect_s3_class(err, "deputy_budget_exceeded")
  expect_s3_class(err, "deputy_budget")
  expect_s3_class(err, "deputy_error")
  expect_equal(err$current_cost, 0.55)
  expect_equal(err$max_cost, 0.50)
})

test_that("abort_turn_limit has correct structure", {
  err <- tryCatch(
    abort_turn_limit(
      "Maximum turns exceeded",
      current_turns = 25,
      max_turns = 25
    ),
    error = function(e) e
  )

  expect_s3_class(err, "deputy_turn_limit")
  expect_s3_class(err, "deputy_budget")
  expect_s3_class(err, "deputy_error")
  expect_equal(err$current_turns, 25)
  expect_equal(err$max_turns, 25)
})

test_that("abort_provider has correct structure", {
  err <- tryCatch(
    abort_provider(
      "API rate limit exceeded",
      provider_name = "openai",
      model = "gpt-4o"
    ),
    error = function(e) e
  )

  expect_s3_class(err, "deputy_provider")
  expect_s3_class(err, "deputy_error")
  expect_equal(err$provider_name, "openai")
  expect_equal(err$model, "gpt-4o")
})

test_that("abort_session_load has correct structure", {
  err <- tryCatch(
    abort_session_load(
      "Session file corrupted",
      path = "session.rds"
    ),
    error = function(e) e
  )

  expect_s3_class(err, "deputy_session_load")
  expect_s3_class(err, "deputy_session")
  expect_s3_class(err, "deputy_error")
  expect_equal(err$path, "session.rds")
})

test_that("abort_session_save has correct structure", {
  err <- tryCatch(
    abort_session_save(
      "Cannot write file",
      path = "/readonly/session.rds"
    ),
    error = function(e) e
  )

  expect_s3_class(err, "deputy_session_save")
  expect_s3_class(err, "deputy_session")
  expect_s3_class(err, "deputy_error")
  expect_equal(err$path, "/readonly/session.rds")
})

test_that("abort_hook has correct structure", {
  err <- tryCatch(
    abort_hook(
      "Hook callback failed",
      hook_event = "PreToolUse"
    ),
    error = function(e) e
  )

  expect_s3_class(err, "deputy_hook")
  expect_s3_class(err, "deputy_error")
  expect_equal(err$hook_event, "PreToolUse")
})

test_that("is_deputy_error correctly identifies errors", {
  err <- tryCatch(abort_deputy("test"), error = function(e) e)
  expect_true(is_deputy_error(err))
  expect_false(is_deputy_error("not an error"))
  expect_false(is_deputy_error(NULL))

  budget_err <- tryCatch(
    abort_budget_exceeded("over budget"),
    error = function(e) e
  )
  expect_true(is_deputy_error(budget_err))
  expect_true(is_deputy_error(budget_err, "budget_exceeded"))
  expect_true(is_deputy_error(budget_err, "budget"))
  expect_false(is_deputy_error(budget_err, "permission"))
})

test_that("errors can be caught with tryCatch by class", {
  caught_class <- NULL

  tryCatch(
    abort_budget_exceeded("test"),
    deputy_budget_exceeded = function(e) {
      caught_class <<- "budget_exceeded"
    }
  )
  expect_equal(caught_class, "budget_exceeded")

  # Test catching parent class
  caught_class <- NULL
  tryCatch(
    abort_budget_exceeded("test"),
    deputy_budget = function(e) {
      caught_class <<- "budget"
    }
  )
  expect_equal(caught_class, "budget")

  # Test catching base class
  caught_class <- NULL
  tryCatch(
    abort_permission_denied("test"),
    deputy_error = function(e) {
      caught_class <<- "deputy_error"
    }
  )
  expect_equal(caught_class, "deputy_error")
})

test_that("cli formatting works in error messages", {
  path <- "/some/path.rds"
  err <- tryCatch(
    abort_session_load(
      "Session file not found: {.path {path}}",
      path = path
    ),
    error = function(e) e
  )

  # Check that cli formatted the path
  msg <- conditionMessage(err)
  expect_true(grepl("path", msg, ignore.case = TRUE))
})

test_that("errors support parent chaining", {
  original_err <- simpleError("Original error")

  err <- tryCatch(
    abort_session_load(
      "Failed to load",
      path = "test.rds",
      parent = original_err
    ),
    error = function(e) e
  )

  expect_equal(err$parent$message, "Original error")
})

test_that("abort_session_load is thrown by Agent$load_session", {
  skip_if_not_installed("ellmer")

  # Create a mock agent
  mock_chat <- ellmer::chat_openai(model = "gpt-4o")
  agent <- Agent$new(chat = mock_chat)

  # Try to load a non-existent file
  expect_error(
    agent$load_session("/nonexistent/path/session.rds"),
    class = "deputy_session_load"
  )
})

test_that("compound cli messages work", {
  err <- tryCatch(
    abort_tool_execution(
      c(
        "Tool {.fn read_file} failed",
        "x" = "File not found",
        "i" = "Check the path exists"
      ),
      tool_name = "read_file"
    ),
    error = function(e) e
  )

  msg <- conditionMessage(err)
  expect_true(grepl("read_file", msg))
  expect_true(grepl("File not found", msg))
})
