# Tests for AgentEvent and AgentResult

test_that("AgentEvent creates correct structure", {
  event <- AgentEvent("start", task = "Test task")

  expect_s3_class(event, "AgentEvent")
  expect_s3_class(event, "AgentEventStart")
  expect_equal(event$type, "start")
  expect_equal(event$task, "Test task")
  expect_s3_class(event$timestamp, "POSIXct")
})

test_that("AgentEvent supports different types", {
  # Text event
  text_event <- AgentEvent("text", text = "Hello", is_complete = TRUE)
  expect_s3_class(text_event, "AgentEventText")
  expect_equal(text_event$text, "Hello")
  expect_true(text_event$is_complete)

  # Stop event
  stop_event <- AgentEvent("stop", reason = "complete", total_turns = 3)
  expect_s3_class(stop_event, "AgentEventStop")
  expect_equal(stop_event$reason, "complete")
  expect_equal(stop_event$total_turns, 3)

  # Turn event
  turn_event <- AgentEvent("turn", turn_number = 1)
  expect_s3_class(turn_event, "AgentEventTurn")
  expect_equal(turn_event$turn_number, 1)
})

test_that("AgentResult has correct structure", {
  result <- AgentResult$new(
    response = "Test response",
    turns = list("turn1", "turn2"),
    cost = list(input = 100, output = 50, cached = 0, total = 0.001),
    events = list(),
    duration = 1.5,
    stop_reason = "complete"
  )

  expect_s3_class(result, "AgentResult")
  expect_equal(result$response, "Test response")
  expect_equal(result$n_turns(), 2)
  expect_equal(result$duration, 1.5)
  expect_equal(result$stop_reason, "complete")
  expect_true(result$is_success())
})

test_that("AgentResult detects non-success states", {
  result_max_turns <- AgentResult$new(stop_reason = "max_turns")
  expect_false(result_max_turns$is_success())

  result_cost <- AgentResult$new(stop_reason = "cost_limit")
  expect_false(result_cost$is_success())

  result_hook <- AgentResult$new(stop_reason = "hook_requested_stop")
  expect_false(result_hook$is_success())
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

  result <- AgentResult$new(events = events)
  tool_calls <- result$tool_calls()

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

  result <- AgentResult$new(events = events)
  chunks <- result$text_chunks()

  expect_length(chunks, 2)
  expect_equal(chunks[1], "Hello ")
  expect_equal(chunks[2], "world!")
})

test_that("AgentResult defaults are sensible", {
  result <- AgentResult$new()

  expect_null(result$response)
  expect_equal(result$turns, list())
  expect_equal(result$cost$total, 0)
  expect_equal(result$events, list())
  expect_null(result$duration)
  expect_equal(result$stop_reason, "complete")
  expect_equal(result$n_turns(), 0)
  expect_true(result$is_success())
})
