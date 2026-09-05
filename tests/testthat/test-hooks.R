test_that("SessionStart is a valid hook event", {
  # Should not error when creating a SessionStart hook
  hook <- HookMatcher$new(
    event = "SessionStart",
    callback = function(context) {
      NULL
    }
  )
  expect_s3_class(hook, "HookMatcher")
  expect_equal(hook$event, "SessionStart")
})

test_that("SessionEnd is a valid hook event", {
  # Should not error when creating a SessionEnd hook
  hook <- HookMatcher$new(
    event = "SessionEnd",
    callback = function(reason, context) {
      NULL
    }
  )
  expect_s3_class(hook, "HookMatcher")
  expect_equal(hook$event, "SessionEnd")
})

test_that("SessionStart hook fires with correct context", {
  received_context <- NULL

  hook <- HookMatcher$new(
    event = "SessionStart",
    timeout = 0,
    callback = function(context) {
      received_context <<- context
      NULL
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # Fire the hook with test context
  test_context <- list(
    working_dir = "/test/dir",
    permissions = list(mode = "standard"),
    provider = list(name = "openai", model = "gpt-4o"),
    tools_count = 5
  )

  registry$fire("SessionStart", context = test_context)

  expect_equal(received_context$working_dir, "/test/dir")
  expect_equal(received_context$permissions$mode, "standard")
  expect_equal(received_context$provider$name, "openai")
  expect_equal(received_context$tools_count, 5)
})

test_that("SessionEnd hook fires with correct reason and context", {
  received_reason <- NULL
  received_context <- NULL

  hook <- HookMatcher$new(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context) {
      received_reason <<- reason
      received_context <<- context
      NULL
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # Fire the hook with test data
  test_context <- list(
    working_dir = "/test/dir",
    total_turns = 10,
    cost = list(input = 100, output = 50, total = 0.005)
  )

  registry$fire("SessionEnd", reason = "complete", context = test_context)

  expect_equal(received_reason, "complete")
  expect_equal(received_context$working_dir, "/test/dir")
  expect_equal(received_context$total_turns, 10)
  expect_equal(received_context$cost$total, 0.005)
})

test_that("SessionEnd receives different stop reasons", {
  reasons_received <- c()

  hook <- HookMatcher$new(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context) {
      reasons_received <<- c(reasons_received, reason)
      NULL
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # Test different stop reasons
  for (reason in c(
    "complete",
    "request_limit",
    "cost_limit",
    "hook_requested_stop"
  )) {
    registry$fire("SessionEnd", reason = reason, context = list())
  }

  expect_equal(
    reasons_received,
    c("complete", "request_limit", "cost_limit", "hook_requested_stop")
  )
})
