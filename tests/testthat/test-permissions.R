# Tests for permission system

test_that("permissions_standard creates valid permissions", {
  perms <- permissions_standard()

  expect_s3_class(perms, "Permissions")
  expect_equal(perms$mode, "standard")
  expect_true(perms$file_read)
  expect_false(perms$r_code)
  expect_false(perms$bash)
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

  expect_equal(perms$mode, "full")
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

test_that("permission check blocks unrestricted R code by default", {
  perms <- permissions_standard()

  result <- perms$check("run_r_code", list(code = "1 + 1"), list())

  expect_s3_class(result, "PermissionResultDeny")
  expect_match(result$reason, "not allowed")
})

test_that("partial direct policies block unrestricted R code by default", {
  perms <- Permissions$new(web = TRUE)

  result <- perms$check("run_r_code", list(code = "1 + 1"), list())

  expect_false(perms$r_code)
  expect_s3_class(result, "PermissionResultDeny")
  expect_match(result$reason, "not allowed")
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

test_that("path-scoped writes cover native write tools", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir
  temp_dir <- normalizePath(temp_dir, mustWork = TRUE)
  outside_path <- file.path(dirname(temp_dir), "outside.txt")
  perms <- permissions_standard(working_dir = temp_dir)

  cases <- list(
    list(name = "write_file", path_arg = "path"),
    list(name = "edit_file", path_arg = "path"),
    list(name = "multi_edit", path_arg = "path")
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
    expect_match(missing$reason, "requires a path")
  }
})

test_that("relative writes use context working_dir for every write tool", {
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
    list(name = "multi_edit", path_arg = "path")
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

test_that("readonly recognizes native mutating tools", {
  perms <- permissions_readonly()
  misleading_context <- list(
    tool_annotations = list(
      read_only_hint = TRUE,
      destructive_hint = FALSE
    )
  )
  mutating_tools <- c(
    "write_file",
    "edit_file",
    "multi_edit",
    "run_bash",
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

test_that("full mode allows everything", {
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

test_that("standard mode uses annotations for unknown tools", {
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
    permissions$check("write_file", list(path = "x"), misleading_write),
    "PermissionResultDeny"
  )
})

# Tests for immutability (security feature)

test_that("permissions mode is immutable after construction", {
  perms <- permissions_standard()

  # Reading should work
  expect_equal(perms$mode, "standard")

  # Writing should error

  expect_error(
    perms$mode <- "full",
    "immutable after construction"
  )

  # Original value should be unchanged
  expect_equal(perms$mode, "standard")
})

test_that("permissions file_write is immutable after construction", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir
  temp_dir <- normalizePath(temp_dir, winslash = "/")
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
  expect_error(perms$can_use_tool <- function(...) NULL, "immutable")
  expect_error(perms$tool_allowlist <- "read_file", "immutable")
  expect_error(perms$tool_denylist <- "run_bash", "immutable")
  expect_error(
    perms$permission_prompt_tool_name <- "ask_user",
    "immutable"
  )
})

test_that("permissions print works with active bindings", {
  perms <- permissions_standard()

  # Should not error
  expect_output(print(perms), "<Permissions>")
  expect_output(print(perms), "mode: standard")
  expect_output(print(perms), "file_read: TRUE")
})

test_that("tool denylist blocks tools before mode checks", {
  perms <- Permissions$new(
    mode = "full",
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
    mode = "full",
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

test_that("permission prompt tool is allowed and referenced in denies", {
  perms <- Permissions$new(
    file_read = TRUE,
    file_write = TRUE,
    bash = FALSE,
    r_code = TRUE,
    tool_allowlist = c("read_file", "ask_user"),
    permission_prompt_tool_name = "ask_user"
  )

  prompt_result <- perms$check(
    "ask_user",
    list(question = "Allow?"),
    list()
  )
  deny_result <- perms$check("write_file", list(path = "x.txt"), list())

  expect_s3_class(prompt_result, "PermissionResultAllow")
  expect_s3_class(deny_result, "PermissionResultDeny")
  expect_match(deny_result$reason, "ask_user", fixed = TRUE)
})

test_that("explicit tool gating applies to permission prompt tools", {
  denied <- Permissions$new(
    mode = "plan",
    tool_denylist = "ask_user",
    permission_prompt_tool_name = "ask_user"
  )
  excluded <- Permissions$new(
    mode = "plan",
    tool_allowlist = "read_file",
    permission_prompt_tool_name = "ask_user"
  )

  deny_result <- denied$check("ask_user", list(), list())
  excluded_result <- excluded$check("ask_user", list(), list())

  expect_s3_class(deny_result, "PermissionResultDeny")
  expect_match(deny_result$reason, "denylist")
  expect_false(grepl("Use ask_user", deny_result$reason, fixed = TRUE))
  expect_s3_class(excluded_result, "PermissionResultDeny")
  expect_match(excluded_result$reason, "allowlist")
  expect_false(grepl("Use ask_user", excluded_result$reason, fixed = TRUE))

  other_denial <- excluded$check("write_file", list(path = "x.txt"), list())
  expect_s3_class(other_denial, "PermissionResultDeny")
  expect_false(grepl("Use ask_user", other_denial$reason, fixed = TRUE))
})

test_that("file-write capability intersections choose the narrower root", {
  withr::local_tempdir(pattern = "deputy-permission-meet") -> container
  root <- file.path(container, "root")
  nested <- file.path(root, "nested")
  disjoint <- file.path(container, "other")
  dir.create(nested, recursive = TRUE)
  dir.create(disjoint)
  root <- normalizePath(root, winslash = "/")
  nested <- normalizePath(nested, winslash = "/")
  disjoint <- normalizePath(disjoint, winslash = "/")

  expect_false(intersect_file_write_capability(FALSE, TRUE))
  expect_identical(intersect_file_write_capability(TRUE, nested), nested)
  expect_identical(intersect_file_write_capability(nested, TRUE), nested)
  expect_identical(intersect_file_write_capability(root, nested), nested)
  expect_identical(intersect_file_write_capability(nested, root), nested)
  expect_false(intersect_file_write_capability(root, disjoint))
  expect_false(intersect_file_write_capability(NULL, root))
  expect_false(intersect_file_write_capability("relative/root", root))
  expect_false(intersect_file_write_capability(paste0(root, " "), TRUE))
  expect_false(intersect_file_write_capability(
    file.path(container, "missing"),
    TRUE
  ))
})

test_that("file-write intersections return stable canonical roots", {
  skip_on_os("windows")
  withr::local_tempdir(pattern = "deputy-permission-symlink") -> container
  real_root <- file.path(container, "real")
  other_root <- file.path(container, "other")
  alias <- file.path(container, "alias")
  dir.create(real_root)
  dir.create(other_root)
  skip_if_not(file.symlink(real_root, alias), "Symlinks are unavailable")

  canonical <- normalizePath(real_root, winslash = "/")
  first <- intersect_file_write_capability(alias, real_root)
  second <- intersect_file_write_capability(real_root, alias)
  expect_identical(first, canonical)
  expect_identical(second, canonical)

  unlink(alias)
  expect_true(file.symlink(other_root, alias))
  expect_identical(first, canonical)
  expect_false(is_path_within(file.path(other_root, "file.txt"), first))

  permissions <- Permissions$new(file_write = real_root)
  unlink(real_root, recursive = TRUE)
  expect_true(file.symlink(other_root, real_root))
  escaped <- permissions$check(
    "write_file",
    list(path = file.path(real_root, "file.txt")),
    list()
  )
  expect_s3_class(escaped, "PermissionResultDeny")
})

test_that("file-write directory grants are canonical and fail closed", {
  withr::local_tempdir(pattern = "deputy-permission-root") -> root
  canonical <- normalizePath(root, winslash = "/")

  permissions <- Permissions$new(file_write = root)
  expect_identical(permissions$file_write, canonical)
  expect_error(
    Permissions$new(file_write = "relative/root"),
    "existing absolute directory"
  )
  expect_error(
    Permissions$new(file_write = file.path(root, "missing")),
    "existing absolute directory"
  )
})

test_that("tool name matching ignores case", {
  perms <- Permissions$new(
    mode = "full",
    file_read = TRUE,
    file_write = TRUE,
    bash = TRUE,
    r_code = TRUE,
    tool_denylist = "RUN_BASH"
  )

  result <- perms$check("run_bash", list(command = "pwd"), list())
  expect_s3_class(result, "PermissionResultDeny")
})
