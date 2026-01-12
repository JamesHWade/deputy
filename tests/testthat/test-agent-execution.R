# Tests for Agent run()/run_sync() execution flow
# The mock chat now provides proper S7 Turn objects for testing.
# Helper functions for S7 mocks are defined in helper-mocks.R:
# - create_mock_assistant_turn()
# - create_mock_user_turn()
# - create_mock_tool_request()
# - create_mock_turn_with_tool_request()

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

# S7 Turn mock tests
# Note: S7 classes use namespaced names like "ellmer::AssistantTurn"
test_that("create_mock_assistant_turn creates valid S7 object", {
  turn <- create_mock_assistant_turn(text = "Hello world")

  # S7 objects have namespaced class names
  expect_true(inherits(turn, "ellmer::AssistantTurn"))
  expect_equal(turn@text, "Hello world")
  expect_true(length(turn@contents) >= 1)
  expect_true(inherits(turn@contents[[1]], "ellmer::ContentText"))
})

test_that("create_mock_user_turn creates valid S7 object", {
  turn <- create_mock_user_turn(text = "User message")

  expect_true(inherits(turn, "ellmer::UserTurn"))
  expect_equal(turn@text, "User message")
})

test_that("create_mock_tool_request creates valid S7 object", {
  request <- create_mock_tool_request(
    id = "call_abc",
    name = "read_file",
    arguments = list(path = "test.txt")
  )

  expect_true(inherits(request, "ellmer::ContentToolRequest"))
  expect_equal(request@id, "call_abc")
  expect_equal(request@name, "read_file")
  expect_equal(request@arguments$path, "test.txt")
})

test_that("create_mock_turn_with_tool_request creates turn with tool", {
  turn <- create_mock_turn_with_tool_request(
    tool_name = "write_file",
    tool_args = list(path = "out.txt", content = "data")
  )

  expect_true(inherits(turn, "ellmer::AssistantTurn"))

  # Find the tool request in contents using namespaced class
  tool_requests <- Filter(
    function(c) inherits(c, "ellmer::ContentToolRequest"),
    turn@contents
  )

  expect_length(tool_requests, 1)
  expect_equal(tool_requests[[1]]@name, "write_file")
})

test_that("mock chat last_turn returns proper S7 AssistantTurn", {
  mock_chat <- create_mock_chat(responses = list("Test response"))
  agent <- Agent$new(chat = mock_chat)

  # Call chat to populate response
  mock_chat$chat("prompt")

  # Verify last_turn returns S7 object
  last <- mock_chat$last_turn()
  expect_true(inherits(last, "ellmer::AssistantTurn"))
  expect_equal(last@text, "Test response")
})

test_that("mock chat stream returns strings", {
  mock_chat <- create_mock_chat(responses = list("Streamed text"))

  # Get stream iterator
  stream_iter <- mock_chat$stream("prompt")

  # First call should return a string (agent expects strings, not ContentText)
  content <- stream_iter()
  expect_type(content, "character")
  expect_equal(content, "Streamed text")

  # Second call should be exhausted
  next_val <- stream_iter()
  expect_true(coro::is_exhausted(next_val))
})

test_that("Agent can access S7 turn properties via @ accessor", {
  mock_chat <- create_mock_chat(responses = list("Response text"))
  agent <- Agent$new(chat = mock_chat)

  mock_chat$chat("prompt")
  last <- agent$chat$last_turn()

  # Should be able to access S7 properties
  expect_equal(last@text, "Response text")
  expect_true(is.list(last@contents))
})

# ============================================================================
# Streaming fallback warning event tests
# ============================================================================

test_that("run emits warning event when streaming fails and falls back", {
  # This test verifies that when streaming fails, the agent emits a "warning"
  # AgentEvent that applications can use to surface the degraded mode to users

  mock_chat <- create_mock_chat(responses = list("Fallback response"))

  # Override stream to fail
  mock_chat$stream <- function(prompt = NULL) {
    stop("Simulated streaming failure")
  }

  # Override chat (fallback) to succeed
  mock_chat$chat <- function(prompt = NULL) {
    "Fallback response"
  }

  # Override last_turn
  mock_chat$last_turn <- function(role = "assistant") {
    create_mock_assistant_turn(text = "Fallback response")
  }

  agent <- Agent$new(chat = mock_chat)

  # Collect events from the generator
  events <- list()
  gen <- agent$run("Test task")
  suppressWarnings({
    while (!coro::is_exhausted(e <- gen())) {
      events <- c(events, list(e))
    }
  })

  # Find warning events
  warning_events <- Filter(function(e) e$type == "warning", events)

  # Should have at least one warning event

  expect_true(length(warning_events) >= 1)

  # Warning event should contain relevant information
  warning_event <- warning_events[[1]]
  expect_equal(
    warning_event$message,
    "Streaming failed, falling back to non-streaming"
  )
  expect_true(grepl("Simulated streaming failure", warning_event$details))
})

test_that("run_sync collects warning events in result", {
  # This test verifies that warning events are collected in the AgentResult
  # so applications using run_sync can also access them

  mock_chat <- create_mock_chat(responses = list("Fallback response"))

  # Override stream to fail
  mock_chat$stream <- function(prompt = NULL) {
    stop("Stream error")
  }

  # Override chat (fallback) to succeed
  mock_chat$chat <- function(prompt = NULL) {
    "Fallback response"
  }

  # Override last_turn
  mock_chat$last_turn <- function(role = "assistant") {
    create_mock_assistant_turn(text = "Fallback response")
  }

  agent <- Agent$new(chat = mock_chat)

  result <- suppressWarnings(agent$run_sync("Test task"))

  # Result should contain events including the warning
  warning_events <- Filter(function(e) e$type == "warning", result$events)
  expect_true(length(warning_events) >= 1)
})

test_that("AgentEvent warning type has correct structure", {
  event <- AgentEvent(
    "warning",
    message = "Test warning",
    details = "Some details"
  )

  expect_s3_class(event, "AgentEvent")
  expect_s3_class(event, "AgentEventWarning")
  expect_equal(event$type, "warning")
  expect_equal(event$message, "Test warning")
  expect_equal(event$details, "Some details")
  expect_true(!is.null(event$timestamp))
})

# ============================================================================
# Agent Loop Integration Tests
# Tests for the full execution flow of run() and run_sync()
# ============================================================================

test_that("run_sync accumulates events from generator", {
  # This test verifies that run_sync correctly collects all events from the
  # generator and returns them in the AgentResult

  mock_chat <- create_mock_chat(responses = list("Hello, world!"))

  # Override stream to return plain strings (agent expects strings, not ContentText)
  mock_chat$stream <- function(prompt = NULL) {
    yielded <- FALSE
    function() {
      if (yielded) {
        return(coro::exhausted())
      }
      yielded <<- TRUE
      "Hello, world!"
    }
  }

  # Override last_turn to avoid index error
  mock_chat$last_turn <- function(role = "assistant") {
    create_mock_assistant_turn(text = "Hello, world!")
  }

  agent <- Agent$new(chat = mock_chat)

  result <- agent$run_sync("Say hello")

  # Verify result contains events
  expect_s3_class(result, "AgentResult")
  expect_true(length(result$events) > 0)

  # Should have at least: start, text, text_complete, turn, stop
  event_types <- sapply(result$events, function(e) e$type)
  expect_true("start" %in% event_types)
  expect_true("stop" %in% event_types)
})

test_that("run_sync fires SessionStart hook before first turn", {
  session_start_fired <- FALSE
  session_start_context <- NULL

  mock_chat <- create_mock_chat(responses = list("Response"))

  mock_chat$stream <- function(prompt = NULL) {
    yielded <- FALSE
    function() {
      if (yielded) {
        return(coro::exhausted())
      }
      yielded <<- TRUE
      "Response"
    }
  }

  # Override last_turn to avoid index error
  mock_chat$last_turn <- function(role = "assistant") {
    create_mock_assistant_turn(text = "Response")
  }

  agent <- Agent$new(chat = mock_chat)

  # Add SessionStart hook
  agent$hooks$add(HookMatcher$new(
    event = "SessionStart",
    timeout = 0,
    callback = function(context) {
      session_start_fired <<- TRUE
      session_start_context <<- context
      NULL
    }
  ))

  result <- agent$run_sync("Test task")

  # Verify SessionStart hook was fired

  expect_true(session_start_fired)

  # Verify context contains expected fields
  expect_true(!is.null(session_start_context$working_dir))
  expect_true(!is.null(session_start_context$permissions))
})

test_that("run_sync fires Stop and SessionEnd hooks after completion", {
  stop_fired <- FALSE
  session_end_fired <- FALSE
  stop_reason_received <- NULL
  session_end_reason_received <- NULL

  mock_chat <- create_mock_chat(responses = list("Response"))

  mock_chat$stream <- function(prompt = NULL) {
    yielded <- FALSE
    function() {
      if (yielded) {
        return(coro::exhausted())
      }
      yielded <<- TRUE
      "Response"
    }
  }

  # Override last_turn to avoid index error
  mock_chat$last_turn <- function(role = "assistant") {
    create_mock_assistant_turn(text = "Response")
  }

  agent <- Agent$new(chat = mock_chat)

  # Add Stop hook
  agent$hooks$add(HookMatcher$new(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context) {
      stop_fired <<- TRUE
      stop_reason_received <<- reason
      NULL
    }
  ))

  # Add SessionEnd hook
  agent$hooks$add(HookMatcher$new(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context) {
      session_end_fired <<- TRUE
      session_end_reason_received <<- reason
      NULL
    }
  ))

  result <- agent$run_sync("Test task")

  # Verify both hooks were fired
  expect_true(stop_fired)
  expect_true(session_end_fired)

  # Verify both received the correct stop reason
  expect_equal(stop_reason_received, "complete")
  expect_equal(session_end_reason_received, "complete")
})

test_that("run_sync warns when approaching cost limit (90%)", {
  # This test verifies that a warning is issued when cost reaches 90% of limit

  mock_chat <- create_mock_chat(responses = list("Response"))

  # Override stream to return strings
  mock_chat$stream <- function(prompt = NULL) {
    yielded <- FALSE
    function() {
      if (yielded) {
        return(coro::exhausted())
      }
      yielded <<- TRUE
      "Response"
    }
  }

  # Override last_turn to avoid index error
  mock_chat$last_turn <- function(role = "assistant") {
    create_mock_assistant_turn(text = "Response")
  }

  # Override get_tokens to return high cost (90% of $1.00 = $0.90)
  mock_chat$get_tokens <- function() {
    data.frame(
      input = 1000,
      output = 500,
      cached_input = 0,
      cost = 0.95 # 95% of $1.00 limit - should trigger warning
    )
  }

  agent <- Agent$new(
    chat = mock_chat,
    permissions = Permissions$new(max_cost_usd = 1.00)
  )

  # Capture warnings
  warnings_raised <- character()
  result <- withCallingHandlers(
    agent$run_sync("Test task"),
    warning = function(w) {
      warnings_raised <<- c(warnings_raised, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  # Should have received a cost warning
  cost_warnings <- grep("cost limit", warnings_raised, value = TRUE)
  expect_true(length(cost_warnings) > 0)
})

test_that("run_sync stops when cost limit is reached", {
  # This test verifies that the agent stops when cost exceeds the limit

  mock_chat <- create_mock_chat(responses = list("Response 1", "Response 2"))

  # Override stream to return strings
  mock_chat$stream <- function(prompt = NULL) {
    yielded <- FALSE
    function() {
      if (yielded) {
        return(coro::exhausted())
      }
      yielded <<- TRUE
      "Response"
    }
  }

  # Override last_turn to avoid index error
  mock_chat$last_turn <- function(role = "assistant") {
    create_mock_assistant_turn(text = "Response")
  }

  # Override get_tokens to return cost exceeding limit
  mock_chat$get_tokens <- function() {
    data.frame(
      input = 10000,
      output = 5000,
      cached_input = 0,
      cost = 1.50 # Exceeds $1.00 limit
    )
  }

  agent <- Agent$new(
    chat = mock_chat,
    permissions = Permissions$new(max_cost_usd = 1.00)
  )

  # Suppress warnings for this test
  result <- suppressWarnings(agent$run_sync("Test task"))

  # Agent should stop with cost_limit reason
  expect_equal(result$stop_reason, "cost_limit")
})

test_that("run_sync detects stalled responses", {
  # This test verifies that a warning is issued when agent returns identical
  # responses (indicating a possible stall)

  call_count <- 0

  mock_chat <- create_mock_chat()

  # Override stream to return the same response twice (simulating stall)
  mock_chat$stream <- function(prompt = NULL) {
    call_count <<- call_count + 1
    yielded <- FALSE
    function() {
      if (yielded) {
        return(coro::exhausted())
      }
      yielded <<- TRUE
      "I am stuck in a loop" # Same response every time
    }
  }

  # Override last_turn to return a turn that looks like it has tool requests
  # (to keep the agent running for multiple turns)
  turn_count <- 0
  mock_chat$last_turn <- function(role = "assistant") {
    turn_count <<- turn_count + 1
    if (turn_count <= 2) {
      # First two turns have a tool request to keep agent running
      create_mock_turn_with_tool_request(
        tool_name = "test_tool",
        tool_args = list(),
        text = "I am stuck in a loop"
      )
    } else {
      # Third turn is just text (no tool request) to stop
      create_mock_assistant_turn(text = "I am stuck in a loop")
    }
  }

  # Create a simple test tool
  test_tool <- ellmer::tool(
    fun = function() "result",
    name = "test_tool",
    description = "A test tool",
    arguments = list()
  )

  agent <- Agent$new(
    chat = mock_chat,
    tools = list(test_tool),
    permissions = Permissions$new(max_turns = 5)
  )

  # Capture warnings
  warnings_raised <- character()
  result <- withCallingHandlers(
    agent$run_sync("Test task"),
    warning = function(w) {
      warnings_raised <<- c(warnings_raised, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  # Should have received a stall warning
  stall_warnings <- grep("stalled", warnings_raised, value = TRUE)
  expect_true(length(stall_warnings) > 0)
})

# ============================================================================
# S7 inherits() Regression Tests
# These tests ensure the ellmer:: namespace prefix is used correctly
# ============================================================================

test_that("has_tool_requests correctly identifies S7 ContentToolRequest", {
  # This test verifies the S7 inherits() fix for has_tool_requests
  # If someone reverts to inherits(x, "ContentToolRequest") this will fail
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Create a turn WITH a tool request using actual S7 objects

  turn_with_request <- create_mock_turn_with_tool_request(
    tool_name = "read_file",
    tool_args = list(path = "test.txt")
  )

  # Access private method - should return TRUE for turn with tool request
  result <- agent$.__enclos_env__$private$has_tool_requests(turn_with_request)
  expect_true(result)

  # Create a turn WITHOUT tool requests
  turn_without_request <- create_mock_assistant_turn(text = "Just text")
  result2 <- agent$.__enclos_env__$private$has_tool_requests(
    turn_without_request
  )
  expect_false(result2)

  # NULL turn should return FALSE
  result3 <- agent$.__enclos_env__$private$has_tool_requests(NULL)
  expect_false(result3)
})

test_that("get_tool_annotation works with S7 ToolDef objects", {
  # This test verifies the S7 inherits() fix for get_tool_annotation
  # If someone reverts to inherits(tool, "ToolDef") this will fail

  # Create actual S7 tool with annotations
  test_tool <- ellmer::tool(
    fun = function() "result",
    name = "test_tool",
    description = "A test tool",
    arguments = list(),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      destructive_hint = FALSE
    )
  )

  # Verify it's an S7 ToolDef with namespace prefix
  expect_true(inherits(test_tool, "ellmer::ToolDef"))

  # get_tool_annotation should extract values correctly
  expect_true(get_tool_annotation(test_tool, "read_only_hint", default = FALSE))
  expect_false(get_tool_annotation(
    test_tool,
    "destructive_hint",
    default = TRUE
  ))
  expect_null(get_tool_annotation(test_tool, "nonexistent"))

  # Non-ToolDef objects should return default
  expect_equal(
    get_tool_annotation(list(), "read_only_hint", default = "default"),
    "default"
  )
  expect_null(get_tool_annotation("not a tool", "annotation"))
})

test_that("run_sync stops with max_turns reason when limit reached", {
  # This test verifies the max_turns stop reason
  mock_chat <- create_mock_chat()

  # Keep returning tool requests to force multiple turns
  mock_chat$stream <- function(prompt = NULL) {
    yielded <- FALSE
    function() {
      if (yielded) {
        return(coro::exhausted())
      }
      yielded <<- TRUE
      "Response"
    }
  }

  turn_count <- 0
  mock_chat$last_turn <- function(role = "assistant") {
    turn_count <<- turn_count + 1
    # Always return turn with tool request to keep looping
    create_mock_turn_with_tool_request(
      tool_name = "test_tool",
      tool_args = list(),
      text = paste("Response", turn_count)
    )
  }

  test_tool <- ellmer::tool(
    fun = function() "result",
    name = "test_tool",
    description = "A test tool",
    arguments = list()
  )

  agent <- Agent$new(
    chat = mock_chat,
    tools = list(test_tool),
    permissions = Permissions$new(max_turns = 2)
  )

  result <- suppressWarnings(agent$run_sync("Test task"))
  expect_equal(result$stop_reason, "max_turns")
})
