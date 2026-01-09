# Tests for permission system

test_that("permissions_standard creates valid permissions", {
  perms <- permissions_standard()

  expect_s3_class(perms, "Permissions")
  expect_equal(perms$mode, "default")
  expect_true(perms$file_read)
  expect_true(perms$r_code)
  expect_false(perms$bash)
  expect_equal(perms$max_turns, 25)
})

test_that("permissions_readonly blocks writes", {
  perms <- permissions_readonly()

  expect_equal(perms$mode, "readonly")
  expect_true(perms$file_read)
  expect_false(perms$file_write)
  expect_false(perms$bash)
})

test_that("permissions_full allows everything", {
  perms <- permissions_full()

  expect_equal(perms$mode, "bypassPermissions")
  expect_true(perms$file_read)
  expect_true(perms$file_write)
  expect_true(perms$bash)
  expect_true(perms$r_code)
})

test_that("permission check allows read tools", {
  perms <- permissions_standard()
  context <- list(working_dir = getwd())

  result <- perms$check("read_file", list(path = "test.txt"), context)
  expect_s3_class(result, "PermissionResultAllow")
})

test_that("permission check blocks bash by default", {
  perms <- permissions_standard()
  context <- list(working_dir = getwd())

  result <- perms$check("run_bash", list(command = "ls"), context)
  expect_s3_class(result, "PermissionResultDeny")
  expect_true(grepl("not allowed", result$reason))
})

test_that("permission check blocks writes outside working_dir", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir
  # Normalize to handle macOS /var -> /private/var symlink
  temp_dir <- normalizePath(temp_dir, mustWork = TRUE)

  perms <- permissions_standard(working_dir = temp_dir)
  context <- list(working_dir = temp_dir)

  # Write inside working_dir - should allow
  inside_result <- perms$check(
    "write_file",
    list(path = file.path(temp_dir, "test.txt")),
    context
  )
  expect_s3_class(inside_result, "PermissionResultAllow")

  # Write outside working_dir - should deny
  outside_result <- perms$check(
    "write_file",
    list(path = "/tmp/outside.txt"),
    context
  )
  expect_s3_class(outside_result, "PermissionResultDeny")
})

test_that("permission check blocks path traversal", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  perms <- permissions_standard(working_dir = temp_dir)
  context <- list(working_dir = temp_dir)

  # Path with .. should be denied
  result <- perms$check("write_file", list(path = "../escape.txt"), context)
  expect_s3_class(result, "PermissionResultDeny")
  expect_true(grepl("traversal", result$reason, ignore.case = TRUE))
})

test_that("bypassPermissions mode allows everything", {
  perms <- permissions_full()
  context <- list(working_dir = getwd())

  # Bash should be allowed
  result <- perms$check("run_bash", list(command = "rm -rf /"), context)
  expect_s3_class(result, "PermissionResultAllow")

  # Any tool should be allowed
  result <- perms$check("dangerous_tool", list(), context)
  expect_s3_class(result, "PermissionResultAllow")
})

test_that("readonly mode blocks all writes", {
  perms <- permissions_readonly()
  context <- list(working_dir = getwd())

  result <- perms$check("write_file", list(path = "test.txt"), context)
  expect_s3_class(result, "PermissionResultDeny")
})

test_that("custom permission callback is called", {
  callback_called <- FALSE

  perms <- Permissions$new(
    can_use_tool = function(tool_name, tool_input, context) {
      callback_called <<- TRUE
      PermissionResultAllow()
    }
  )
  context <- list(working_dir = getwd())

  result <- perms$check("custom_tool", list(), context)
  expect_true(callback_called)
  expect_s3_class(result, "PermissionResultAllow")
})

test_that("PermissionResultAllow has correct structure", {
  result <- PermissionResultAllow(message = "test message")

  expect_s3_class(result, "PermissionResultAllow")
  expect_s3_class(result, "PermissionResult")
  expect_equal(result$decision, "allow")
  expect_equal(result$message, "test message")
})

test_that("PermissionResultDeny has correct structure", {
  result <- PermissionResultDeny(reason = "test reason", interrupt = TRUE)

  expect_s3_class(result, "PermissionResultDeny")
  expect_s3_class(result, "PermissionResult")
  expect_equal(result$decision, "deny")
  expect_equal(result$reason, "test reason")
  expect_true(result$interrupt)
})

test_that("readonly mode uses annotations when available", {
  perms <- permissions_readonly()
  context <- list(working_dir = getwd())

  # Tool with read_only_hint should be allowed
  read_only_context <- c(
    context,
    list(tool_annotations = list(read_only_hint = TRUE))
  )
  result <- perms$check("unknown_tool", list(), read_only_context)
  expect_s3_class(result, "PermissionResultAllow")

  # Tool with destructive_hint should be denied
  destructive_context <- c(
    context,
    list(tool_annotations = list(destructive_hint = TRUE))
  )
  result <- perms$check("unknown_tool", list(), destructive_context)
  expect_s3_class(result, "PermissionResultDeny")
})

test_that("default mode uses annotations for unknown tools", {
  perms <- permissions_standard()
  context <- list(working_dir = getwd())

  # Unknown read-only tool should be allowed
  read_only_context <- c(
    context,
    list(tool_annotations = list(read_only_hint = TRUE))
  )
  result <- perms$check("custom_read_tool", list(), read_only_context)
  expect_s3_class(result, "PermissionResultAllow")

  # Open-world tool with web disabled should be denied
  open_world_context <- c(
    context,
    list(tool_annotations = list(open_world_hint = TRUE))
  )
  result <- perms$check("custom_web_tool", list(), open_world_context)
  expect_s3_class(result, "PermissionResultDeny")
})
