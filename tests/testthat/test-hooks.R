# Tests for hook system

test_that("HookMatcher validates event type", {
  expect_error(
    HookMatcher$new(
      event = "InvalidEvent",
      callback = function(...) NULL
    ),
    "Invalid hook event"
  )
})

test_that("HookMatcher validates callback is function", {
  expect_error(
    HookMatcher$new(
      event = "PreToolUse",
      callback = "not a function"
    ),
    "must be a function"
  )
})

test_that("HookMatcher matches without pattern", {
  matcher <- HookMatcher$new(
    event = "PreToolUse",
    callback = function(...) NULL
  )

  # Should match any tool name when no pattern specified
  expect_true(matcher$matches("read_file"))
  expect_true(matcher$matches("write_file"))
  expect_true(matcher$matches("anything"))
  expect_true(matcher$matches(NULL))
})

test_that("HookMatcher matches with pattern", {
  matcher <- HookMatcher$new(
    event = "PreToolUse",
    pattern = "^write",
    callback = function(...) NULL
  )

  # Should match tools starting with "write"
  expect_true(matcher$matches("write_file"))
  expect_true(matcher$matches("write_csv"))

  # Should not match other tools
  expect_false(matcher$matches("read_file"))
  expect_false(matcher$matches("list_files"))
  expect_false(matcher$matches(NULL))
})

test_that("HookRegistry adds and retrieves hooks", {
  registry <- HookRegistry$new()

  expect_equal(registry$count(), 0)

  hook1 <- HookMatcher$new(
    event = "PreToolUse",
    callback = function(...) NULL
  )
  registry$add(hook1)

  expect_equal(registry$count(), 1)

  hook2 <- HookMatcher$new(
    event = "PostToolUse",
    callback = function(...) NULL
  )
  registry$add(hook2)

  expect_equal(registry$count(), 2)
})

test_that("HookRegistry filters by event", {
  registry <- HookRegistry$new()

  registry$add(HookMatcher$new(
    event = "PreToolUse",
    callback = function(...) NULL
  ))
  registry$add(HookMatcher$new(
    event = "PostToolUse",
    callback = function(...) NULL
  ))

  pre_hooks <- registry$get_hooks("PreToolUse")
  expect_length(pre_hooks, 1)

  post_hooks <- registry$get_hooks("PostToolUse")
  expect_length(post_hooks, 1)

  stop_hooks <- registry$get_hooks("Stop")
  expect_length(stop_hooks, 0)
})

test_that("HookRegistry filters by tool name", {
  registry <- HookRegistry$new()

  registry$add(HookMatcher$new(
    event = "PreToolUse",
    pattern = "^write",
    callback = function(...) NULL
  ))
  registry$add(HookMatcher$new(
    event = "PreToolUse",
    pattern = "^read",
    callback = function(...) NULL
  ))
  registry$add(HookMatcher$new(
    event = "PreToolUse",
    callback = function(...) NULL # No pattern - matches all
  ))

  # Should get write hook + universal hook
  write_hooks <- registry$get_hooks("PreToolUse", "write_file")
  expect_length(write_hooks, 2)

  # Should get read hook + universal hook
  read_hooks <- registry$get_hooks("PreToolUse", "read_file")
  expect_length(read_hooks, 2)

  # Should get only universal hook
  other_hooks <- registry$get_hooks("PreToolUse", "bash_command")
  expect_length(other_hooks, 1)
})

test_that("HookRegistry fire returns first non-NULL result", {
  registry <- HookRegistry$new()

  registry$add(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(...) NULL # Returns NULL
  ))
  registry$add(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(...) {
      HookResultPreToolUse(permission = "deny", reason = "test")
    }
  ))

  result <- registry$fire("PreToolUse", tool_name = "test")
  expect_s3_class(result, "HookResultPreToolUse")
  expect_equal(result$permission, "deny")
})

test_that("HookResultPreToolUse has correct structure", {
  result <- HookResultPreToolUse(permission = "allow")
  expect_s3_class(result, "HookResultPreToolUse")
  expect_s3_class(result, "HookResult")
  expect_equal(result$permission, "allow")
  expect_true(result$continue)

  result_deny <- HookResultPreToolUse(
    permission = "deny",
    reason = "test reason",
    continue = FALSE
  )
  expect_equal(result_deny$permission, "deny")
  expect_equal(result_deny$reason, "test reason")
  expect_false(result_deny$continue)
})

test_that("HookResultPostToolUse has correct structure", {
  result <- HookResultPostToolUse()
  expect_s3_class(result, "HookResultPostToolUse")
  expect_s3_class(result, "HookResult")
  expect_true(result$continue)

  result_stop <- HookResultPostToolUse(continue = FALSE)
  expect_false(result_stop$continue)
})

test_that("hook_block_dangerous_bash blocks dangerous commands", {
  hook <- hook_block_dangerous_bash()

  # Test dangerous commands
  dangerous_result <- hook$callback(
    tool_name = "run_bash",
    tool_input = list(command = "rm -rf /"),
    context = list()
  )
  expect_equal(dangerous_result$permission, "deny")

  sudo_result <- hook$callback(
    tool_name = "run_bash",
    tool_input = list(command = "sudo apt install something"),
    context = list()
  )
  expect_equal(sudo_result$permission, "deny")

  # Test safe commands
  safe_result <- hook$callback(
    tool_name = "run_bash",
    tool_input = list(command = "ls -la"),
    context = list()
  )
  expect_equal(safe_result$permission, "allow")
})

test_that("hook_limit_file_writes restricts directory", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir
  # Normalize to handle macOS /var -> /private/var symlink
  temp_dir <- normalizePath(temp_dir, mustWork = TRUE)

  hook <- hook_limit_file_writes(temp_dir)

  # Write inside allowed dir - should allow
  inside_result <- hook$callback(
    tool_name = "write_file",
    tool_input = list(path = file.path(temp_dir, "test.txt")),
    context = list()
  )
  expect_equal(inside_result$permission, "allow")

  # Write outside allowed dir - should deny
  outside_result <- hook$callback(
    tool_name = "write_file",
    tool_input = list(path = "/tmp/outside.txt"),
    context = list()
  )
  expect_equal(outside_result$permission, "deny")
})
