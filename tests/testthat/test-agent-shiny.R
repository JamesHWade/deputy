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

test_that("run_shiny resets counters on each call", {
  skip_if_not_installed("promises")

  mock_chat <- create_mock_chat()

  # Add stream_async to mock
  mock_chat$stream_async <- function(prompt, stream = "content") {
    promises::promise(function(resolve, reject) {
      resolve("done")
    })
  }

  agent <- Agent$new(chat = mock_chat)

  # Simulate previous state
  agent$.__enclos_env__$private$tool_call_count <- 10L
  agent$.__enclos_env__$private$tool_call_limit <- 5L

  # Call run_shiny -- should reset count and set new limit
  result <- agent$run_shiny("test", max_tool_calls = 20L)

  expect_equal(agent$.__enclos_env__$private$tool_call_count, 0L)
  expect_equal(agent$.__enclos_env__$private$tool_call_limit, 20L)
})

test_that("run_shiny defaults max_tool_calls from permissions$max_turns", {
  skip_if_not_installed("promises")

  mock_chat <- create_mock_chat()
  mock_chat$stream_async <- function(prompt, stream = "content") {
    promises::promise(function(resolve, reject) {
      resolve("done")
    })
  }

  agent <- Agent$new(
    chat = mock_chat,
    permissions = Permissions$new(max_turns = 15)
  )

  agent$run_shiny("test")

  expect_equal(agent$.__enclos_env__$private$tool_call_limit, 15L)
})
