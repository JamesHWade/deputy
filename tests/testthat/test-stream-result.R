test_that("stream_result() rejects anything that is not a stream from stream_async()", {
  agent <- Agent$new(chat = create_mock_chat())

  expect_error(stream_result(function() NULL), "stream_async")
  expect_error(stream_result(NULL), "stream_async")
  expect_error(stream_result(agent$stream("hi")), "stream_async")
})

test_that("stream_result() resolves with the run's result once the stream is drained", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  agent <- Agent$new(chat = create_mock_chat(responses = list("Hello!")))
  stream <- agent$stream_async("hi")
  promise <- stream_result(stream)

  collect_async_stream(stream)
  result <- resolve_async_value(promise)

  expect_s7_class(result, AgentResult)
  expect_identical(result$run_id, agent$last_run()$run_id)
  expect_identical(result, agent$last_run())
})

test_that("stream_result() asked after the run has finished resolves at once", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  agent <- Agent$new(chat = create_mock_chat(responses = list("Hello!")))
  stream <- agent$stream_async("hi")
  collect_async_stream(stream)

  promise <- stream_result(stream)
  result <- resolve_async_value(promise, max_polls = 1L)

  expect_s7_class(result, AgentResult)
  expect_identical(result, agent$last_run())
})

test_that("stream_result() gives the same promise each time it is asked", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  agent <- Agent$new(chat = create_mock_chat(responses = list("Hello!")))
  stream <- agent$stream_async("hi")

  first <- stream_result(stream)
  second <- stream_result(stream)

  expect_identical(first, second)
  collect_async_stream(stream)
  expect_identical(resolve_async_value(first), agent$last_run())
})

test_that("stream_result() resolves for a run that was stopped", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  agent <- NULL
  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      coro::yield("first")
      agent$interrupt("user_cancelled")
      coro::yield("second")
    })()
  }
  agent <- Agent$new(chat = chat)
  stream <- agent$stream_async("hi")
  promise <- stream_result(stream)

  collect_async_stream(stream)
  result <- resolve_async_value(promise)

  expect_s7_class(result$ending, RunEndingStopped)
  expect_identical(result$ending@by, "caller")
})

test_that("stream_result() resolves for a run that failed, though the stream rejects", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  mock_chat <- create_mock_chat()
  mock_chat$stream_async <- function(
    prompt,
    stream = "content",
    controller = NULL
  ) {
    coro::async_generator(function() {
      coro::yield("partial")
      stop("stream failed")
    })()
  }
  agent <- Agent$new(chat = mock_chat)
  stream <- agent$stream_async("test")
  promise <- stream_result(stream)

  expect_error(collect_async_stream(stream), "stream failed")
  result <- resolve_async_value(promise)

  expect_s7_class(result$ending, RunEndingFailed)
})

test_that("stream_result() resolves when the agent is free again", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  agent <- Agent$new(
    chat = create_mock_chat(responses = list("Hello!", "Again!"))
  )
  stream <- agent$stream_async("hi")
  promise <- stream_result(stream)
  collect_async_stream(stream)

  next_stream <- NULL
  started <- promises::then(promise, function(result) {
    next_stream <<- agent$stream_async("next")
    "started"
  })

  expect_identical(resolve_async_value(started), "started")
  expect_false(is.null(next_stream))
})

test_that("a stream wrapped for subagent activity still gives its result", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  # The mock's default content stream yields bare strings, which the activity
  # wrapper cannot take; content objects are what a provider streams.
  chat <- create_mock_chat(responses = list("Hello!"))
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      coro::yield(ellmer::ContentText("Hello!"))
    })()
  }
  agent <- Agent$new(chat = chat)
  presenter <- activity_enable(agent, function() "viewer", 0.05)
  on.exit(activity_disable(agent, presenter), add = TRUE)

  stream <- agent$stream_async("hi", stream = "content")
  promise <- stream_result(stream)
  collect_async_stream(stream)
  result <- resolve_async_value(promise)

  expect_s7_class(result, AgentResult)
  expect_identical(result, agent$last_run())
})

test_that("two streams made one after the other each give their own result", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  agent <- Agent$new(
    chat = create_mock_chat(responses = list("First!", "Second!"))
  )

  first <- agent$stream_async("one")
  first_promise <- stream_result(first)
  collect_async_stream(first)
  first_result <- resolve_async_value(first_promise)

  second <- agent$stream_async("two")
  second_promise <- stream_result(second)
  collect_async_stream(second)
  second_result <- resolve_async_value(second_promise)

  expect_false(identical(first_result$run_id, second_result$run_id))
  expect_identical(second_result, agent$last_run())
  expect_identical(resolve_async_value(stream_result(first)), first_result)
})
