test_that("HookMatcher validates event type", {
  expect_error(
    HookMatcher(
      event = "InvalidEvent",
      callback = function(...) NULL
    ),
    "Invalid hook event"
  )
})

test_that("HookMatcher validates callback is function", {
  expect_error(
    HookMatcher(
      event = "PreToolUse",
      callback = "not a function"
    ),
    "must be a function"
  )
})

test_that("HookMatcher fields are immutable after construction", {
  callback <- function(...) NULL
  matcher <- HookMatcher(
    event = "PreToolUse",
    pattern = "^write",
    callback = callback,
    timeout = 5
  )

  expect_error(
    matcher@event <- "PostToolUse",
    "read-only after construction"
  )
  expect_error(
    matcher@pattern <- "^read",
    "read-only after construction"
  )
  expect_error(
    matcher@callback <- function(...) TRUE,
    "read-only after construction"
  )
  expect_error(
    matcher@timeout <- 0,
    "read-only after construction"
  )

  expect_equal(matcher@event, "PreToolUse")
  expect_equal(matcher@pattern, "^write")
  expect_identical(matcher@callback, callback)
  expect_equal(matcher@timeout, 5)
})

test_that("HookMatcher matches without pattern", {
  matcher <- HookMatcher(
    event = "PreToolUse",
    callback = function(...) NULL
  )

  # Should match any tool name when no pattern specified
  expect_true(hook_matches(matcher, "read_file"))
  expect_true(hook_matches(matcher, "write_file"))
  expect_true(hook_matches(matcher, "anything"))
  expect_true(hook_matches(matcher, NULL))
})

test_that("HookMatcher matches with pattern", {
  matcher <- HookMatcher(
    event = "PreToolUse",
    pattern = "^write",
    callback = function(...) NULL
  )

  # Should match tools starting with "write"
  expect_true(hook_matches(matcher, "write_file"))
  expect_true(hook_matches(matcher, "write_csv"))

  # Should not match other tools
  expect_false(hook_matches(matcher, "read_file"))
  expect_false(hook_matches(matcher, "list_files"))
  expect_false(hook_matches(matcher, NULL))
})

test_that("HookRegistry adds and retrieves hooks", {
  registry <- HookRegistry$new()

  expect_equal(registry$count(), 0)

  hook1 <- HookMatcher(
    event = "PreToolUse",
    callback = function(...) NULL
  )
  registry$add(hook1)

  expect_equal(registry$count(), 1)

  hook2 <- HookMatcher(
    event = "PostToolUse",
    callback = function(...) NULL
  )
  registry$add(hook2)

  expect_equal(registry$count(), 2)
})

test_that("HookRegistry filters by event", {
  registry <- HookRegistry$new()

  registry$add(HookMatcher(
    event = "PreToolUse",
    callback = function(...) NULL
  ))
  registry$add(HookMatcher(
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

  registry$add(HookMatcher(
    event = "PreToolUse",
    pattern = "^write",
    callback = function(...) NULL
  ))
  registry$add(HookMatcher(
    event = "PreToolUse",
    pattern = "^read",
    callback = function(...) NULL
  ))
  registry$add(HookMatcher(
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

  registry$add(HookMatcher(
    event = "PreToolUse",
    timeout = 0,
    callback = function(...) NULL # Returns NULL
  ))
  registry$add(HookMatcher(
    event = "PreToolUse",
    timeout = 0,
    callback = function(...) {
      HookResultPreToolUse(permission = "deny", reason = "test")
    }
  ))

  result <- registry$fire("PreToolUse", tool_name = "test")
  expect_s7_class(result, HookResultPreToolUse)
  expect_equal(result$permission, "deny")
})

test_that("HookMatcher stores timeout value", {
  hook <- HookMatcher(
    event = "PreToolUse",
    callback = function(...) NULL,
    timeout = 10
  )

  expect_equal(hook@timeout, 10)

  # Default timeout
  hook_default <- HookMatcher(
    event = "PreToolUse",
    callback = function(...) NULL
  )
  expect_equal(hook_default@timeout, 0)
})

test_that("HookMatcher with timeout=0 runs in main process", {
  # timeout=0 means run in main process (no callr)
  # We test this by checking that side effects work
  side_effect <- NULL

  hook <- HookMatcher(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      side_effect <<- "modified"
      HookResultPreToolUse(permission = "allow")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)
  registry$fire(
    "PreToolUse",
    tool_name = "test",
    tool_input = list(),
    context = list()
  )

  # Side effect should work with timeout=0 (main process)
  expect_equal(side_effect, "modified")
})

test_that("Hook callback error returns deny for PreToolUse", {
  hook <- HookMatcher(
    event = "PreToolUse",
    timeout = 0,
    callback = function(...) {
      stop("Callback error!")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # Should get deny result with error message (and alert)
  result <- NULL
  expect_message(
    result <- registry$fire(
      "PreToolUse",
      tool_name = "test",
      tool_input = list(),
      context = list()
    ),
    "PreToolUse hook failed"
  )

  expect_s7_class(result, HookResultPreToolUse)
  expect_equal(result$permission, "deny")
  expect_true(grepl("Callback error", result$reason))
})

test_that("Hook callback error returns NULL for PostToolUse", {
  hook <- HookMatcher(
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
  expect_message(
    result <- registry$fire(
      "PostToolUse",
      tool_name = "test",
      tool_result = "result",
      tool_error = NULL,
      context = list()
    ),
    "PostToolUse hook failed"
  )

  expect_null(result)
})

test_that("Hook callback error returns NULL for Stop event", {
  hook <- HookMatcher(
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
  expect_message(
    result <- registry$fire("Stop", reason = "complete", context = list()),
    "Stop hook failed"
  )

  expect_null(result)
})

test_that("Multiple hooks are called in order until non-NULL result", {
  call_order <- c()

  hook1 <- HookMatcher(
    event = "PreToolUse",
    timeout = 0,
    callback = function(...) {
      call_order <<- c(call_order, "hook1")
      NULL # Return NULL to continue to next hook
    }
  )

  hook2 <- HookMatcher(
    event = "PreToolUse",
    timeout = 0,
    callback = function(...) {
      call_order <<- c(call_order, "hook2")
      HookResultPreToolUse(permission = "deny")
    }
  )

  hook3 <- HookMatcher(
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

  result <- registry$fire(
    "PreToolUse",
    tool_name = "test",
    tool_input = list(),
    context = list()
  )

  # hook3 should NOT be called because hook2 returned non-NULL
  expect_equal(call_order, c("hook1", "hook2"))
  expect_equal(result$permission, "deny")
})

test_that("HookRegistry print method works", {
  registry <- HookRegistry$new()

  registry$add(HookMatcher(
    event = "PreToolUse",
    callback = function(...) NULL
  ))
  registry$add(HookMatcher(
    event = "PreToolUse",
    callback = function(...) NULL
  ))
  registry$add(HookMatcher(
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
  hook <- HookMatcher(
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

# SessionStart and SessionEnd hook tests

test_that("HookRegistry filters SessionStart and SessionEnd events", {
  registry <- HookRegistry$new()

  registry$add(HookMatcher(
    event = "SessionStart",
    callback = function(context) NULL
  ))
  registry$add(HookMatcher(
    event = "SessionEnd",
    callback = function(reason, context) NULL
  ))
  registry$add(HookMatcher(
    event = "PreToolUse",
    callback = function(...) NULL
  ))

  start_hooks <- registry$get_hooks("SessionStart")
  expect_length(start_hooks, 1)

  end_hooks <- registry$get_hooks("SessionEnd")
  expect_length(end_hooks, 1)

  pre_hooks <- registry$get_hooks("PreToolUse")
  expect_length(pre_hooks, 1)
})

test_that("Hook callback error returns NULL for SessionStart", {
  hook <- HookMatcher(
    event = "SessionStart",
    timeout = 0,
    callback = function(context) {
      stop("SessionStart error!")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # SessionStart errors return NULL (fail-safe)
  result <- "not_null"
  expect_message(
    result <- registry$fire("SessionStart", context = list()),
    "SessionStart hook failed"
  )

  expect_null(result)
})

test_that("Hook callback error returns NULL for SessionEnd", {
  hook <- HookMatcher(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context) {
      stop("SessionEnd error!")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # SessionEnd errors return NULL (fail-safe) and produce message
  result <- "not_null"
  expect_message(
    result <- registry$fire(
      "SessionEnd",
      reason = "complete",
      context = list()
    ),
    "SessionEnd hook failed"
  )

  expect_null(result)
})

# Tests for hook error tracking

test_that("HookRegistry tracks errors in last_errors()", {
  hook <- HookMatcher(
    event = "PostToolUse",
    timeout = 0,
    callback = function(tool_name, tool_result, tool_error, context) {
      stop("Logging failed!")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # Clear any existing errors
  registry$clear_errors()
  expect_length(registry$last_errors(), 0)

  # Fire the hook (will error)
  suppressMessages(
    registry$fire(
      "PostToolUse",
      tool_name = "test_tool",
      tool_result = "result",
      tool_error = NULL,
      context = list()
    )
  )

  # Check error was tracked
  errors <- registry$last_errors()
  expect_length(errors, 1)
  expect_equal(errors[[1]]$event, "PostToolUse")
  expect_equal(errors[[1]]$tool_name, "test_tool")
  expect_true(grepl("Logging failed", errors[[1]]$error))
  expect_s3_class(errors[[1]]$timestamp, "POSIXct")
})

test_that("HookRegistry clear_errors removes tracked errors", {
  hook <- HookMatcher(
    event = "SessionStart",
    timeout = 0,
    callback = function(context) {
      stop("Init failed!")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # Generate an error
  suppressMessages(
    registry$fire("SessionStart", context = list())
  )
  expect_length(registry$last_errors(), 1)

  # Clear errors
  registry$clear_errors()
  expect_length(registry$last_errors(), 0)
})

test_that("Hook errors show context-specific messages", {
  # PostToolUse error message
  hook <- HookMatcher(
    event = "PostToolUse",
    timeout = 0,
    callback = function(...) stop("error")
  )
  registry <- HookRegistry$new()
  registry$add(hook)

  expect_message(
    registry$fire(
      "PostToolUse",
      tool_name = "x",
      tool_input = list(),
      tool_result = "",
      context = list()
    ),
    "audit/logging may be incomplete"
  )
})

test_that("PreToolUse errors still deny and use cli_alert_danger", {
  hook <- HookMatcher(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      stop("Security check failed!")
    }
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # Should still deny even with cli_alert_danger
  result <- NULL
  expect_message(
    result <- registry$fire(
      "PreToolUse",
      tool_name = "bash",
      tool_input = list(),
      context = list()
    ),
    "denying tool for safety"
  )

  expect_equal(result$permission, "deny")
  expect_true(grepl("Security check failed", result$reason))

  # Error should also be tracked
  errors <- registry$last_errors()
  expect_length(errors, 1)
  expect_equal(errors[[1]]$event, "PreToolUse")
})

test_that("Hook timeout warns once when callr not installed", {
  # Mock rlang::is_installed to return FALSE for callr
  local_mocked_bindings(
    is_installed = function(pkg) {
      if (pkg == "callr") FALSE else TRUE
    },
    .package = "rlang"
  )

  hook <- HookMatcher(
    event = "PostToolUse",
    timeout = 5, # timeout > 0 triggers the check
    callback = function(...) NULL
  )

  registry <- HookRegistry$new()
  registry$add(hook)

  # First call should warn
  expect_warning(
    registry$fire(
      "PostToolUse",
      tool_name = "test",
      tool_input = list(),
      tool_result = "result",
      context = list()
    ),
    "callr.*not installed"
  )

  # Second call should NOT warn (only warns once)
  expect_no_warning(
    registry$fire(
      "PostToolUse",
      tool_name = "test",
      tool_input = list(),
      tool_result = "result",
      context = list()
    )
  )
})

test_that("fire() stays synchronous when no callback returns a promise", {
  registry <- HookRegistry$new()
  registry$add(HookMatcher(
    "PreToolUse",
    callback = function(tool_name, tool_input, context) {
      HookResultPreToolUse(permission = "deny", reason = "sync")
    }
  ))

  result <- registry$fire(
    "PreToolUse",
    tool_name = "x",
    tool_input = list(),
    context = list()
  )

  expect_false(promises::is.promising(result))
  expect_s7_class(result, HookResultPreToolUse)
})

test_that("fire() returns a promise of the result when a callback returns a promise", {
  registry <- HookRegistry$new()
  registry$add(HookMatcher(
    "PreToolUse",
    callback = function(tool_name, tool_input, context) {
      later_value(HookResultPreToolUse(permission = "deny", reason = "later"))
    }
  ))

  result <- resolve_async_value(registry$fire(
    "PreToolUse",
    tool_name = "x",
    tool_input = list(),
    context = list()
  ))

  expect_s7_class(result, HookResultPreToolUse)
  expect_equal(result@permission, "deny")
  expect_equal(result@reason, "later")
})

test_that("a promise that resolves to NULL lets the next hook decide, in order", {
  ran <- character()
  registry <- HookRegistry$new()
  registry$add(HookMatcher(
    "PreToolUse",
    callback = function(tool_name, tool_input, context) {
      ran <<- c(ran, "first")
      later_value(NULL)
    }
  ))
  registry$add(HookMatcher(
    "PreToolUse",
    callback = function(tool_name, tool_input, context) {
      ran <<- c(ran, "second")
      HookResultPreToolUse(permission = "deny", reason = "second")
    }
  ))

  pending <- registry$fire(
    "PreToolUse",
    tool_name = "x",
    tool_input = list(),
    context = list()
  )

  expect_equal(ran, "first")

  result <- resolve_async_value(pending)

  expect_equal(ran, c("first", "second"))
  expect_equal(result@permission, "deny")
  expect_equal(result@reason, "second")
})

test_that("after a promised result, later hooks do not run", {
  ran <- FALSE
  registry <- HookRegistry$new()
  registry$add(HookMatcher(
    "PreToolUse",
    callback = function(tool_name, tool_input, context) {
      later_value(HookResultPreToolUse(permission = "allow"))
    }
  ))
  registry$add(HookMatcher(
    "PreToolUse",
    callback = function(tool_name, tool_input, context) {
      ran <<- TRUE
      HookResultPreToolUse(permission = "deny", reason = "never")
    }
  ))

  result <- resolve_async_value(registry$fire(
    "PreToolUse",
    tool_name = "x",
    tool_input = list(),
    context = list()
  ))

  expect_false(ran)
  expect_equal(result@permission, "allow")
})

test_that("a rejected promise is recorded, and denies for PreToolUse", {
  rejected <- function(message) {
    promises::promise(function(resolve, reject) {
      later::later(function() reject(rlang::error_cnd(message = message)), 0.02)
    })
  }
  rejected_string <- function() {
    promises::promise(function(resolve, reject) {
      later::later(function() reject("plain failure"), 0.02)
    })
  }

  registry <- HookRegistry$new()
  registry$add(HookMatcher(
    "PreToolUse",
    callback = function(tool_name, tool_input, context) rejected("boom")
  ))
  registry$add(HookMatcher(
    "PostToolUse",
    callback = function(tool_name, tool_result, tool_error, context) {
      rejected("post boom")
    }
  ))

  denied <- resolve_async_value(registry$fire(
    "PreToolUse",
    tool_name = "x",
    tool_input = list(),
    context = list()
  ))
  expect_s7_class(denied, HookResultPreToolUse)
  expect_equal(denied@permission, "deny")
  expect_match(denied@reason, "^Hook error:")
  expect_length(registry$last_errors(), 1L)

  post <- resolve_async_value(registry$fire(
    "PostToolUse",
    tool_name = "x",
    tool_result = "r",
    tool_error = NULL,
    context = list()
  ))
  expect_null(post)
  expect_length(registry$last_errors(), 2L)

  string_registry <- HookRegistry$new()
  string_registry$add(HookMatcher(
    "PreToolUse",
    callback = function(tool_name, tool_input, context) rejected_string()
  ))
  denied_string <- resolve_async_value(string_registry$fire(
    "PreToolUse",
    tool_name = "y",
    tool_input = list(),
    context = list()
  ))
  expect_equal(denied_string@permission, "deny")
  expect_match(denied_string@reason, "^Hook error:.*plain failure")
  expect_length(string_registry$last_errors(), 1L)
})

test_that("a promise that does not settle in time counts as no answer and is recorded", {
  never <- function(...) promises::promise(function(resolve, reject) NULL)

  post_registry <- HookRegistry$new()
  post_registry$add(HookMatcher(
    "PostToolUse",
    callback = function(tool_name, tool_result, tool_error, context) {
      never()
    },
    promise_timeout = 0.05
  ))
  post <- resolve_async_value(post_registry$fire(
    "PostToolUse",
    tool_name = "x",
    tool_result = "r",
    tool_error = NULL,
    context = list()
  ))
  expect_null(post)
  expect_length(post_registry$last_errors(), 1L)
  expect_match(
    post_registry$last_errors()[[1]]$error,
    "did not settle within 0.05 seconds"
  )

  pre_registry <- HookRegistry$new()
  pre_registry$add(HookMatcher(
    "PreToolUse",
    callback = function(tool_name, tool_input, context) never(),
    promise_timeout = 0.05
  ))
  denied <- resolve_async_value(pre_registry$fire(
    "PreToolUse",
    tool_name = "x",
    tool_input = list(),
    context = list()
  ))
  expect_equal(denied@permission, "deny")
  expect_length(pre_registry$last_errors(), 1L)
})

test_that("the hook timeout is a deputy error as well as a hook timeout", {
  never <- promises::promise(function(resolve, reject) NULL)
  timed_out <- tryCatch(
    resolve_async_value(hook_promise_timeout(never, 0.05, "Stop")),
    error = identity
  )
  expect_s3_class(timed_out, "deputy_hook_timeout")
  expect_s3_class(timed_out, "deputy_error")
})

test_that("errors can be read by the firing that raised them", {
  registry <- HookRegistry$new()
  registry$add(HookMatcher(
    "PostToolUse",
    callback = function(tool_name, tool_result, tool_error, context) {
      if (identical(tool_name, "first")) {
        return(promises::promise(function(resolve, reject) {
          later::later(
            function() reject(rlang::error_cnd(message = "first failed")),
            0.05
          )
        }))
      }
      promises::promise(function(resolve, reject) {
        later::later(function() resolve(NULL), 0.15)
      })
    }
  ))

  first_id <- registry$reserve_fire_id()
  first <- registry$fire(
    "PostToolUse",
    tool_name = "first",
    tool_result = "r",
    tool_error = NULL,
    context = list()
  )
  second_id <- registry$reserve_fire_id()
  second <- registry$fire(
    "PostToolUse",
    tool_name = "second",
    tool_result = "r",
    tool_error = NULL,
    context = list()
  )
  resolve_async_value(promises::promise_all(first, second))

  expect_length(registry$errors_from(first_id), 1L)
  expect_match(registry$errors_from(first_id)[[1]]$error, "first failed")
  expect_length(registry$errors_from(second_id), 0L)

  unreserved <- resolve_async_value(registry$fire(
    "PostToolUse",
    tool_name = "first",
    tool_result = "r",
    tool_error = NULL,
    context = list()
  ))
  expect_null(unreserved)
  own_id <- registry$last_errors()[[length(registry$last_errors())]]$fire_id
  expect_false(identical(own_id, first_id))
  expect_false(identical(own_id, second_id))
  expect_length(registry$errors_from(own_id), 1L)
})

test_that("a hook that fires the same registry again does not take the outer firing's ID", {
  registry <- HookRegistry$new()
  registry$add(HookMatcher(
    "PostToolUse",
    callback = function(tool_name, tool_result, tool_error, context) {
      registry$fire("Notification", message = "x", context = list())
      rlang::abort("outer failed")
    }
  ))
  registry$add(HookMatcher(
    "Notification",
    callback = function(message, context) {
      rlang::abort("notice failed")
    }
  ))

  outer_id <- registry$reserve_fire_id()
  registry$fire(
    "PostToolUse",
    tool_name = "t",
    tool_result = "r",
    tool_error = NULL,
    context = list()
  )

  outer_errors <- registry$errors_from(outer_id)
  expect_length(outer_errors, 1L)
  expect_match(outer_errors[[1]]$error, "outer failed")
  expect_length(registry$last_errors(), 2L)
})

test_that("a firing that throws still hands over the errors raised before it", {
  registry <- HookRegistry$new()
  registry$add(HookMatcher(
    "PostToolUse",
    function(tool_name, tool_result, tool_error, context) stop("hook broke")
  ))
  recorded <- list()

  expect_error(
    suppressMessages(fire_with_errors(
      registry,
      function() {
        registry$fire(
          "PostToolUse",
          tool_name = "x",
          tool_result = "r",
          tool_error = NULL,
          context = list()
        )
        stop("the caller failed")
      },
      function(errors) recorded <<- c(recorded, errors)
    )),
    "the caller failed"
  )

  expect_length(recorded, 1L)
  expect_match(recorded[[1]]$error, "hook broke")
})
