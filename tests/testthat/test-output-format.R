# Tests for structured output and partial streaming

test_that("structured output parses JSON responses", {
  skip_if_not_installed("jsonlite")

  chat <- create_mock_chat(list("{\"status\":\"ok\"}"))
  agent <- Agent$new(chat = chat, tools = list())

  schema <- list(
    type = "object",
    properties = list(status = list(type = "string")),
    required = list("status")
  )

  result <- agent$run_sync(
    "Return status ok",
    output_format = list(type = "json_schema", schema = schema)
  )

  expect_true(is.list(result$structured_output))
  if (rlang::is_installed("jsonvalidate")) {
    expect_true(result$structured_output$valid)
  } else {
    expect_true(is.na(result$structured_output$valid))
  }
  expect_equal(result$structured_output$parsed$status, "ok")
})

test_that("include_partial_messages suppresses text events", {
  chat <- create_mock_chat(list("hello"))
  agent <- Agent$new(chat = chat, tools = list())

  gen <- agent$run("task", include_partial_messages = FALSE)
  events <- list()

  repeat {
    event <- tryCatch(gen(), error = function(e) coro::exhausted())
    if (coro::is_exhausted(event)) {
      break
    }
    events <- c(events, list(event))
    if (inherits(event, "AgentEvent") && event$type == "stop") {
      break
    }
  }

  types <- vapply(events, function(e) e$type, character(1))
  expect_false("text" %in% types)
  expect_true("text_complete" %in% types)
})
