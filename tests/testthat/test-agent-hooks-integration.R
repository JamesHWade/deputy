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
