test_that("tool_call_limit is NULL by default", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  expect_null(agent$.__enclos_env__$private$tool_call_limit)
  expect_equal(agent$.__enclos_env__$private$tool_call_count, 0L)
})

test_that("on_tool_request enforces tool_call_limit", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Activate callback-based limits (simulating the governed stream setup)
  agent$.__enclos_env__$private$tool_call_limit <- 2L
  agent$.__enclos_env__$private$tool_call_count <- 0L

  # Create a mock tool request
  request <- create_mock_tool_request(
    name = "read_file",
    arguments = list(path = "test.R")
  )

  # First two calls should pass (count goes to 1, then 2)
  expect_no_error(agent$.__enclos_env__$private$handle_tool_request(request))
  expect_equal(agent$.__enclos_env__$private$tool_call_count, 1L)

  expect_no_error(agent$.__enclos_env__$private$handle_tool_request(request))
  expect_equal(agent$.__enclos_env__$private$tool_call_count, 2L)

  # Third call exceeds limit -- should call tool_reject
  expect_error(
    agent$.__enclos_env__$private$handle_tool_request(request),
    "Tool call limit reached"
  )
})

test_that("on_tool_request enforces cost limit in callback mode", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    usage_limits = UsageLimits(max_cost_usd = 0.001)
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
    agent$.__enclos_env__$private$handle_tool_request(request),
    "estimated cost"
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

  expect_no_error(agent$.__enclos_env__$private$handle_tool_request(request))
  expect_equal(agent$.__enclos_env__$private$tool_call_count, 0L)
})

test_that("Agent exposes stream_async instead of a separate Shiny bridge", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  expect_true("stream_async" %in% names(agent))
  expect_false("run_shiny" %in% names(agent))
})

test_that("stream_async returns content and resets counters on each call", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  mock_chat <- create_mock_chat()
  observed <- new.env(parent = emptyenv())

  # Add stream_async to mock
  mock_chat$stream_async <- function(prompt, stream = "content") {
    observed$count <- agent$.__enclos_env__$private$tool_call_count
    observed$limit <- agent$.__enclos_env__$private$tool_call_limit
    coro::generator(function() {
      coro::yield("done")
    })()
  }

  agent <- Agent$new(
    chat = mock_chat,
    usage_limits = UsageLimits(max_tool_calls = 20L)
  )

  # Simulate previous state
  agent$.__enclos_env__$private$tool_call_count <- 10L
  agent$.__enclos_env__$private$tool_call_limit <- 5L

  # Construction is lazy and must not reserve or mutate the Agent.
  result <- agent$stream_async("test")

  expect_true(inherits(result, "coro_generator_instance"))
  expect_equal(agent$.__enclos_env__$private$tool_call_count, 10L)
  expect_equal(agent$.__enclos_env__$private$tool_call_limit, 5L)
  expect_equal(collect_async_stream(result), list("done"))
  expect_equal(observed$count, 0L)
  expect_equal(observed$limit, 20L)
  expect_null(agent$.__enclos_env__$private$tool_call_limit)
})

test_that("stream_async isolates and clears run-scoped state", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  mock_chat <- create_mock_chat()
  observed <- new.env(parent = emptyenv())
  mock_chat$stream_async <- function(prompt, stream = "content") {
    observed$run_active <- private$run_active
    observed$current_stream_content <- private$current_stream_content
    observed$current_usage_limits <- private$current_usage_limits
    observed$pending_events <- private$pending_events
    coro::generator(function() {
      coro::yield("done")
    })()
  }
  agent <- Agent$new(
    chat = mock_chat,
    usage_limits = UsageLimits(max_tool_calls = 3)
  )

  private <- agent$.__enclos_env__$private
  private$current_usage_limits <- UsageLimits(max_requests = 0)
  private$current_usage_baseline <- AgentUsage(requests = 100)
  private$current_stream_content <- FALSE
  private$pending_events <- list(AgentEvent("warning", message = "stale"))

  stream <- agent$stream_async("test")

  expect_false(private$run_active)
  expect_false(private$current_stream_content)
  expect_equal(private$current_usage_limits$max_requests, 0L)
  expect_length(private$pending_events, 1L)

  expect_equal(collect_async_stream(stream), list("done"))
  expect_true(observed$run_active)
  expect_false(observed$current_stream_content)
  expect_s3_class(observed$current_usage_limits, "UsageLimits")
  expect_null(observed$current_usage_limits$max_requests)
  expect_equal(observed$current_usage_limits$max_tool_calls, 3L)
  expect_length(observed$pending_events, 0L)
  expect_false(private$run_active)
  expect_false(private$current_stream_content)
  expect_null(private$current_usage_limits)
  expect_null(private$current_usage_baseline)
  expect_length(private$pending_events, 0L)
})

test_that("stream_async releases state when stream setup fails", {
  skip_if_not_installed("promises")

  mock_chat <- create_mock_chat()
  mock_chat$stream_async <- function(prompt, stream = "content") {
    stop("setup failed")
  }
  agent <- Agent$new(chat = mock_chat)

  stream <- agent$stream_async("test")
  expect_error(collect_async_stream(stream), "setup failed")
  expect_false(agent$.__enclos_env__$private$run_active)
  expect_null(agent$.__enclos_env__$private$current_usage_limits)
  expect_null(agent$.__enclos_env__$private$tool_call_limit)
})

test_that("stream_async uses max_tool_calls from Agent limits", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  mock_chat <- create_mock_chat()
  observed_limit <- NULL
  mock_chat$stream_async <- function(prompt, stream = "content") {
    observed_limit <<- agent$.__enclos_env__$private$tool_call_limit
    coro::generator(function() {
      coro::yield("done")
    })()
  }

  agent <- Agent$new(
    chat = mock_chat,
    usage_limits = UsageLimits(max_tool_calls = 15)
  )

  stream <- agent$stream_async("test")

  expect_null(agent$.__enclos_env__$private$tool_call_limit)
  expect_equal(collect_async_stream(stream), list("done"))
  expect_equal(observed_limit, 15L)
  expect_null(agent$.__enclos_env__$private$tool_call_limit)
})

test_that("stream_async fires Stop and SessionEnd hooks on completion", {
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
      NULL
    }
  ))
  agent$add_hook(HookMatcher$new(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context) {
      session_end_reason <<- reason
      NULL
    }
  ))

  stream <- agent$stream_async("test")

  expect_null(stop_reason)
  expect_null(session_end_reason)
  expect_equal(collect_async_stream(stream), list("done"))
  expect_equal(stop_reason, "complete")
  expect_equal(session_end_reason, "complete")
  expect_null(agent$.__enclos_env__$private$tool_call_limit)
})

test_that("stream_async cleans up and reports stream errors", {
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
      NULL
    }
  ))
  agent$add_hook(HookMatcher$new(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context) {
      session_end_reason <<- reason
      NULL
    }
  ))

  stream <- agent$stream_async("test")

  expect_error(collect_async_stream(stream), "stream failed")
  expect_equal(stop_reason, "error")
  expect_equal(session_end_reason, "error")
  expect_null(agent$.__enclos_env__$private$tool_call_limit)
})

test_that("stream_async checkpoints rooted file writes", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  root <- withr::local_tempdir(pattern = "deputy-shiny-checkpoint-")
  path <- file.path(root, "created.txt")
  mock <- create_shiny_tool_chat(
    "write_file",
    list(path = path, content = "created"),
    execute = function(request) {
      writeLines("created", request@arguments$path)
    }
  )
  agent <- Agent$new(
    chat = mock$chat,
    permissions = permissions_standard(root),
    enable_file_checkpointing = TRUE,
    working_dir = root
  )

  stream_result <- collect_async_stream(agent$stream_async("write"))
  rejection_reason <- if (is.null(mock$state$rejection)) {
    NULL
  } else {
    conditionMessage(mock$state$rejection)
  }
  expect_equal(stream_result, list("done"), info = rejection_reason)
  expect_true(mock$state$executed)
  expect_true(file.exists(path))
  checkpoints <- agent$list_checkpoints()
  expect_equal(nrow(checkpoints), 1L)

  rewind <- agent$rewind_files(checkpoints$checkpoint_id[[1L]])
  expect_equal(rewind$restored_changes, 1L)
  expect_false(file.exists(path))
})

test_that("stream_async rejects dangling symlinks targeting outside", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")
  skip_on_os("windows")

  sandbox <- withr::local_tempdir(pattern = "deputy-shiny-link-")
  root <- file.path(sandbox, "root")
  outside <- file.path(sandbox, "outside")
  dir.create(root)
  dir.create(outside)
  outside_target <- file.path(outside, "created.txt")
  link <- file.path(root, "link.txt")
  expect_true(file.symlink(outside_target, link))
  mock <- create_shiny_tool_chat(
    "write_file",
    list(path = link, content = "unsafe"),
    execute = function(request) {
      writeLines("unsafe", request@arguments$path)
    }
  )
  agent <- Agent$new(
    chat = mock$chat,
    permissions = permissions_standard(root),
    working_dir = root
  )

  expect_equal(
    collect_async_stream(agent$stream_async("write")),
    list("rejected")
  )
  expect_true(mock$state$rejected)
  expect_false(mock$state$executed)
  expect_false(file.exists(outside_target))
})

test_that("abandoned stream_async streams release the exact active run", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  mock_chat <- create_mock_chat()
  mock_chat$stream_async <- function(
    prompt,
    stream = "content",
    controller = NULL
  ) {
    coro::async_generator(function() {
      coro::yield("first")
      coro::yield("second")
    })()
  }
  agent <- Agent$new(chat = mock_chat)
  stream <- agent$stream_async("test")

  expect_equal(resolve_async_value(stream()), "first")
  expect_true(agent$.__enclos_env__$private$run_active)
  expect_true(agent$interrupt("user_cancelled"))
  stream <- NULL
  invisible(gc())
  later::run_now(0.01)

  expect_false(agent$.__enclos_env__$private$run_active)
  expect_no_error(agent$stream_async("next"))
})

test_that("stream_async reports clean cancellation instead of completion", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  stop_reason <- NULL
  agent <- NULL
  chat <- create_mock_chat()
  chat$stream_async <- function(
    prompt,
    stream = "content",
    controller = NULL
  ) {
    coro::async_generator(function() {
      agent$interrupt("user_cancelled")
    })()
  }
  agent <- Agent$new(chat = chat)
  agent$add_hook(HookMatcher$new(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context) {
      stop_reason <<- reason
      NULL
    }
  ))

  expect_length(collect_async_stream(agent$stream_async("cancel")), 0L)
  expect_identical(stop_reason, "user_cancelled")
})

test_that("stream_async reports terminal cost limits without tool calls", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  cost <- 0
  output_tokens <- 0
  stop_reason <- NULL
  chat <- create_mock_chat()
  chat$get_tokens <- function() {
    data.frame(input = 1, output = 1, cached_input = 0, cost = cost)
  }
  chat$stream_async <- function(
    prompt,
    stream = "content",
    controller = NULL
  ) {
    cost <<- 0.01
    coro::async_generator(function() {
      coro::yield("over budget")
    })()
  }
  agent <- Agent$new(
    chat = chat,
    usage_limits = UsageLimits(max_cost_usd = 0.001)
  )
  agent$add_hook(HookMatcher$new(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context) {
      stop_reason <<- reason
      NULL
    }
  ))

  expect_equal(
    collect_async_stream(agent$stream_async("expensive")),
    list("over budget")
  )
  expect_identical(stop_reason, "cost_limit")
})

test_that("stream_async enforces Agent usage_limits", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  cost <- 0
  stop_reason <- NULL
  observed_limits <- NULL
  chat <- create_mock_chat()
  chat$get_tokens <- function() {
    data.frame(
      input = 1,
      output = output_tokens,
      cached_input = 0,
      cost = cost
    )
  }
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    observed_limits <<- agent$.__enclos_env__$private$current_usage_limits
    cost <<- 0.01
    output_tokens <<- 2
    coro::async_generator(function() {
      coro::yield("over budget")
    })()
  }
  agent <- Agent$new(
    chat = chat,
    usage_limits = UsageLimits(
      max_output_tokens = 1,
      max_cost_usd = 0.001,
      max_tool_calls = 7,
      on_exceed = "stop"
    )
  )
  agent$add_hook(HookMatcher$new(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context) {
      stop_reason <<- reason
      NULL
    }
  ))

  expect_equal(
    collect_async_stream(agent$stream_async("expensive")),
    list("over budget")
  )
  expect_equal(observed_limits$max_output_tokens, 1L)
  expect_equal(observed_limits$max_cost_usd, 0.001)
  expect_equal(observed_limits$max_tool_calls, 7L)
  expect_identical(stop_reason, "output_token_limit")
})

test_that("stream_async does not start with no request budget", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  provider_calls <- 0L
  stop_reason <- NULL
  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    provider_calls <<- provider_calls + 1L
    coro::async_generator(function() {
      coro::yield("unexpected")
    })()
  }
  agent <- Agent$new(
    chat = chat,
    usage_limits = UsageLimits(max_requests = 0)
  )
  agent$add_hook(HookMatcher$new(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context) {
      stop_reason <<- reason
      NULL
    }
  ))

  expect_length(collect_async_stream(agent$stream_async("blocked")), 0L)
  expect_identical(provider_calls, 0L)
  expect_identical(stop_reason, "request_limit")
})

test_that("stream_async reports incomplete tool calls as provider errors", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  stop_reason <- NULL
  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    agent$.__enclos_env__$private$current_tool_calls <- 1L
    coro::async_generator(function() {
      if (FALSE) coro::yield("unreachable")
    })()
  }
  agent <- Agent$new(chat = chat)
  agent$add_hook(HookMatcher$new(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context) {
      stop_reason <<- reason
      NULL
    }
  ))

  expect_length(collect_async_stream(agent$stream_async("incomplete")), 0L)
  expect_identical(stop_reason, "provider_error")
})
