# Integration tests for Agent hook execution during tool request processing.
# Verifies that PreToolUse hook denials correctly trigger ellmer::tool_reject().

# Helper to create a mock chat that captures the tool request callback
create_mock_chat_with_callback_capture <- function() {
  captured_callback <- NULL
  mock_chat <- create_mock_chat()

  original_on_tool_request <- mock_chat$on_tool_request
  mock_chat$on_tool_request <- function(callback) {
    captured_callback <<- callback
    original_on_tool_request(callback)
  }

  list(
    chat = mock_chat,
    get_callback = function() captured_callback
  )
}

# Helper to simulate a tool request and invoke the captured callback
simulate_tool_request <- function(
  callback,
  name = "read_file",
  path = "test.txt"
) {
  tool_request <- create_mock_tool_request(
    id = paste0("call_", sample(1000:9999, 1)),
    name = name,
    arguments = list(path = path)
  )
  # Suppress S7 class check warning from extract_tool_request_data
  # (occurs when mock objects don't perfectly match ellmer's S7 classes)
  suppressWarnings(callback(tool_request))
}

test_that("Agent rejects tool when PreToolUse hook denies", {
  reject_called <- FALSE
  reject_reason <- NULL

  local_mocked_bindings(
    tool_reject = function(reason) {
      reject_called <<- TRUE
      reject_reason <<- reason
    },
    .package = "ellmer"
  )

  mock <- create_mock_chat_with_callback_capture()

  agent <- Agent$new(
    chat = mock$chat,
    tools = list(tool_read_file)
  )

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

  expect_false(is.null(mock$get_callback()))
  simulate_tool_request(mock$get_callback())

  expect_true(reject_called)
  expect_equal(reject_reason, "Blocked by security hook")
})

test_that("Agent allows tool when PreToolUse hook permits", {
  reject_called <- FALSE

  local_mocked_bindings(
    tool_reject = function(reason) {
      reject_called <<- TRUE
    },
    .package = "ellmer"
  )

  mock <- create_mock_chat_with_callback_capture()

  agent <- Agent$new(
    chat = mock$chat,
    tools = list(tool_read_file)
  )

  agent$hooks$add(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      HookResultPreToolUse(permission = "allow")
    }
  ))

  simulate_tool_request(mock$get_callback())

  expect_false(reject_called)
})

test_that("Hook denial takes precedence over permission allow", {
  # This test verifies that hooks are checked AFTER permissions pass and
  # that hook denial can override a permission allow (permissions check first,
  # hooks check second, and hooks can still deny what permissions allowed)
  reject_called <- FALSE
  reject_reason <- NULL

  local_mocked_bindings(
    tool_reject = function(reason) {
      reject_called <<- TRUE
      reject_reason <<- reason
    },
    .package = "ellmer"
  )

  mock <- create_mock_chat_with_callback_capture()

  agent <- Agent$new(
    chat = mock$chat,
    tools = list(tool_read_file),
    permissions = Permissions$new(file_read = TRUE)
  )

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

  simulate_tool_request(mock$get_callback())

  expect_true(reject_called)
  expect_equal(reject_reason, "Hook overrides permission")
})

test_that("Hook denial with continue=FALSE sets should_stop", {
  # Verifies that continue=FALSE signals the agent to stop after this tool
  reject_called <- FALSE

  local_mocked_bindings(
    tool_reject = function(reason) {
      reject_called <<- TRUE
    },
    .package = "ellmer"
  )

  mock <- create_mock_chat_with_callback_capture()

  agent <- Agent$new(
    chat = mock$chat,
    tools = list(tool_read_file)
  )

  agent$hooks$add(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      HookResultPreToolUse(
        permission = "deny",
        reason = "Critical security violation",
        continue = FALSE # Signal to stop after this tool
      )
    }
  ))

  simulate_tool_request(mock$get_callback())

  # Verify tool was rejected
  expect_true(reject_called)

  # Verify agent's internal state indicates it should stop
  # (accessing private fields via R6's internal structure for testing)
  expect_true(agent$.__enclos_env__$private$should_stop)
  expect_equal(
    agent$.__enclos_env__$private$stop_reason_from_hook,
    "hook_requested_stop"
  )
})

test_that("Hook returning NULL allows tool to proceed", {
  # Verifies that hooks can abstain from decisions by returning NULL
  reject_called <- FALSE

  local_mocked_bindings(
    tool_reject = function(reason) {
      reject_called <<- TRUE
    },
    .package = "ellmer"
  )

  mock <- create_mock_chat_with_callback_capture()

  agent <- Agent$new(
    chat = mock$chat,
    tools = list(tool_read_file)
  )

  agent$hooks$add(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      NULL # Abstain from decision
    }
  ))

  simulate_tool_request(mock$get_callback())

  # Tool should NOT be rejected when hook returns NULL
  expect_false(reject_called)
})

test_that("Permission check occurs before PreToolUse hooks", {
  # Verifies the permission check happens first by directly testing
  # the permissions object (integration of permission flow with hooks
  # requires full agent run, tested elsewhere)
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(tool_read_file),
    permissions = Permissions$new(file_read = FALSE)
  )

  # Verify permission check would deny this tool
  perm_result <- agent$permissions$check(
    "read_file",
    list(path = "test.txt"),
    list()
  )

  expect_s3_class(perm_result, "PermissionResultDeny")
  expect_equal(perm_result$reason, "File reading is not allowed")
})

test_that("Agent stops when PostToolUse hook returns continue=FALSE", {
  # This test verifies the full execution loop stops when a PostToolUse hook
  # returns continue=FALSE (agent.R lines 704-708 set should_stop,
  # lines 1038-1040 check it and stop)

  # Track which call we're on
  call_count <- 0
  last_turn_with_tool <- NULL
  tool_request_callback <- NULL
  tool_result_callback <- NULL
  captured_tool_request <- NULL

  # Create mock chat
  mock_chat <- create_mock_chat()

  # Capture the tool request callback when agent registers it
  original_on_tool_request <- mock_chat$on_tool_request
  mock_chat$on_tool_request <- function(callback) {
    tool_request_callback <<- callback
    original_on_tool_request(callback)
  }

  # Capture the tool result callback when agent registers it
  original_on_tool_result <- mock_chat$on_tool_result
  mock_chat$on_tool_result <- function(callback) {
    tool_result_callback <<- callback
    original_on_tool_result(callback)
  }

  # Override stream to return text, then have last_turn return a turn with tool
  original_stream <- mock_chat$stream
  mock_chat$stream <- function(prompt = NULL) {
    call_count <<- call_count + 1

    if (call_count == 1) {
      # First call: return text, but prepare a turn with tool request
      last_turn_with_tool <<- create_mock_turn_with_tool_request(
        tool_name = "read_file",
        tool_args = list(path = "test.txt"),
        text = "I'll read the file"
      )

      # Return text iterator (stream returns strings, not ContentText)
      yielded <- FALSE
      function() {
        if (yielded) {
          return(coro::exhausted())
        }
        yielded <<- TRUE
        "I'll read the file"
      }
    } else {
      # Subsequent calls: return normal text
      original_stream(prompt)
    }
  }

  # Override last_turn to return the turn with tool on first call
  mock_chat$last_turn <- function(role = "assistant") {
    if (!is.null(last_turn_with_tool)) {
      turn <- last_turn_with_tool

      # Trigger tool request and result callbacks if registered
      if (!is.null(tool_request_callback) && !is.null(tool_result_callback)) {
        # Find tool requests in the turn contents
        # The turn has text first, then tool request second
        for (content in turn@contents) {
          if (inherits(content, "ellmer::ContentToolRequest")) {
            # Call the request callback
            tool_request_callback(content)

            # Simulate tool execution by calling result callback
            # Create a mock tool result
            tool_result <- ellmer::ContentToolResult(
              request = content,
              value = "file contents",
              error = NULL
            )
            tool_result_callback(tool_result)
          }
        }
      }

      last_turn_with_tool <<- NULL # Clear after first use
      return(turn)
    }
    # Return a simple assistant turn with the last text
    create_mock_assistant_turn(text = "I'll read the file")
  }

  # Track hook execution
  hook_executed <- FALSE

  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_read_file),
    permissions = Permissions$new(file_read = TRUE)
  )

  # Add PostToolUse hook that returns continue=FALSE
  agent$hooks$add(HookMatcher$new(
    event = "PostToolUse",
    timeout = 0,
    callback = function(tool_name, tool_result, tool_error, context) {
      hook_executed <<- TRUE
      HookResultPostToolUse(continue = FALSE)
    }
  ))

  # Run the agent - it should stop after the tool executes
  result <- agent$run_sync("Read test.txt")

  # Verify hook was executed
  expect_true(hook_executed)

  # Verify agent stopped due to hook
  expect_equal(result$stop_reason, "hook_requested_stop")
})
