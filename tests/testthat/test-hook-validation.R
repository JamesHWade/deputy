test_that("HookMatcher rejects callbacks that cannot accept an event", {
  expect_snapshot(
    HookMatcher(
      event = "PreToolUse",
      callback = function(tool_name) NULL
    ),
    error = TRUE
  )

  expect_snapshot(
    HookMatcher(
      event = "SessionStart",
      callback = function(context, required) NULL
    ),
    error = TRUE
  )

  expect_snapshot(
    HookMatcher(
      event = "SessionStart",
      callback = function(..., required) NULL
    ),
    error = TRUE
  )
})

test_that("HookMatcher accepts callbacks with dots or optional extras", {
  dots <- HookMatcher(
    event = "PreToolUse",
    callback = function(...) NULL
  )
  optional <- HookMatcher(
    event = "SessionStart",
    callback = function(context, optional = TRUE) NULL
  )
  dots_optional <- HookMatcher(
    event = "SessionStart",
    callback = function(..., optional = TRUE) NULL
  )

  expect_s7_class(dots, HookMatcher)
  expect_s7_class(optional, HookMatcher)
  expect_s7_class(dots_optional, HookMatcher)
})

test_that("HookMatcher rejects invalid regex patterns at construction", {
  expect_snapshot(
    HookMatcher(
      event = "PreToolUse",
      pattern = "[",
      callback = function(...) NULL
    ),
    error = TRUE
  )

  expect_snapshot(
    HookMatcher(
      event = "PreToolUse",
      pattern = c("read", "write"),
      callback = function(...) NULL
    ),
    error = TRUE
  )
})

test_that("HookMatcher rejects invalid timeouts at construction", {
  callback <- function(...) NULL

  expect_snapshot(
    HookMatcher("PreToolUse", callback, timeout = -1),
    error = TRUE
  )
  expect_snapshot(
    HookMatcher("PreToolUse", callback, timeout = Inf),
    error = TRUE
  )
  expect_snapshot(
    HookMatcher("PreToolUse", callback, timeout = c(1, 2)),
    error = TRUE
  )
  expect_snapshot(
    HookMatcher("PreToolUse", callback, timeout = "5"),
    error = TRUE
  )
})
