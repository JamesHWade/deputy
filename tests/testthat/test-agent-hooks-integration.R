# Integration tests for Agent hook execution during tool request processing
# These tests verify that hooks are properly integrated with the agent's
# tool request/result processing pipeline, specifically testing that
# PreToolUse hook denials correctly trigger ellmer::tool_reject()

test_that("Agent rejects tool when PreToolUse hook denies", {
  # Track if tool_reject was called
  reject_called <- FALSE
  reject_reason <- NULL

  # Mock ellmer::tool_reject to verify it gets called
  local_mocked_bindings(
    tool_reject = function(reason) {
      reject_called <<- TRUE
      reject_reason <<- reason
    },
    .package = "ellmer"
  )

  # Create a custom mock chat that exposes the tool request callback
  tool_request_callback <- NULL
  mock_chat <- create_mock_chat()

  # Wrap on_tool_request to capture the callback
  original_on_tool_request <- mock_chat$on_tool_request
  mock_chat$on_tool_request <- function(callback) {
    tool_request_callback <<- callback
    original_on_tool_request(callback)
  }

  # Create agent with tool and denying hook
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_read_file)
  )

  # Add hook that denies all PreToolUse events
  agent$hooks$add(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      HookResultPreToolUse(
        permission = "deny",
        reason = "Blocked by security hook"
      )
    }
  ))

  # Verify callback was registered
  expect_false(is.null(tool_request_callback))

  # Simulate a tool request from the LLM
  # This is what ellmer would call when the LLM requests a tool
  tool_request <- create_mock_tool_request(
    id = "call_test_123",
    name = "read_file",
    arguments = list(path = "test.txt")
  )

  # Call the registered callback (simulating ellmer's behavior)
  # Suppress the S7 class check warning (known issue in agent.R:732)
  suppressWarnings(tool_request_callback(tool_request))

  # Verify that tool_reject was called due to hook denial
  expect_true(reject_called)
  expect_equal(reject_reason, "Blocked by security hook")
})

test_that("Agent allows tool when PreToolUse hook permits", {
  # Track if tool_reject was called (it should NOT be)
  reject_called <- FALSE

  local_mocked_bindings(
    tool_reject = function(reason) {
      reject_called <<- TRUE
    },
    .package = "ellmer"
  )

  # Create mock chat and capture callback
  tool_request_callback <- NULL
  mock_chat <- create_mock_chat()
  original_on_tool_request <- mock_chat$on_tool_request
  mock_chat$on_tool_request <- function(callback) {
    tool_request_callback <<- callback
    original_on_tool_request(callback)
  }

  # Create agent with allowing hook
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_read_file)
  )

  # Add hook that allows the tool
  agent$hooks$add(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      HookResultPreToolUse(permission = "allow")
    }
  ))

  # Simulate tool request
  tool_request <- create_mock_tool_request(
    id = "call_test_456",
    name = "read_file",
    arguments = list(path = "test.txt")
  )

  # Call the callback (suppress S7 class check warning)
  suppressWarnings(tool_request_callback(tool_request))

  # Verify tool_reject was NOT called
  expect_false(reject_called)
})

test_that("Hook denial takes precedence over permission allow", {
  # This test verifies that hooks are checked AFTER permissions and
  # that hook denial can override permission allow

  # Track tool_reject calls
  reject_called <- FALSE
  reject_reason <- NULL

  local_mocked_bindings(
    tool_reject = function(reason) {
      reject_called <<- TRUE
      reject_reason <<- reason
    },
    .package = "ellmer"
  )

  # Create mock chat with callback capture
  tool_request_callback <- NULL
  mock_chat <- create_mock_chat()
  original_on_tool_request <- mock_chat$on_tool_request
  mock_chat$on_tool_request <- function(callback) {
    tool_request_callback <<- callback
    original_on_tool_request(callback)
  }

  # Create agent with permissive permissions (allows file reading)
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_read_file),
    permissions = Permissions$new(file_read = TRUE)
  )

  # Add hook that denies despite permissive permissions
  agent$hooks$add(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      HookResultPreToolUse(
        permission = "deny",
        reason = "Hook overrides permission"
      )
    }
  ))

  # Simulate tool request
  tool_request <- create_mock_tool_request(
    id = "call_test_abc",
    name = "read_file",
    arguments = list(path = "test.txt")
  )

  # Call the callback (suppress S7 class check warning)
  suppressWarnings(tool_request_callback(tool_request))

  # Verify tool_reject was called due to hook (not permission)
  expect_true(reject_called)
  expect_equal(reject_reason, "Hook overrides permission")
})
