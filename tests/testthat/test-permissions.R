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

test_that("path-scoped writes reject dangling symlinks outside the root", {
  skip_on_os("windows")
  sandbox <- withr::local_tempdir(pattern = "deputy-dangling-link-")
  root <- file.path(sandbox, "root")
  outside <- file.path(sandbox, "outside")
  dir.create(root)
  dir.create(outside)
  outside_target <- file.path(outside, "created.txt")
  link <- file.path(root, "link.txt")
  expect_true(file.symlink(outside_target, link))

  result <- permissions_standard(root)$check(
    "write_file",
    list(path = link),
    list(working_dir = root)
  )

  expect_s3_class(result, "PermissionResultDeny")
  expect_false(file.exists(outside_target))
})

test_that("path-scoped writes cover native and SDK tool aliases", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir
  temp_dir <- normalizePath(temp_dir, mustWork = TRUE)
  outside_path <- file.path(dirname(temp_dir), "outside.txt")
  perms <- permissions_standard(working_dir = temp_dir)

  cases <- list(
    list(name = "write_file", path_arg = "path"),
    list(name = "edit_file", path_arg = "path"),
    list(name = "multi_edit", path_arg = "path"),
    list(name = "todo_write", path_arg = "path"),
    list(name = "Write", path_arg = "file_path"),
    list(name = "Edit", path_arg = "file_path"),
    list(name = "MultiEdit", path_arg = "file_path"),
    list(name = "TodoWrite", path_arg = "path")
  )

  tool_input <- function(case, path) {
    stats::setNames(list(path), case$path_arg)
  }

  for (case in cases) {
    inside <- perms$check(
      case$name,
      tool_input(case, file.path(temp_dir, "inside.txt")),
      list()
    )
    outside <- perms$check(
      case$name,
      tool_input(case, outside_path),
      list()
    )
    traversal <- perms$check(
      case$name,
      tool_input(case, "../escape.txt"),
      list()
    )
    missing <- perms$check(case$name, list(), list())

    expect_s3_class(inside, "PermissionResultAllow")
    expect_s3_class(outside, "PermissionResultDeny")
    expect_s3_class(traversal, "PermissionResultDeny")
    expect_match(traversal$reason, "traversal")
    expect_s3_class(missing, "PermissionResultDeny")
    if (!case$name %in% c("todo_write", "TodoWrite")) {
      expect_match(missing$reason, "requires a path")
    }
  }
})

test_that("relative writes use context working_dir for every write alias", {
  sandbox <- withr::local_tempdir(pattern = "deputy-permission-")
  allowed_dir <- file.path(sandbox, "allowed")
  process_dir <- file.path(sandbox, "process")
  dir.create(allowed_dir)
  dir.create(process_dir)
  allowed_dir <- normalizePath(allowed_dir, mustWork = TRUE)
  process_dir <- normalizePath(process_dir, mustWork = TRUE)

  permissions <- permissions_standard(working_dir = allowed_dir)
  withr::local_dir(process_dir)

  cases <- list(
    list(name = "write_file", path_arg = "path"),
    list(name = "edit_file", path_arg = "path"),
    list(name = "multi_edit", path_arg = "path"),
    list(name = "todo_write", path_arg = "path"),
    list(name = "Write", path_arg = "file_path"),
    list(name = "Edit", path_arg = "file_path"),
    list(name = "MultiEdit", path_arg = "file_path"),
    list(name = "TodoWrite", path_arg = "path")
  )

  for (case in cases) {
    input <- stats::setNames(list("nested/file.txt"), case$path_arg)
    traversal_input <- stats::setNames(list("../escape.txt"), case$path_arg)

    allowed <- permissions$check(
      case$name,
      input,
      list(working_dir = allowed_dir)
    )
    wrong_context <- permissions$check(
      case$name,
      input,
      list(working_dir = process_dir)
    )
    traversal <- permissions$check(
      case$name,
      traversal_input,
      list(working_dir = allowed_dir)
    )

    expect_true(inherits(allowed, "PermissionResultAllow"), info = case$name)
    expect_true(
      inherits(wrong_context, "PermissionResultDeny"),
      info = case$name
    )
    expect_true(
      inherits(traversal, "PermissionResultDeny"),
      info = case$name
    )
    expect_match(traversal$reason, "traversal")
  }
})

test_that("readonly recognizes native and SDK mutating tool aliases", {
  perms <- permissions_readonly()
  misleading_context <- list(
    tool_annotations = list(
      read_only_hint = TRUE,
      destructive_hint = FALSE
    )
  )
  mutating_tools <- c(
    "write_file",
    "tool_write_file",
    "edit_file",
    "multi_edit",
    "todo_write",
    "Write",
    "Edit",
    "MultiEdit",
    "TodoWrite",
    "run_bash",
    "bash",
    "run_r_code",
    "install_package"
  )

  for (tool_name in mutating_tools) {
    result <- perms$check(tool_name, list(), misleading_context)
    expect_s3_class(result, "PermissionResultDeny")
  }
})

test_that("readonly fails closed for unknown unannotated tools", {
  result <- permissions_readonly()$check(
    "delete_everything",
    list(),
    list()
  )

  expect_s3_class(result, "PermissionResultDeny")
  expect_match(result$reason, "explicit tool allowlist")
})

test_that("readonly still enforces capability fields before annotations", {
  permissions <- permissions_readonly()
  read_only_web <- list(
    tool_annotations = list(
      read_only_hint = TRUE,
      open_world_hint = TRUE
    )
  )

  web <- permissions$check("web_search", list(query = "R"), read_only_web)
  unknown_web <- permissions$check("custom_search", list(), read_only_web)
  delegation <- permissions$check(
    "delegate_to_agent",
    list(),
    list(tool_annotations = list(read_only_hint = FALSE))
  )

  expect_s3_class(web, "PermissionResultDeny")
  expect_s3_class(unknown_web, "PermissionResultDeny")
  expect_s3_class(delegation, "PermissionResultDeny")
  expect_s3_class(
    permissions$check("read_file", list(path = "safe.txt"), list()),
    "PermissionResultAllow"
  )
})

test_that("readonly denies contradictory destructive annotations", {
  context <- list(
    tool_annotations = list(
      read_only_hint = TRUE,
      destructive_hint = TRUE
    )
  )

  expect_s3_class(
    permissions_readonly()$check("custom_tool", list(), context),
    "PermissionResultDeny"
  )
  expect_s3_class(
    permissions_readonly()$check("read_file", list(), context),
    "PermissionResultDeny"
  )
})

test_that("TodoWrite uses its documented default under scoped permissions", {
  root <- withr::local_tempdir(pattern = "deputy-permission-")
  permissions <- permissions_standard(root)

  for (tool_name in c("todo_write", "tool_todo_write", "TodoWrite")) {
    result <- permissions$check(
      tool_name,
      list(todos = list()),
      list(working_dir = root)
    )
    expect_true(inherits(result, "PermissionResultAllow"), info = tool_name)

    withr::local_dir(dirname(root))
    outside <- permissions$check(tool_name, list(todos = list()), list())
    expect_true(inherits(outside, "PermissionResultDeny"), info = tool_name)
  }
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

test_that("readonly annotations do not grant authority to unknown tools", {
  perms <- permissions_readonly()
  context <- list(working_dir = getwd())

  read_only_context <- c(
    context,
    list(tool_annotations = list(read_only_hint = TRUE))
  )
  result <- perms$check("unknown_tool", list(), read_only_context)
  expect_s3_class(result, "PermissionResultDeny")

  destructive_context <- c(
    context,
    list(tool_annotations = list(destructive_hint = TRUE))
  )
  result <- perms$check("unknown_tool", list(), destructive_context)
  expect_s3_class(result, "PermissionResultDeny")

  explicitly_allowed <- Permissions$new(
    mode = "readonly",
    file_read = TRUE,
    file_write = FALSE,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE,
    tool_allowlist = "unknown_tool"
  )
  result <- explicitly_allowed$check(
    "unknown_tool",
    list(),
    read_only_context
  )
  expect_s3_class(result, "PermissionResultAllow")
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

  combined_context <- c(
    context,
    list(
      tool_annotations = list(
        read_only_hint = TRUE,
        open_world_hint = TRUE
      )
    )
  )
  result <- perms$check("custom_read_web_tool", list(), combined_context)
  expect_s3_class(result, "PermissionResultDeny")
})

test_that("plan mode preserves capability ceilings before annotations", {
  permissions <- Permissions$new(
    mode = "plan",
    file_read = TRUE,
    file_write = FALSE,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE
  )
  read_only_web <- list(
    tool_annotations = list(
      read_only_hint = TRUE,
      open_world_hint = TRUE,
      destructive_hint = FALSE
    )
  )
  misleading_write <- list(
    tool_annotations = list(
      read_only_hint = TRUE,
      open_world_hint = FALSE,
      destructive_hint = FALSE
    )
  )

  expect_s3_class(
    permissions$check("custom_search", list(), read_only_web),
    "PermissionResultDeny"
  )
  expect_s3_class(
    permissions$check("Write", list(file_path = "x"), misleading_write),
    "PermissionResultDeny"
  )
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
  expect_error(
    perms$permission_prompt_tool_name <- "AskUserQuestion",
    "immutable"
  )
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

  prompt_result <- perms$check(
    "ask_user_question",
    list(question = "Allow?"),
    list()
  )
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

test_that("run_bash policy also matches bash alias", {
  perms <- Permissions$new(
    mode = "bypassPermissions",
    file_read = TRUE,
    file_write = TRUE,
    bash = TRUE,
    r_code = TRUE,
    tool_denylist = "run_bash"
  )

  result <- perms$check("bash", list(command = "pwd"), list())
  expect_s3_class(result, "PermissionResultDeny")
  expect_match(result$reason, "denylist")
})

test_that("tool policies match equivalent native and SDK aliases", {
  aliases <- list(
    c("read_file", "Read"),
    c("write_file", "Write"),
    c("edit_file", "Edit"),
    c("multi_edit", "MultiEdit"),
    c("list_files", "LS"),
    c("glob_files", "Glob"),
    c("grep_files", "Grep"),
    c("todo_read", "TodoRead"),
    c("todo_write", "TodoWrite"),
    c("web_fetch", "WebFetch"),
    c("web_search", "WebSearch"),
    c("delegate_to_agent", "Agent"),
    c("delegate_to_agent", "Task")
  )

  for (pair in aliases) {
    native_name <- pair[[1]]
    sdk_name <- pair[[2]]

    deny_native <- Permissions$new(
      mode = "bypassPermissions",
      tool_denylist = native_name
    )
    deny_sdk <- Permissions$new(
      mode = "bypassPermissions",
      tool_denylist = sdk_name
    )
    allow_native <- Permissions$new(
      mode = "bypassPermissions",
      tool_allowlist = native_name
    )
    allow_sdk <- Permissions$new(
      mode = "bypassPermissions",
      tool_allowlist = sdk_name
    )

    expect_s3_class(
      deny_native$check(sdk_name, list(), list()),
      "PermissionResultDeny"
    )
    expect_s3_class(
      deny_sdk$check(native_name, list(), list()),
      "PermissionResultDeny"
    )
    expect_s3_class(
      allow_native$check(sdk_name, list(), list()),
      "PermissionResultAllow"
    )
    expect_s3_class(
      allow_sdk$check(native_name, list(), list()),
      "PermissionResultAllow"
    )
  }
})
