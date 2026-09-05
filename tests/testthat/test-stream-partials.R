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
