# Tests for plan permission mode.

test_that("permissions_plan creates compat planning permissions", {
  perms <- permissions_plan(max_turns = 7, max_cost_usd = 0.25)

  expect_s3_class(perms, "Permissions")
  expect_equal(perms$mode, "plan")
  expect_true(perms$file_read)
  expect_false(perms$file_write)
  expect_false(perms$bash)
  expect_false(perms$r_code)
  expect_equal(perms$permission_prompt_tool_name, "AskUserQuestion")
  expect_equal(perms$max_turns, 7)
  expect_equal(perms$max_cost_usd, 0.25)
})

test_that("plan mode allows only annotated read-only tools", {
  perms <- permissions_plan()

  allow <- perms$check(
    "custom_read",
    list(),
    list(tool_annotations = list(read_only_hint = TRUE))
  )
  expect_s3_class(allow, "PermissionResultAllow")

  destructive <- perms$check(
    "custom_edit",
    list(),
    list(tool_annotations = list(
      read_only_hint = FALSE,
      destructive_hint = TRUE
    ))
  )
  expect_s3_class(destructive, "PermissionResultDeny")
  expect_match(destructive$reason, "destructive", ignore.case = TRUE)

  unannotated <- perms$check("mystery_tool", list(), list())
  expect_s3_class(unannotated, "PermissionResultDeny")
  expect_match(unannotated$reason, "read-only", ignore.case = TRUE)
})

test_that("plan mode always allows the permission prompt tool", {
  perms <- permissions_plan(permission_prompt_tool_name = "AskUserQuestion")

  result <- perms$check("AskUserQuestion", list(), list())
  expect_s3_class(result, "PermissionResultAllow")
})
