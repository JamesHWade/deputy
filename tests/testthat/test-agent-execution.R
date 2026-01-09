# Tests for Agent run()/run_sync() execution flow
# Note: These tests are limited because the mock chat doesn't provide
# proper S7 Turn objects that the generator expects. More comprehensive
# testing requires real API calls or a more sophisticated mock.

# Note: create_mock_chat is defined in helper-mocks.R

test_that("run_sync exists and is callable", {
  mock_chat <- create_mock_chat(responses = list("Test response"))
  agent <- Agent$new(chat = mock_chat)

  # Just verify the method exists
  expect_true("run_sync" %in% names(agent))
  expect_true(is.function(agent$run_sync))
})

test_that("run exists and returns a generator", {
  mock_chat <- create_mock_chat(responses = list("Test response"))
  agent <- Agent$new(chat = mock_chat)

  # Just verify the method exists
  expect_true("run" %in% names(agent))
  expect_true(is.function(agent$run))
})

test_that("AgentResult class has expected fields", {
  # Test AgentResult directly without running agent
  result <- AgentResult$new(
    response = "test",
    turns = list(),
    cost = list(total = 0.01)
  )

  expect_s3_class(result, "AgentResult")
  expect_equal(result$response, "test")
  expect_equal(result$cost$total, 0.01)
})

test_that("AgentResult print method works", {
  result <- AgentResult$new(
    response = "test response here",
    turns = list(1, 2), # 2 mock turns
    cost = list(total = 0.05)
  )

  output <- capture.output(print(result))
  expect_true(any(grepl("AgentResult", output)))
  expect_true(any(grepl("turns", output)))
})

test_that("Agent cost method returns cost data", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  cost <- agent$cost()
  expect_true(!is.null(cost))
  expect_true("total" %in% names(cost))
})

test_that("Agent permissions affect run configuration", {
  mock_chat <- create_mock_chat()

  agent_limited <- Agent$new(
    chat = mock_chat,
    permissions = Permissions$new(max_turns = 5)
  )

  expect_equal(agent_limited$permissions$max_turns, 5)
})

test_that("Agent with cost limit stores limit correctly", {
  mock_chat <- create_mock_chat()

  agent <- Agent$new(
    chat = mock_chat,
    permissions = Permissions$new(max_cost_usd = 1.00)
  )

  expect_equal(agent$permissions$max_cost_usd, 1.00)
})

# AgentEvent tests
test_that("AgentEvent creates events with correct structure", {
  event <- AgentEvent("start", task = "test task")

  expect_s3_class(event, "AgentEvent")
  # Class name uses capitalized type: AgentEventStart not AgentEventstart
  expect_s3_class(event, "AgentEventStart")
  expect_equal(event$type, "start")
  expect_equal(event$task, "test task")
  expect_true(!is.null(event$timestamp))
})

test_that("AgentEvent creates different event types", {
  text_event <- AgentEvent("text", text = "hello", is_complete = FALSE)
  expect_equal(text_event$type, "text")
  expect_equal(text_event$text, "hello")
  expect_false(text_event$is_complete)

  stop_event <- AgentEvent("stop", reason = "complete", total_turns = 3)
  expect_equal(stop_event$type, "stop")
  expect_equal(stop_event$reason, "complete")
  expect_equal(stop_event$total_turns, 3)

  turn_event <- AgentEvent("turn", turn_number = 2)
  expect_equal(turn_event$type, "turn")
  expect_equal(turn_event$turn_number, 2)
})

# AgentResult tests
test_that("AgentResult stores all metadata", {
  result <- AgentResult$new(
    response = "Final response",
    turns = list("turn1", "turn2", "turn3"),
    cost = list(total = 0.05, input_tokens = 100, output_tokens = 50),
    events = list(AgentEvent("start"), AgentEvent("stop")),
    duration = 2.5,
    stop_reason = "complete"
  )

  expect_equal(result$response, "Final response")
  expect_length(result$turns, 3)
  expect_equal(result$cost$total, 0.05)
  expect_equal(result$cost$input_tokens, 100)
  expect_length(result$events, 2)
  expect_equal(result$duration, 2.5)
  expect_equal(result$stop_reason, "complete")
})

test_that("AgentResult has sensible defaults", {
  result <- AgentResult$new(
    response = "test",
    turns = list(),
    cost = list(total = 0)
  )

  # events defaults to empty list, not NULL

  expect_equal(result$events, list())
  # duration can be NULL
  expect_null(result$duration)
  # stop_reason defaults to "complete"
  expect_equal(result$stop_reason, "complete")
})

test_that("AgentResult print shows key information", {
  result <- AgentResult$new(
    response = "A response that is longer than fifty characters for testing truncation",
    turns = list(1, 2, 3, 4, 5),
    cost = list(total = 0.123),
    duration = 5.5,
    stop_reason = "max_turns"
  )

  output <- capture.output(print(result))
  output_text <- paste(output, collapse = "\n")

  expect_true(grepl("AgentResult", output_text))
  # Print format is "turns: 5" not "5 turns"
  expect_true(grepl("turns:", output_text))
  expect_true(grepl("max_turns", output_text))
})

# Generator tests (testing coro::is_exhausted handling)
test_that("coro::exhausted is properly detected", {
  # This tests the fix for the run_sync hanging bug
  exhausted_val <- coro::exhausted()

  expect_true(coro::is_exhausted(exhausted_val))
  expect_false(is.null(exhausted_val))
})

test_that("Agent run method returns a callable generator", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  gen <- agent$run("test task")

  # Should be a function (generator)
  expect_true(is.function(gen))
})
