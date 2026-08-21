test_that("run_async resolves to an AgentResult with the final turn's text", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      coro::yield(ellmer::ContentText("Thinking... "))
      request <- ellmer::ContentToolRequest(
        id = "t1",
        name = "read_file",
        arguments = list(path = "a.txt")
      )
      coro::yield(request)
      coro::yield(ellmer::ContentToolResult(value = "ok", request = request))
      coro::yield(ellmer::ContentText("Final "))
      coro::yield(ellmer::ContentText("answer"))
    })()
  }
  agent <- Agent$new(chat = chat, agent_name = "worker")

  promise <- agent$run_async("do it", run_context = list(role = "worker"))
  expect_true(promises::is.promising(promise))

  result <- resolve_async_value(promise)
  expect_s3_class(result, "AgentResult")
  # Text before the tool call is narration; only the last turn survives.
  expect_identical(result$response, "Final answer")
  expect_identical(result$stop_reason, "complete")
  expect_identical(result$agent_name, "worker")
  expect_identical(result$agent_id, agent$agent_id)
  expect_identical(result$session_id, agent$session_id())
  expect_match(result$run_id, "^run_")
  expect_identical(result$run_context$role, "worker")
  expect_s3_class(result$usage, "AgentUsage")
  expect_true(is.numeric(result$duration))
  expect_false(agent$.__enclos_env__$private$run_active)
})

test_that("run_async accepts plain text chunks and falls back to last turn", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  chat <- create_mock_chat(responses = list("from last turn"))
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      coro::yield("plain ")
      coro::yield("text")
    })()
  }
  agent <- Agent$new(chat = chat)
  expect_identical(
    resolve_async_value(agent$run_async("x"))$response,
    "plain text"
  )

  silent <- create_mock_chat(responses = list("from last turn"))
  silent$stream_async <- function(
    prompt,
    stream = "content",
    controller = NULL
  ) {
    coro::async_generator(function() {
      if (FALSE) coro::yield("unreachable")
    })()
  }
  silent$last_turn <- function(role = "assistant") {
    create_mock_assistant_turn(text = "from last turn")
  }
  agent <- Agent$new(chat = silent)
  expect_identical(
    resolve_async_value(agent$run_async("x"))$response,
    "from last turn"
  )
})

test_that("run_async enforces tool-call limits and releases the run", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  calls <- 0L
  chat <- create_mock_chat()
  request_cb <- NULL
  result_cb <- NULL
  chat$on_tool_request <- function(callback) request_cb <<- callback
  chat$on_tool_result <- function(callback) result_cb <<- callback
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      for (i in 1:3) {
        request <- ellmer::ContentToolRequest(
          id = paste0("t", i),
          name = "read_file",
          arguments = list(path = "a.txt")
        )
        rejected <- tryCatch(
          {
            request_cb(request)
            FALSE
          },
          ellmer_tool_reject = function(e) TRUE
        )
        if (!rejected) {
          calls <<- calls + 1L
        }
        result_cb(ellmer::ContentToolResult(
          value = if (rejected) NULL else "ok",
          error = if (rejected) "limit" else NULL,
          request = request
        ))
        coro::yield(request)
      }
      coro::yield(ellmer::ContentText("done"))
    })()
  }
  agent <- Agent$new(chat = chat)

  result <- resolve_async_value(
    agent$run_async("x", usage_limits = UsageLimits(max_tool_calls = 2))
  )
  expect_equal(calls, 2L)
  expect_identical(result$stop_reason, "tool_call_limit")
  expect_false(agent$.__enclos_env__$private$run_active)
  expect_null(agent$.__enclos_env__$private$tool_call_limit)

  # Agent-level limits apply when no override is given.
  calls <- 0L
  agent <- Agent$new(
    chat = chat,
    usage_limits = UsageLimits(max_tool_calls = 1)
  )
  result <- resolve_async_value(agent$run_async("x"))
  expect_equal(calls, 1L)
  expect_identical(result$stop_reason, "tool_call_limit")
})

test_that("run_async leaves tool calls unbounded when no tool-call limit is set", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  observed <- NULL
  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    observed <<- agent$.__enclos_env__$private$tool_call_limit
    coro::async_generator(function() coro::yield("done"))()
  }
  agent <- Agent$new(chat = chat, usage_limits = UsageLimits(max_requests = 5))
  resolve_async_value(agent$run_async("x"))
  expect_null(observed)
})

test_that("run_async honors on_exceed = 'error' by rejecting the promise", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  cost <- 0
  chat <- create_mock_chat()
  chat$get_tokens <- function() {
    data.frame(input = 1, output = 1, cached_input = 0, cost = cost)
  }
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    cost <<- 0.01
    coro::async_generator(function() coro::yield("over budget"))()
  }
  agent <- Agent$new(
    chat = chat,
    usage_limits = UsageLimits(max_cost_usd = 0.001, on_exceed = "error")
  )
  expect_error(
    resolve_async_value(agent$run_async("expensive")),
    class = "deputy_budget_exceeded"
  )
  expect_false(agent$.__enclos_env__$private$run_active)

  # With the default "stop", the same run resolves with a typed reason.
  cost <- 0
  agent <- Agent$new(
    chat = chat,
    usage_limits = UsageLimits(max_cost_usd = 0.001)
  )
  result <- resolve_async_value(agent$run_async("expensive"))
  expect_identical(result$stop_reason, "cost_limit")
  expect_gt(result$usage$cost_usd, 0)
})

test_that("run_async fires lifecycle hooks and records usage on the result", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  fired <- character()
  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() coro::yield("done"))()
  }
  agent <- Agent$new(chat = chat)
  for (event in c("SessionStart", "UserPromptSubmit", "Stop", "SessionEnd")) {
    local({
      name <- event
      agent$add_hook(HookMatcher$new(
        event = name,
        timeout = 0,
        callback = function(...) {
          fired <<- c(fired, name)
          NULL
        }
      ))
    })
  }

  result <- resolve_async_value(agent$run_async("x"))
  expect_identical(
    fired,
    c("SessionStart", "UserPromptSubmit", "Stop", "SessionEnd")
  )
  expect_s3_class(result$usage, "AgentUsage")
  expect_identical(agent$.__enclos_env__$private$last_run_usage, result$usage)
})

test_that("run_async rejects on stream failure and releases the agent", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  # The mock chat is a plain list, so the stream must consult mutable state
  # rather than being reassigned after the Agent captured it.
  mode <- new.env(parent = emptyenv())
  mode$fail <- TRUE
  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      if (mode$fail) {
        stop("stream failed")
      }
      coro::yield("ok")
    })()
  }
  agent <- Agent$new(chat = chat)
  expect_error(resolve_async_value(agent$run_async("x")), "stream failed")
  expect_false(agent$.__enclos_env__$private$run_active)

  # A failed run must not block the next one.
  mode$fail <- FALSE
  expect_identical(resolve_async_value(agent$run_async("y"))$response, "ok")
})

test_that("run_async refuses to start while another run is active", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      coro::await(promises::promise(function(resolve, reject) {
        later::later(function() resolve(TRUE), 0.05)
      }))
      coro::yield("done")
    })()
  }
  agent <- Agent$new(chat = chat)
  first <- agent$run_async("x")
  expect_error(agent$run_async("y"), class = "deputy_run_active")
  expect_identical(resolve_async_value(first)$response, "done")
  expect_identical(resolve_async_value(agent$run_async("z"))$response, "done")
})

test_that("run_async allows relative file paths unlike run_shiny", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  dir <- withr::local_tempdir()
  writeLines("hello", file.path(dir, "note.txt"))
  read <- create_shiny_tool_chat(
    tool_name = "read_file",
    tool_input = list(path = "note.txt")
  )
  agent <- Agent$new(
    chat = read$chat,
    tools = list(tool_read_file),
    permissions = permissions_readonly(),
    working_dir = dir
  )

  result <- resolve_async_value(agent$run_async("read"))
  expect_true(read$state$executed)
  expect_false(read$state$rejected)
  expect_identical(result$response, "done")
})

test_that("run_async reports clean interruption", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  agent <- NULL
  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      agent$interrupt("user_cancelled")
      coro::yield("ignored")
    })()
  }
  agent <- Agent$new(chat = chat)
  result <- resolve_async_value(agent$run_async("cancel"))
  expect_identical(result$stop_reason, "user_cancelled")
})

test_that("run_shiny still records usage on the shared callback state", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() coro::yield("done"))()
  }
  agent <- Agent$new(chat = chat)
  expect_equal(collect_async_stream(agent$run_shiny("x")), list("done"))
  expect_s3_class(agent$.__enclos_env__$private$last_run_usage, "AgentUsage")
})
