# Tests for AgentEvent and AgentResult

test_that("AgentEvent creates correct structure", {
  event <- AgentEvent("start", task = "Test task")

  expect_s7_class(event, AgentEvent)
  expect_identical(event@type, "start")
  expect_equal(event$type, "start")
  expect_equal(event$task, "Test task")
  expect_s3_class(event$timestamp, "POSIXct")
})

test_that("AgentEvent supports different types", {
  # Text event
  text_event <- AgentEvent("text", text = "Hello", is_complete = TRUE)
  expect_identical(text_event@type, "text")
  expect_equal(text_event$text, "Hello")
  expect_true(text_event$is_complete)

  # Stop event
  stop_event <- AgentEvent("stop", reason = "complete", total_turns = 3)
  expect_identical(stop_event@type, "stop")
  expect_equal(stop_event$reason, "complete")
  expect_equal(stop_event$total_turns, 3)

  # Turn event
  turn_event <- AgentEvent("turn", turn_number = 1)
  expect_identical(turn_event@type, "turn")
  expect_equal(turn_event$turn_number, 1)
})

test_that("AgentEvent prints structured usage fields readably", {
  event <- AgentEvent(
    "usage",
    usage = AgentUsage(requests = 2, tool_calls = 1, cost_usd = 0.01),
    limits = UsageLimits(max_requests = 3)
  )

  output <- paste(capture.output(print(event)), collapse = "\n")
  expect_match(output, "usage: requests=2, tool_calls=1")
  expect_match(output, "limits: max_requests=3, on_exceed=stop")
  expect_false(grepl("0000000", output, fixed = TRUE))
})

test_that("AgentResult has correct structure", {
  result <- AgentResult(
    response = "Test response",
    turns = list("turn1", "turn2"),
    cost = list(input = 100, output = 50, cached = 0, total = 0.001),
    events = list(),
    duration = 1.5,
    stop_reason = "complete"
  )

  expect_s7_class(result, AgentResult)
  expect_equal(result$response, "Test response")
  expect_equal(result_n_turns(result), 2)
  expect_equal(result$duration, 1.5)
  expect_equal(result$stop_reason, "complete")
  expect_true(result_is_success(result))
})

test_that("AgentResult detects non-success states", {
  result_request_limit <- AgentResult(stop_reason = "request_limit")
  expect_false(result_is_success(result_request_limit))

  result_cost <- AgentResult(stop_reason = "cost_limit")
  expect_false(result_is_success(result_cost))

  result_hook <- AgentResult(stop_reason = "hook_requested_stop")
  expect_false(result_is_success(result_hook))
})

test_that("AgentResult tool_calls extracts correct events", {
  events <- list(
    AgentEvent("start", task = "test"),
    AgentEvent(
      "tool_start",
      tool_name = "read_file",
      tool_input = list(path = "test.txt")
    ),
    AgentEvent("text", text = "Reading file..."),
    AgentEvent(
      "tool_start",
      tool_name = "write_file",
      tool_input = list(path = "out.txt")
    ),
    AgentEvent("stop", reason = "complete")
  )

  result <- AgentResult(events = events)
  tool_calls <- result_tool_calls(result)

  expect_length(tool_calls, 2)
  expect_equal(tool_calls[[1]]$tool_name, "read_file")
  expect_equal(tool_calls[[2]]$tool_name, "write_file")
})

test_that("AgentResult text_chunks extracts correct events", {
  events <- list(
    AgentEvent("start", task = "test"),
    AgentEvent("text", text = "Hello "),
    AgentEvent("text", text = "world!"),
    AgentEvent("stop", reason = "complete")
  )

  result <- AgentResult(events = events)
  chunks <- result_text_chunks(result)

  expect_length(chunks, 2)
  expect_equal(chunks[1], "Hello ")
  expect_equal(chunks[2], "world!")
})

test_that("AgentResult defaults are sensible", {
  result <- AgentResult()

  expect_null(result$response)
  expect_equal(result$turns, list())
  expect_equal(result$cost$total, 0)
  expect_equal(result$events, list())
  expect_null(result$duration)
  expect_equal(result$stop_reason, "complete")
  expect_equal(result_n_turns(result), 0)
  expect_true(result_is_success(result))
})

test_that("S7 run results preserve evidence and independent list values", {
  content <- ellmer::ContentText("original")
  turn <- ellmer::AssistantTurn(list(content))
  condition <- simpleError("provider detail")
  event <- AgentEvent("run_error", condition = condition)
  context <- list(product = list(revision = "v1"))
  usage <- AgentUsage(requests = 1, input_tokens = 2, output_tokens = 1)
  result <- AgentResult(
    response = "original",
    turns = list(turn),
    events = list(event),
    usage = usage,
    run_context = context
  )
  context$product$revision <- "v2"
  turns <- result@turns
  turns[[1L]] <- ellmer::AssistantTurn(list(ellmer::ContentText("copy")))
  events <- result@events
  events[[1L]] <- AgentEvent("text", text = "copy")
  expect_identical(result@turns[[1L]], turn)
  expect_identical(result@events[[1L]]$condition, condition)
  expect_identical(result@usage, usage)
  expect_identical(result@run_context$product$revision, "v1")
  expect_identical(S7::S7_inherits(result, ellmer::Turn), FALSE)
  expect_identical(S7::S7_inherits(result, ellmer::Round), FALSE)
  expect_snapshot(error = TRUE, result@response <- "replacement")
  expect_snapshot(error = TRUE, result@structured_output <- list(value = 1))
})

test_that("every S7 result property is read-only", {
  result <- AgentResult()
  for (name in names(S7::props(result))) {
    error <- tryCatch(
      {
        S7::prop(result, name) <- S7::prop(result, name)
        NULL
      },
      error = identity
    )
    expect_match(conditionMessage(error), "read-only", info = name)
  }
  expect_identical(result_text_chunks(result), character())
  expect_identical(result_tool_calls(result), list())
  expect_identical(result_tool_results(result), list())
})

test_that("S7 result constructors reject malformed metadata", {
  expect_snapshot(error = TRUE, AgentResult(response = c("one", "two")))
  expect_snapshot(error = TRUE, AgentResult(stop_reason = NA_character_))
  expect_snapshot(error = TRUE, AgentResult(duration = Inf))
  expect_snapshot(error = TRUE, AgentResult(events = list(list(type = "text"))))
  expect_snapshot(error = TRUE, AgentResult(session_id = ""))
  expect_snapshot(error = TRUE, AgentResult(turns = "turn"))
  expect_snapshot(error = TRUE, AgentResult(usage = list(requests = 1)))
})
