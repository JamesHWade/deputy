test_that("HookResultPreToolUse has correct structure", {
  result <- HookResultPreToolUse(permission = "allow")
  expect_s3_class(result, "HookResultPreToolUse")
  expect_s3_class(result, "HookResult")
  expect_equal(result$permission, "allow")
  expect_true(result$continue)
  expect_named(
    result,
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
  expect_s3_class(result, "HookResultPostToolUse")
  expect_s3_class(result, "HookResult")
  expect_true(result$continue)
  expect_named(
    result,
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
