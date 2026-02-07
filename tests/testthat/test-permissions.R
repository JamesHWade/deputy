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

# Tests for immutability (security feature)

test_that("permissions mode is immutable after construction", {
  perms <- permissions_standard()

  # Reading should work
  expect_equal(perms$mode, "default")

  # Writing should error

  expect_error(
    perms$mode <- "bypassPermissions",
    "immutable after construction"
  )

  # Original value should be unchanged
  expect_equal(perms$mode, "default")
})

test_that("permissions file_write is immutable after construction", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir
  perms <- permissions_standard(working_dir = temp_dir)

  # Reading should work
  expect_equal(perms$file_write, temp_dir)

  # Writing should error
  expect_error(
    perms$file_write <- TRUE,
    "immutable after construction"
  )

  # Original value should be unchanged
  expect_equal(perms$file_write, temp_dir)
})

test_that("permissions bash is immutable after construction", {
  perms <- permissions_standard()

  # Reading should work
  expect_false(perms$bash)

  # Writing should error
  expect_error(
    perms$bash <- TRUE,
    "immutable after construction"
  )

  # Original value should be unchanged
  expect_false(perms$bash)
})

test_that("permissions max_turns is immutable after construction", {
  perms <- permissions_standard(max_turns = 10)

  # Reading should work
  expect_equal(perms$max_turns, 10)

  # Writing should error
  expect_error(
    perms$max_turns <- 1000,
    "immutable after construction"
  )

  # Original value should be unchanged
  expect_equal(perms$max_turns, 10)
})

test_that("permissions max_cost_usd is immutable after construction", {
  perms <- permissions_standard(max_cost_usd = 1.0)

  # Reading should work
  expect_equal(perms$max_cost_usd, 1.0)

  # Writing should error
  expect_error(
    perms$max_cost_usd <- 1000.0,
    "immutable after construction"
  )

  # Original value should be unchanged
  expect_equal(perms$max_cost_usd, 1.0)
})

test_that("permissions can_use_tool is immutable after construction", {
  callback <- function(tool_name, tool_input, context) PermissionResultAllow()
  perms <- Permissions$new(can_use_tool = callback)

  # Reading should work
  expect_true(is.function(perms$can_use_tool))

  # Writing should error
  expect_error(
    perms$can_use_tool <- function(...) PermissionResultDeny("blocked"),
    "immutable after construction"
  )

  # Original callback should be unchanged (call it to verify)
  result <- perms$can_use_tool("test", list(), list())
  expect_s3_class(result, "PermissionResultAllow")
})

test_that("all permission fields reject modification attempts", {
  perms <- permissions_full()

  # All these should error
  expect_error(perms$mode <- "readonly", "immutable")
  expect_error(perms$file_read <- FALSE, "immutable")
  expect_error(perms$file_write <- FALSE, "immutable")
  expect_error(perms$bash <- FALSE, "immutable")
  expect_error(perms$r_code <- FALSE, "immutable")
  expect_error(perms$web <- FALSE, "immutable")
  expect_error(perms$install_packages <- FALSE, "immutable")
  expect_error(perms$max_turns <- 1, "immutable")
  expect_error(perms$max_cost_usd <- 0.01, "immutable")
  expect_error(perms$can_use_tool <- function(...) NULL, "immutable")
  expect_error(perms$tool_allowlist <- "read_file", "immutable")
  expect_error(perms$tool_denylist <- "run_bash", "immutable")
  expect_error(perms$permission_prompt_tool_name <- "AskUserQuestion", "immutable")
})

test_that("permissions print works with active bindings", {
  perms <- permissions_standard()

  # Should not error
  expect_output(print(perms), "<Permissions>")
  expect_output(print(perms), "mode: default")
  expect_output(print(perms), "file_read: TRUE")
})

test_that("tool denylist blocks tools before mode checks", {
  perms <- Permissions$new(
    mode = "bypassPermissions",
    file_read = TRUE,
    file_write = TRUE,
    bash = TRUE,
    r_code = TRUE,
    tool_denylist = "run_bash"
  )

  result <- perms$check("run_bash", list(command = "pwd"), list())
  expect_s3_class(result, "PermissionResultDeny")
  expect_match(result$reason, "denylist")
})

test_that("tool allowlist restricts tools when configured", {
  perms <- Permissions$new(
    file_read = TRUE,
    file_write = TRUE,
    bash = TRUE,
    r_code = TRUE,
    tool_allowlist = "read_file"
  )

  allow_result <- perms$check("read_file", list(path = "x.txt"), list())
  deny_result <- perms$check("write_file", list(path = "x.txt"), list())

  expect_s3_class(allow_result, "PermissionResultAllow")
  expect_s3_class(deny_result, "PermissionResultDeny")
  expect_match(deny_result$reason, "allowlist")
})

test_that("denylist takes precedence over allowlist", {
  perms <- Permissions$new(
    mode = "bypassPermissions",
    file_read = TRUE,
    file_write = TRUE,
    bash = TRUE,
    r_code = TRUE,
    tool_allowlist = "run_bash",
    tool_denylist = "run_bash"
  )

  result <- perms$check("run_bash", list(command = "pwd"), list())
  expect_s3_class(result, "PermissionResultDeny")
  expect_match(result$reason, "denylist")
})

test_that("permission prompt tool is always allowed and referenced in denies", {
  perms <- Permissions$new(
    file_read = TRUE,
    file_write = TRUE,
    bash = FALSE,
    r_code = TRUE,
    tool_allowlist = "read_file",
    permission_prompt_tool_name = "AskUserQuestion"
  )

  prompt_result <- perms$check("ask_user_question", list(question = "Allow?"), list())
  deny_result <- perms$check("write_file", list(path = "x.txt"), list())

  expect_s3_class(prompt_result, "PermissionResultAllow")
  expect_s3_class(deny_result, "PermissionResultDeny")
  expect_match(deny_result$reason, "AskUserQuestion", fixed = TRUE)
})

test_that("tool name matching ignores case and optional tool_ prefix", {
  perms <- Permissions$new(
    mode = "bypassPermissions",
    file_read = TRUE,
    file_write = TRUE,
    bash = TRUE,
    r_code = TRUE,
    tool_denylist = "RUN_BASH"
  )

  result <- perms$check("tool_run_bash", list(command = "pwd"), list())
  expect_s3_class(result, "PermissionResultDeny")
})
