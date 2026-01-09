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

# Hook timeout tests
test_that("HookMatcher stores timeout value", {
  hook <- HookMatcher$new(
    event = "PreToolUse",
    callback = function(...) NULL,
    timeout = 10
  )

  expect_equal(hook$timeout, 10)

  # Default timeout
  hook_default <- HookMatcher$new(
    event = "PreToolUse",
    callback = function(...) NULL
  )
  expect_equal(hook_default$timeout, 30)
})

test_that("HookMatcher with timeout=0 runs in main process", {
  # timeout=0 means run in main process (no callr)
  # We test this by checking that side effects work
  side_effect <- NULL

  hook <- HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      side_effect <<- "modified"
      HookResultPreToolUse(permission = "allow")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)
  registry$fire("PreToolUse", tool_name = "test", tool_input = list(), context = list())

  # Side effect should work with timeout=0 (main process)
  expect_equal(side_effect, "modified")
})

test_that("Hook callback error returns deny for PreToolUse", {
  hook <- HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(...) {
      stop("Callback error!")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # Should get deny result with error message (and warning)
  result <- NULL
  expect_warning(
    result <- registry$fire("PreToolUse", tool_name = "test", tool_input = list(), context = list()),
    "Hook.*failed"
  )

  expect_s3_class(result, "HookResultPreToolUse")
  expect_equal(result$permission, "deny")
  expect_true(grepl("Callback error", result$reason))
})

test_that("Hook callback error returns NULL for PostToolUse", {
  hook <- HookMatcher$new(
    event = "PostToolUse",
    timeout = 0,
    callback = function(...) {
      stop("PostToolUse error!")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # PostToolUse errors return NULL (fail-safe)
  result <- "not_null"
  expect_warning(
    result <- registry$fire(
      "PostToolUse",
      tool_name = "test",
      tool_result = "result",
      tool_error = NULL,
      context = list()
    ),
    "Hook.*failed"
  )

  expect_null(result)
})

test_that("Hook callback error returns NULL for Stop event", {
  hook <- HookMatcher$new(
    event = "Stop",
    timeout = 0,
    callback = function(...) {
      stop("Stop hook error!")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # Stop hook errors return NULL
  result <- "not_null"
  expect_warning(
    result <- registry$fire("Stop", reason = "complete", context = list()),
    "Hook.*failed"
  )

  expect_null(result)
})

test_that("HookResultStop has correct structure", {
  result <- HookResultStop()
  expect_s3_class(result, "HookResultStop")
  expect_s3_class(result, "HookResult")
  expect_true(result$handled)

  result_unhandled <- HookResultStop(handled = FALSE)
  expect_false(result_unhandled$handled)
})

test_that("HookResultPreCompact has correct structure", {
  result <- HookResultPreCompact()
  expect_s3_class(result, "HookResultPreCompact")
  expect_s3_class(result, "HookResult")
  expect_true(result$continue)
  expect_null(result$summary)

  result_with_summary <- HookResultPreCompact(
    continue = FALSE,
    summary = "Custom summary"
  )
  expect_false(result_with_summary$continue)
  expect_equal(result_with_summary$summary, "Custom summary")
})

test_that("Multiple hooks are called in order until non-NULL result", {
  call_order <- c()

  hook1 <- HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(...) {
      call_order <<- c(call_order, "hook1")
      NULL # Return NULL to continue to next hook
    }
  )

  hook2 <- HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(...) {
      call_order <<- c(call_order, "hook2")
      HookResultPreToolUse(permission = "deny")
    }
  )

  hook3 <- HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(...) {
      call_order <<- c(call_order, "hook3")
      HookResultPreToolUse(permission = "allow")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook1)
  registry$add(hook2)
  registry$add(hook3)

  result <- registry$fire("PreToolUse", tool_name = "test", tool_input = list(), context = list())

  # hook3 should NOT be called because hook2 returned non-NULL
  expect_equal(call_order, c("hook1", "hook2"))
  expect_equal(result$permission, "deny")
})

test_that("HookRegistry print method works", {
  registry <- HookRegistry$new()

  registry$add(HookMatcher$new(
    event = "PreToolUse",
    callback = function(...) NULL
  ))
  registry$add(HookMatcher$new(
    event = "PreToolUse",
    callback = function(...) NULL
  ))
  registry$add(HookMatcher$new(
    event = "PostToolUse",
    callback = function(...) NULL
  ))

  output <- capture.output(print(registry))
  output_text <- paste(output, collapse = "\n")

  expect_true(grepl("HookRegistry", output_text))
  expect_true(grepl("hooks:", output_text))
  expect_true(grepl("3 registered", output_text))
  expect_true(grepl("PreToolUse", output_text))
  expect_true(grepl("PostToolUse", output_text))
})

test_that("HookMatcher print method works", {
  hook <- HookMatcher$new(
    event = "PreToolUse",
    pattern = "^write",
    callback = function(...) NULL,
    timeout = 15
  )

  output <- capture.output(print(hook))
  output_text <- paste(output, collapse = "\n")

  expect_true(grepl("HookMatcher", output_text))
  expect_true(grepl("PreToolUse", output_text))
  expect_true(grepl("write", output_text))
  expect_true(grepl("15", output_text))
})
