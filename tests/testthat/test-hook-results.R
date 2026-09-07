test_that("HookResultPreToolUse has correct structure", {
  result <- HookResultPreToolUse(permission = "allow")
  expect_s7_class(result, HookResultPreToolUse)
  expect_s7_class(result, HookResult)
  expect_equal(result$permission, "allow")
  expect_true(result$continue)
  expect_named(
    S7::props(result),
    c("permission", "reason", "continue", "additional_context", "stop_reason")
  )

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
  expect_s7_class(result, HookResultPostToolUse)
  expect_s7_class(result, HookResult)
  expect_true(result$continue)
  expect_named(
    S7::props(result),
    c(
      "continue",
      "suppress_output",
      "updated_tool_output",
      "additional_context",
      "stop_reason"
    )
  )

  result_stop <- HookResultPostToolUse(continue = FALSE)
  expect_false(result_stop$continue)
})

test_that("HookResultPreCompact has correct structure", {
  result <- HookResultPreCompact()
  expect_s7_class(result, HookResultPreCompact)
  expect_s7_class(result, HookResult)
  expect_true(result$continue)
  expect_null(result$summary)

  result_with_summary <- HookResultPreCompact(
    continue = FALSE,
    summary = "Custom summary"
  )
  expect_false(result_with_summary$continue)
  expect_equal(result_with_summary$summary, "Custom summary")
})

test_that("callback result properties freeze decisions but retain output identity", {
  output <- new.env(parent = emptyenv())
  output$value <- "original"
  values <- list(
    HookResultPreToolUse(),
    HookResultPostToolUse(updated_tool_output = output),
    HookResultPreCompact(),
    PermissionResultAllow(),
    PermissionResultDeny("blocked")
  )
  for (value in values) {
    original <- S7::props(value)
    for (name in names(original)) {
      expect_error(S7::prop(value, name) <- original[[name]], "read-only")
    }
    expect_error(S7::props(value) <- original, "read-only")
    expect_identical(S7::props(value), original)
    expect_false(is.list(value))
    expect_null(value$unknown)
  }
  result <- values[[2L]]
  expect_identical(result@updated_tool_output, output)
  output$value <- "changed"
  expect_identical(result$updated_tool_output$value, "changed")
  expect_error(result$continue <- FALSE, "Can.t set S7 properties")
  revised <- do.call(
    HookResultPostToolUse,
    modifyList(
      S7::props(result),
      list(continue = FALSE)
    )
  )
  expect_false(revised$continue)
  expect_true(result$continue)
  expect_identical(revised$updated_tool_output, output)
})

test_that("callback constructors reject ambiguous flags and text", {
  for (flag in list(NULL, NA, logical(), c(TRUE, FALSE), 1, "FALSE")) {
    expect_error(HookResultPreToolUse(continue = flag), "logical")
    expect_error(HookResultPostToolUse(continue = flag), "logical")
    expect_error(HookResultPreCompact(continue = flag), "logical")
    expect_error(PermissionResultDeny("blocked", interrupt = flag), "logical")
    expect_identical(
      HookResultPostToolUse(suppress_output = flag)$suppress_output,
      isTRUE(flag)
    )
  }
  for (text in list(NA_character_, character(), c("one", "two"), 42)) {
    expect_error(HookResultPreToolUse(reason = text), "string")
    expect_error(HookResultPreToolUse(additional_context = text), "string")
    expect_error(HookResultPostToolUse(stop_reason = text), "string")
    expect_error(HookResultPreCompact(summary = text), "string")
    expect_error(PermissionResultAllow(message = text), "string")
    expect_error(PermissionResultDeny(reason = text), "string")
  }
  expect_error(PermissionResultDeny(NULL), "string")
  expect_error(HookResultPreToolUse(permission = "invalid"), "arg")
  expect_identical(HookResultPreToolUse("d")$permission, "deny")
  expect_identical(PermissionResultDeny("")$reason, "")
  expect_true(HookResultPostToolUse(suppress_output = TRUE)$suppress_output)
})

test_that("invalid permission callback values still deny execution", {
  for (invalid in list(
    list(decision = "allow"),
    structure(
      list(decision = "allow"),
      class = c("PermissionResultAllow", "PermissionResult", "list")
    ),
    HookResultPreToolUse("allow")
  )) {
    policy <- Permissions(can_use_tool = function(...) invalid)
    expect_warning(
      result <- permissions_check(policy, "read_file", list()),
      "invalid type"
    )
    expect_s7_class(result, PermissionResultDeny)
    expect_identical(result$reason, "Invalid callback result")
  }
})

test_that("invalid hook construction uses existing fail-closed error handling", {
  registry <- HookRegistry$new()
  registry$add(HookMatcher("PreToolUse", function(...) {
    HookResultPreToolUse(continue = NA)
  }))
  result <- registry$fire("PreToolUse", tool_name = "effect")
  expect_s7_class(result, HookResultPreToolUse)
  expect_identical(result$permission, "deny")
  expect_match(result$reason, "Hook error:")
  expect_length(registry$last_errors(), 1L)

  registry$add(HookMatcher("PostToolUse", function(...) {
    HookResultPostToolUse(continue = NA)
  }))
  expect_null(registry$fire("PostToolUse", tool_name = "effect"))
  expect_length(registry$last_errors(), 2L)
})
