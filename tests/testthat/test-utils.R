# Tests for internal path, IO, and utility helpers

test_that("is_path_within_permission_root detects valid paths", {
  # Skip on Windows due to 8.3 short name vs long name normalization differences
  skip_on_os("windows")

  temp_dir <- withr::local_tempdir(pattern = "deputy-test")
  root <- canonical_permission_root(temp_dir)

  inner_path <- file.path(temp_dir, "subdir", "file.txt")
  expect_true(is_path_within_permission_root(inner_path, root))
  expect_true(is_path_within_permission_root(temp_dir, root))
})

test_that("is_path_within_permission_root rejects paths outside directory", {
  temp_dir <- withr::local_tempdir(pattern = "deputy-test")
  root <- canonical_permission_root(temp_dir)

  outside_path <- file.path(dirname(temp_dir), "other", "file.txt")
  expect_false(is_path_within_permission_root(outside_path, root))
  expect_false(is_path_within_permission_root("/etc/passwd", root))
})

test_that("is_path_within_permission_root prevents directory prefix attacks", {
  temp_dir <- withr::local_tempdir(pattern = "deputy-test")
  root <- canonical_permission_root(temp_dir)

  sibling <- paste0(temp_dir, "-sibling")
  dir.create(sibling)
  withr::defer(unlink(sibling, recursive = TRUE))

  sibling_file <- file.path(sibling, "file.txt")
  expect_false(is_path_within_permission_root(sibling_file, root))
})

test_that("has_path_traversal detects traversal patterns", {
  expect_true(has_path_traversal("../secret.txt"))
  expect_true(has_path_traversal("foo/../bar"))
  expect_true(has_path_traversal("foo/bar/../../baz"))
  expect_true(has_path_traversal("~/secret.txt"))
  expect_true(has_path_traversal("~user/file.txt"))
  expect_true(has_path_traversal(NULL))
  expect_true(has_path_traversal(123))
})

test_that("has_path_traversal allows safe paths", {
  expect_false(has_path_traversal("file.txt"))
  expect_false(has_path_traversal("subdir/file.txt"))
  expect_false(has_path_traversal("a/b/c/file.txt"))
  expect_false(has_path_traversal("/etc/passwd"))
  expect_false(has_path_traversal("/var/log/syslog"))
  expect_false(has_path_traversal("/Users/test/file.txt"))
})

test_that("has_path_traversal matches .. only as a whole path segment", {
  expect_false(has_path_traversal("notes..v2.md"))
  expect_false(has_path_traversal("subdir/notes..v2.md"))
  expect_false(has_path_traversal("..hidden"))
  expect_false(has_path_traversal("a..b/c..d/file.txt"))
  expect_false(has_path_traversal("file.."))

  expect_true(has_path_traversal(".."))
  expect_true(has_path_traversal("foo/.."))
  expect_true(has_path_traversal("foo\\..\\bar"))
  expect_true(has_path_traversal("..\\escape.txt"))
  expect_true(has_path_traversal("/tmp/allowed/../escape.txt"))

  # Windows trims trailing dots and spaces, so these are flagged too
  expect_true(has_path_traversal(".../escape.txt"))
  expect_true(has_path_traversal("foo/.. /escape.txt"))
  expect_true(has_path_traversal("foo/..."))
})

test_that("truncate_string works correctly", {
  expect_equal(truncate_string("hello", 10), "hello")

  long_string <- paste(rep("a", 100), collapse = "")
  result <- truncate_string(long_string, 20)
  expect_equal(nchar(result), 20)
  expect_true(endsWith(result, "..."))

  expect_null(truncate_string(NULL))

  result <- truncate_string(long_string, 20, suffix = "[...]")
  expect_true(endsWith(result, "[...]"))
})

test_that("format_cost formats correctly", {
  expect_equal(format_cost(0), "$0.0000")
  expect_equal(format_cost(0.0123), "$0.0123")
  expect_equal(format_cost(1.5), "$1.5000")

  expect_equal(format_cost(NULL), "unknown")
  expect_equal(format_cost(NA), "unknown")
})

test_that("is_path_within_permission_root handles tilde and symlinks", {
  skip_on_os("windows")

  temp_dir <- withr::local_tempdir(pattern = "deputy-test")
  root <- canonical_permission_root(temp_dir)

  # Tilde inside a literal directory name is allowed
  tilde_dir <- file.path(temp_dir, "~subdir")
  dir.create(tilde_dir)
  expect_true(is_path_within_permission_root(
    file.path(tilde_dir, "file.txt"),
    root
  ))

  # Home directory reference at start resolves outside temp_dir
  expect_false(is_path_within_permission_root("~/test/file.txt", root))

  # Symlink chain resolves to target
  real_file <- file.path(temp_dir, "real.txt")
  writeLines("test", real_file)
  link1 <- file.path(temp_dir, "link1")
  link2 <- file.path(temp_dir, "link2")
  file.symlink(real_file, link1)
  file.symlink(link1, link2)
  expect_equal(
    resolve_path_components(link2),
    expand_and_normalize(real_file)
  )

  # Symlink escaping allowed directory is blocked
  escape_dir <- withr::local_tempdir(pattern = "deputy-escape")
  writeLines("secret", file.path(escape_dir, "secret.txt"))
  escape_link <- file.path(temp_dir, "escape_link")
  file.symlink(escape_dir, escape_link)
  expect_false(is_path_within_permission_root(
    file.path(escape_link, "secret.txt"),
    root
  ))
})

test_that("expand_and_normalize expands home directory and handles invalid input", {
  skip_on_os("windows")

  expanded <- expand_and_normalize("~/test")
  expect_true(startsWith(expanded, path.expand("~")))
  expect_false(grepl("^~", expanded))

  expect_true(is.na(expand_and_normalize(NULL)))
  expect_true(is.na(expand_and_normalize("")))
})

test_that("validate_path_at_operation performs validation and operation atomically", {
  temp_dir <- withr::local_tempdir(pattern = "deputy-test")
  test_file <- file.path(temp_dir, "test.txt")
  writeLines("hello", test_file)

  result <- validate_path_at_operation(
    path = test_file,
    allowed_dir = canonical_permission_root(temp_dir),
    operation = function(normalized_path) {
      paste(readLines(normalized_path), collapse = "\n")
    }
  )
  expect_equal(result, "hello")
})

test_that("validate_path_at_operation rejects traversal, outside, and invalid paths", {
  temp_dir <- withr::local_tempdir(pattern = "deputy-test")
  root <- canonical_permission_root(temp_dir)

  expect_error(
    validate_path_at_operation(
      path = file.path(temp_dir, "..", "escape.txt"),
      allowed_dir = root,
      operation = function(p) p
    ),
    "Path traversal detected"
  )
  expect_error(
    validate_path_at_operation(
      path = "~/escape.txt",
      allowed_dir = root,
      operation = function(p) p
    ),
    "Path traversal detected"
  )
  expect_error(
    validate_path_at_operation(
      path = "/etc/passwd",
      allowed_dir = root,
      operation = function(p) p
    ),
    "Path outside allowed directory"
  )
  expect_error(
    validate_path_at_operation(
      path = NULL,
      allowed_dir = root,
      operation = function(p) p
    ),
    "Invalid path"
  )
  expect_error(
    validate_path_at_operation(
      path = "",
      allowed_dir = root,
      operation = function(p) p
    ),
    "Invalid path"
  )
})

test_that("validate_path_at_operation keeps the directory the policy resolved", {
  skip_on_os("windows")
  parent <- withr::local_tempdir(pattern = "deputy-test")
  allowed <- file.path(parent, "allowed")
  outside <- file.path(parent, "outside")
  dir.create(allowed)
  dir.create(outside)
  root <- Permissions(file_write = allowed)@file_write

  # The allowed directory is replaced by a link to another directory.
  file.rename(allowed, file.path(parent, "moved"))
  file.symlink(outside, allowed)
  ran <- FALSE
  expect_error(
    validate_path_at_operation(
      path = file.path(allowed, "file.txt"),
      allowed_dir = root,
      operation = function(p) ran <<- TRUE
    ),
    class = "deputy_unsafe_path"
  )
  expect_false(ran)
  expect_false(file.exists(file.path(outside, "file.txt")))
})

test_that("shared utility primitives behave consistently", {
  expect_true(has_unique_names(list(a = 1, b = 2)))
  expect_false(has_unique_names(list(1, 2)))
  expect_false(has_unique_names(list(a = 1, a = 2)))
  expect_false(has_unique_names(stats::setNames(list(1, 2), c("a", ""))))
  expect_false(has_unique_names(stats::setNames(list(1, 2), c("a", NA))))

  expect_null(validate_positive_int(NULL, "n"))
  expect_identical(validate_positive_int(5, "n"), 5L)
  expect_error(validate_positive_int(0, "n"), "positive whole number")
  expect_error(
    validate_positive_int(NULL, "n", allow_null = FALSE),
    "positive whole number"
  )
  expect_identical(validate_nonnegative_int(0, "n"), 0L)
  expect_error(validate_nonnegative_int(-1, "n"), "non-negative whole number")

  expect_identical(validate_positive_timeout(2.5, "timeout"), 2.5)
  expect_error(
    validate_positive_timeout(0, "timeout", class = "custom_timeout"),
    class = "deputy_custom_timeout"
  )

  tool <- ellmer::tool(
    fun = function() "ok",
    name = "demo",
    description = "Demo tool",
    arguments = list()
  )
  wrapped <- runtime_wrap_tool(
    tool,
    resolve_arguments = function(name, args) args,
    process_result = function(name, value, id) value
  )
  expect_identical(runtime_source_tool(tool), tool)
  expect_identical(runtime_source_tool(wrapped), tool)

  dir <- withr::local_tempdir()
  target <- file.path(dir, "data.bin")
  payload <- charToRaw("hello-world")
  write_file_atomic(target, function(tmp) writeBin(payload, tmp))
  expect_identical(read_file_raw_bounded(target, max_bytes = 64), payload)
  expect_error(
    read_file_raw_bounded(target, max_bytes = 4),
    "exceeds its configured byte limit"
  )

  expect_no_error(assert_portable_data(list(a = 1L, b = "x")))
  expect_error(
    assert_portable_data(list(fn = function() 1)),
    class = "deputy_error"
  )
})

test_that("functions sent to a child process keep no source references", {
  fun <- eval(parse(
    text = "function() tryCatch(stop('x'), error = function(e) 'handled')",
    keep.source = TRUE
  ))
  expect_s3_class(body(fun)[[3L]][[4L]], "srcref")

  sent <- child_function(fun)
  expect_null(attr(sent, "srcref"))
  expect_null(body(sent)[[3L]][[4L]])
  expect_identical(environment(sent), baseenv())
  expect_identical(sent(), "handled")
  expect_identical(environment(child_function(fun, globalenv())), globalenv())
})
