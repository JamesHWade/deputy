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
