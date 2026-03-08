collect_async_stream <- function(stream) {
  result <- NULL
  stream_error <- NULL
  done <- FALSE

  coro::async_collect(stream) |>
    promises::then(function(value) {
      result <<- value
      done <<- TRUE
    }) |>
    promises::catch(function(cnd) {
      stream_error <<- cnd
      done <<- TRUE
    })

  for (i in seq_len(100)) {
    if (done) {
      break
    }
    later::run_now(0.01)
  }

  if (!done) {
    stop("Async stream did not settle")
  }

  if (!is.null(stream_error)) {
    stop(stream_error)
  }

  result
}

test_that("tool_call_limit is NULL by default", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  expect_null(agent$.__enclos_env__$private$tool_call_limit)
  expect_equal(agent$.__enclos_env__$private$tool_call_count, 0L)
})

test_that("on_tool_request enforces tool_call_limit", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Activate callback-based limits (simulating run_shiny setup)
  agent$.__enclos_env__$private$tool_call_limit <- 2L
  agent$.__enclos_env__$private$tool_call_count <- 0L

  # Create a mock tool request
  request <- create_mock_tool_request(
    name = "read_file",
    arguments = list(path = "test.R")
  )

  # First two calls should pass (count goes to 1, then 2)
  expect_no_error(agent$.__enclos_env__$private$on_tool_request(request))
  expect_equal(agent$.__enclos_env__$private$tool_call_count, 1L)

  expect_no_error(agent$.__enclos_env__$private$on_tool_request(request))
  expect_equal(agent$.__enclos_env__$private$tool_call_count, 2L)

  # Third call exceeds limit -- should call tool_reject
  expect_error(
    agent$.__enclos_env__$private$on_tool_request(request),
    "Tool call limit reached"
  )
})

test_that("on_tool_request enforces cost limit in callback mode", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    permissions = Permissions$new(max_cost_usd = 0.001)
  )

  # Activate callback-based limits
  agent$.__enclos_env__$private$tool_call_limit <- 100L
  agent$.__enclos_env__$private$tool_call_count <- 0L

  request <- create_mock_tool_request(
    name = "read_file",
    arguments = list(path = "test.R")
  )

  # mock_chat returns cost = 0.001 which matches the limit
  expect_error(
    agent$.__enclos_env__$private$on_tool_request(request),
    "Cost limit reached"
  )
})

test_that("on_tool_request skips limit checks when tool_call_limit is NULL", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Ensure limit is NULL (default -- run/run_sync path)
  expect_null(agent$.__enclos_env__$private$tool_call_limit)

  request <- create_mock_tool_request(
    name = "read_file",
    arguments = list(path = "test.R")
  )

  # Should not increment or check limits

  expect_no_error(agent$.__enclos_env__$private$on_tool_request(request))
  expect_equal(agent$.__enclos_env__$private$tool_call_count, 0L)
})

test_that("run_shiny requires promises package", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # run_shiny should check for promises
  # We can't easily test this without mocking check_installed,

  # but we verify the method exists
  expect_true("run_shiny" %in% names(agent))
})

test_that("run_shiny returns a content stream and resets counters on each call", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  mock_chat <- create_mock_chat()

  # Add stream_async to mock
  mock_chat$stream_async <- function(prompt, stream = "content") {
    coro::generator(function() {
      coro::yield("done")
    })()
  }

  agent <- Agent$new(chat = mock_chat)

  # Simulate previous state
  agent$.__enclos_env__$private$tool_call_count <- 10L
  agent$.__enclos_env__$private$tool_call_limit <- 5L

  # Call run_shiny -- should reset count and set new limit
  result <- agent$run_shiny("test", max_tool_calls = 20L)

  expect_true(inherits(result, "coro_generator_instance"))
  expect_equal(agent$.__enclos_env__$private$tool_call_count, 0L)
  expect_equal(agent$.__enclos_env__$private$tool_call_limit, 20L)
  expect_equal(collect_async_stream(result), list("done"))
  expect_null(agent$.__enclos_env__$private$tool_call_limit)
})

test_that("run_shiny defaults max_tool_calls from permissions$max_turns", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  mock_chat <- create_mock_chat()
  mock_chat$stream_async <- function(prompt, stream = "content") {
    coro::generator(function() {
      coro::yield("done")
    })()
  }

  agent <- Agent$new(
    chat = mock_chat,
    permissions = Permissions$new(max_turns = 15)
  )

  stream <- agent$run_shiny("test")

  expect_equal(agent$.__enclos_env__$private$tool_call_limit, 15L)
  expect_equal(collect_async_stream(stream), list("done"))
  expect_null(agent$.__enclos_env__$private$tool_call_limit)
})

test_that("run_shiny fires Stop and SessionEnd hooks when the stream completes", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  mock_chat <- create_mock_chat()
  mock_chat$stream_async <- function(prompt, stream = "content") {
    coro::generator(function() {
      coro::yield("done")
    })()
  }

  agent <- Agent$new(chat = mock_chat)

  stop_reason <- NULL
  session_end_reason <- NULL

  agent$add_hook(HookMatcher$new(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context) {
      stop_reason <<- reason
      HookResultStop()
    }
  ))
  agent$add_hook(HookMatcher$new(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context) {
      session_end_reason <<- reason
      HookResultSessionEnd()
    }
  ))

  stream <- agent$run_shiny("test")

  expect_null(stop_reason)
  expect_null(session_end_reason)
  expect_equal(collect_async_stream(stream), list("done"))
  expect_equal(stop_reason, "complete")
  expect_equal(session_end_reason, "complete")
  expect_null(agent$.__enclos_env__$private$tool_call_limit)
})

test_that("run_shiny cleans up and reports errors when the stream fails", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  mock_chat <- create_mock_chat()
  mock_chat$stream_async <- function(prompt, stream = "content") {
    coro::async_generator(function() {
      coro::yield("partial")
      stop("stream failed")
    })()
  }

  agent <- Agent$new(chat = mock_chat)

  stop_reason <- NULL
  session_end_reason <- NULL

  agent$add_hook(HookMatcher$new(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context) {
      stop_reason <<- reason
      HookResultStop()
    }
  ))
  agent$add_hook(HookMatcher$new(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context) {
      session_end_reason <<- reason
      HookResultSessionEnd()
    }
  ))

  stream <- agent$run_shiny("test")

  expect_error(collect_async_stream(stream), "stream failed")
  expect_equal(stop_reason, "error")
  expect_equal(session_end_reason, "error")
  expect_null(agent$.__enclos_env__$private$tool_call_limit)
})
