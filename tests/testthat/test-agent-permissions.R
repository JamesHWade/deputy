# Tests for Agent permission enforcement integration
# Note: create_mock_chat is defined in helper-mocks.R

test_that("Agent rejects tool when permission denies", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_read_file),
    permissions = Permissions$new(file_read = FALSE)
  )

  # Check that permission would deny read_file
  result <- agent$permissions$check(
    "read_file",
    list(path = "test.txt"),
    list()
  )

  expect_s3_class(result, "PermissionResultDeny")
  expect_equal(result$reason, "File reading is not allowed")
})

test_that("Agent allows tool when permission allows", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_read_file),
    permissions = Permissions$new(file_read = TRUE)
  )

  # Check that permission would allow read_file
  result <- agent$permissions$check(
    "read_file",
    list(path = "test.txt"),
    list()
  )

  expect_s3_class(result, "PermissionResultAllow")
})

test_that("Agent respects readonly mode", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_read_file, tool_write_file),
    permissions = permissions_readonly()
  )

  # Read should be allowed
  read_result <- agent$permissions$check(
    "read_file",
    list(path = "test.txt"),
    list()
  )
  expect_s3_class(read_result, "PermissionResultAllow")

  # Write should be denied
  write_result <- agent$permissions$check(
    "write_file",
    list(path = "test.txt", content = "data"),
    list()
  )
  expect_s3_class(write_result, "PermissionResultDeny")
})

test_that("Agent respects working directory restriction", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_write_file),
    permissions = permissions_standard(working_dir = temp_dir)
  )

  # Write within allowed dir should be allowed
  allowed_path <- file.path(temp_dir, "test.txt")
  result_allowed <- agent$permissions$check(
    "write_file",
    list(path = allowed_path, content = "data"),
    list()
  )
  expect_s3_class(result_allowed, "PermissionResultAllow")

  # Write outside allowed dir should be denied
  outside_path <- file.path(dirname(temp_dir), "outside.txt")
  result_denied <- agent$permissions$check(
    "write_file",
    list(path = outside_path, content = "data"),
    list()
  )
  expect_s3_class(result_denied, "PermissionResultDeny")
})

test_that("Agent uses custom permission callback", {
  callback_called <- FALSE

  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_read_file),
    permissions = Permissions$new(
      can_use_tool = function(tool_name, tool_input, context) {
        callback_called <<- TRUE
        PermissionResultAllow()
      }
    )
  )

  result <- agent$permissions$check(
    "read_file",
    list(path = "test.txt"),
    list()
  )

  expect_true(callback_called)
  expect_s3_class(result, "PermissionResultAllow")
})

test_that("Permission callback errors result in deny (fail-safe)", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_read_file),
    permissions = Permissions$new(
      can_use_tool = function(tool_name, tool_input, context) {
        stop("Callback error!")
      }
    )
  )

  # Should deny when callback errors (fail-safe behavior)
  suppressWarnings({
    result <- agent$permissions$check(
      "read_file",
      list(path = "test.txt"),
      list()
    )
  })

  expect_s3_class(result, "PermissionResultDeny")
  expect_equal(result$reason, "Permission callback error")
})

test_that("Permission callback invalid return results in deny", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_read_file),
    permissions = Permissions$new(
      can_use_tool = function(tool_name, tool_input, context) {
        # Return invalid type
        "not a PermissionResult"
      }
    )
  )

  suppressWarnings({
    result <- agent$permissions$check(
      "read_file",
      list(path = "test.txt"),
      list()
    )
  })

  expect_s3_class(result, "PermissionResultDeny")
  expect_equal(result$reason, "Invalid callback result")
})

test_that("Agent respects bash permission", {
  mock_chat <- create_mock_chat()

  # Bash denied
  agent_no_bash <- Agent$new(
    chat = mock_chat,
    tools = list(tool_run_bash),
    permissions = Permissions$new(bash = FALSE)
  )
  result_no_bash <- agent_no_bash$permissions$check(
    "run_bash",
    list(command = "echo test"),
    list()
  )
  expect_s3_class(result_no_bash, "PermissionResultDeny")

  # Bash allowed
  agent_bash <- Agent$new(
    chat = mock_chat,
    tools = list(tool_run_bash),
    permissions = Permissions$new(bash = TRUE)
  )
  result_bash <- agent_bash$permissions$check(
    "run_bash",
    list(command = "echo test"),
    list()
  )
  expect_s3_class(result_bash, "PermissionResultAllow")
})

test_that("Agent respects r_code permission", {
  mock_chat <- create_mock_chat()

  # R code denied
  agent_no_r <- Agent$new(
    chat = mock_chat,
    tools = list(tool_run_r_code),
    permissions = Permissions$new(r_code = FALSE)
  )
  result_no_r <- agent_no_r$permissions$check(
    "run_r_code",
    list(code = "1 + 1"),
    list()
  )
  expect_s3_class(result_no_r, "PermissionResultDeny")

  # R code allowed
  agent_r <- Agent$new(
    chat = mock_chat,
    tools = list(tool_run_r_code),
    permissions = Permissions$new(r_code = TRUE)
  )
  result_r <- agent_r$permissions$check(
    "run_r_code",
    list(code = "1 + 1"),
    list()
  )
  expect_s3_class(result_r, "PermissionResultAllow")
})

test_that("bypassPermissions mode allows everything", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_run_bash, tool_write_file),
    permissions = permissions_full()
  )

  # Even bash should be allowed
  result_bash <- agent$permissions$check(
    "run_bash",
    list(command = "rm -rf /"),
    list()
  )
  expect_s3_class(result_bash, "PermissionResultAllow")

  # File write should be allowed
  result_write <- agent$permissions$check(
    "write_file",
    list(path = "/etc/passwd", content = "bad"),
    list()
  )
  expect_s3_class(result_write, "PermissionResultAllow")
})
