# Tests for Agent permission enforcement integration
# Note: create_mock_chat is defined in helper-mocks.R

test_that("reapplying a permission mode preserves the custom policy", {
  callback <- function(...) PermissionResultDeny(reason = "custom ceiling")
  permissions <- Permissions$new(
    mode = "standard",
    file_read = FALSE,
    file_write = FALSE,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE,
    can_use_tool = callback,
    tool_allowlist = "read_file",
    tool_denylist = "run_r_code",
    permission_prompt_tool_name = "ask_user"
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    permissions = permissions
  )

  expect_invisible(agent$set_permission_mode("standard"))
  expect_identical(agent$permissions, permissions)
  expect_false(agent$permissions$file_read)
  expect_false(agent$permissions$file_write)
  expect_false(agent$permissions$r_code)
  expect_identical(agent$permissions$can_use_tool, callback)
  expect_identical(agent$permissions$tool_allowlist, "read_file")
  expect_identical(agent$permissions$tool_denylist, "run_r_code")
  expect_identical(
    agent$permissions$permission_prompt_tool_name,
    "ask_user"
  )
})

test_that("permission mode changes can only narrow the current policy", {
  permissions <- Permissions$new(
    mode = "standard",
    file_read = FALSE,
    file_write = FALSE,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(tool_read_file),
    permissions = permissions
  )

  expect_invisible(agent$set_permission_mode("readonly"))
  expect_identical(agent$get_permission_mode(), "readonly")
  expect_false(agent$permissions$file_read)
  expect_false(agent$permissions$file_write)
  expect_false(agent$permissions$r_code)
  expect_s3_class(
    agent$permissions$check("read_file", list(path = "blocked.txt")),
    "PermissionResultDeny"
  )

  expect_error(
    agent$set_permission_mode("standard"),
    class = "deputy_permission_mode_widening"
  )

  plan_agent <- Agent$new(
    chat = create_mock_chat(),
    permissions = permissions_plan()
  )
  expect_error(
    plan_agent$set_permission_mode("standard"),
    class = "deputy_permission_mode_widening"
  )
  expect_error(
    plan_agent$set_permission_mode("full"),
    class = "deputy_permission_mode_widening"
  )
})

test_that("permission mode transitions follow the authority lattice", {
  expected <- list(
    standard = c("standard", "readonly"),
    plan = c("plan", "readonly"),
    readonly = "readonly",
    full = PermissionMode
  )
  make_permissions <- function(mode) {
    switch(
      mode,
      standard = permissions_standard(),
      plan = permissions_plan(),
      readonly = permissions_readonly(),
      full = permissions_full()
    )
  }

  for (source in PermissionMode) {
    expect_identical(permission_mode_targets(source), expected[[source]])
    for (target in PermissionMode) {
      agent <- Agent$new(
        chat = create_mock_chat(),
        permissions = make_permissions(source)
      )
      if (target %in% expected[[source]]) {
        expect_no_error(agent$set_permission_mode(target))
        expect_identical(agent$get_permission_mode(), target)
      } else {
        expect_error(
          agent$set_permission_mode(target),
          class = "deputy_permission_mode_widening"
        )
        expect_identical(agent$get_permission_mode(), source)
      }
    }
  }
})

test_that("readonly transitions retain callback denials as a veto", {
  callback <- function(tool_name, ...) {
    if (identical(tool_name, "read_file")) {
      return(PermissionResultDeny(reason = "custom read denial"))
    }
    PermissionResultAllow()
  }
  agent <- Agent$new(
    chat = create_mock_chat(),
    permissions = Permissions$new(
      mode = "standard",
      can_use_tool = callback
    )
  )

  expect_s3_class(
    agent$permissions$check("read_file", list(path = "blocked.txt")),
    "PermissionResultDeny"
  )
  agent$set_permission_mode("readonly")
  expect_s3_class(
    agent$permissions$check("read_file", list(path = "blocked.txt")),
    "PermissionResultDeny"
  )
  expect_s3_class(
    agent$permissions$check("run_bash", list(command = "pwd")),
    "PermissionResultDeny"
  )
})

test_that("narrowing a full policy retains a custom write root", {
  withr::local_tempdir(pattern = "deputy-permission-root") -> root
  nested <- file.path(root, "nested")
  dir.create(nested)
  nested <- normalizePath(nested, winslash = "/")
  permissions <- Permissions$new(
    mode = "full",
    file_read = TRUE,
    file_write = nested,
    bash = TRUE,
    r_code = TRUE,
    web = TRUE,
    install_packages = TRUE
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    working_dir = root,
    permissions = permissions
  )

  expect_invisible(agent$set_permission_mode("standard"))
  expect_identical(agent$permissions$file_write, nested)
  expect_false(agent$permissions$bash)
  expect_false(agent$permissions$web)
  expect_false(agent$permissions$install_packages)
})

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
  # Skip on Windows due to 8.3 short name normalization issues
  skip_on_os("windows")

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

test_that("full mode allows everything", {
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
