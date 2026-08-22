test_that("HookMatcher rejects callbacks that cannot accept an event", {
  expect_snapshot(
    HookMatcher$new(
      event = "PreToolUse",
      callback = function(tool_name) NULL
    ),
    error = TRUE
  )

  expect_snapshot(
    HookMatcher$new(
      event = "SessionStart",
      callback = function(context, required) NULL
    ),
    error = TRUE
  )
})

test_that("HookMatcher accepts callbacks with dots or optional extras", {
  dots <- HookMatcher$new(
    event = "PreToolUse",
    callback = function(...) NULL
  )
  optional <- HookMatcher$new(
    event = "SessionStart",
    callback = function(context, optional = TRUE) NULL
  )

  expect_s3_class(dots, "HookMatcher")
  expect_s3_class(optional, "HookMatcher")
})

test_that("HookMatcher rejects invalid regex patterns at construction", {
  expect_snapshot(
    HookMatcher$new(
      event = "PreToolUse",
      pattern = "[",
      callback = function(...) NULL
    ),
    error = TRUE
  )

  expect_snapshot(
    HookMatcher$new(
      event = "PreToolUse",
      pattern = c("read", "write"),
      callback = function(...) NULL
    ),
    error = TRUE
  )
})
