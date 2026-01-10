# Tests for utility functions

test_that("is_path_within detects valid paths", {
  # Create a temporary directory for testing
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Path within directory should return TRUE
  inner_path <- file.path(temp_dir, "subdir", "file.txt")
  expect_true(is_path_within(inner_path, temp_dir))

  # Same directory should return TRUE
  expect_true(is_path_within(temp_dir, temp_dir))
})

test_that("is_path_within rejects paths outside directory", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Path outside directory should return FALSE
  outside_path <- file.path(dirname(temp_dir), "other", "file.txt")
  expect_false(is_path_within(outside_path, temp_dir))

  # Root path should return FALSE
  expect_false(is_path_within("/etc/passwd", temp_dir))
})

test_that("is_path_within prevents directory prefix attacks", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Create a sibling directory with similar name
  sibling <- paste0(temp_dir, "-sibling")
  dir.create(sibling)
  withr::defer(unlink(sibling, recursive = TRUE))

  sibling_file <- file.path(sibling, "file.txt")

  # Should NOT match because sibling is not within temp_dir
  expect_false(is_path_within(sibling_file, temp_dir))
})

test_that("has_path_traversal detects traversal patterns", {
  # Parent directory references
  expect_true(has_path_traversal("../secret.txt"))
  expect_true(has_path_traversal("foo/../bar"))
  expect_true(has_path_traversal("foo/bar/../../baz"))

  # Home directory expansion
  expect_true(has_path_traversal("~/secret.txt"))
  expect_true(has_path_traversal("~user/file.txt"))

  # Invalid input
  expect_true(has_path_traversal(NULL))
  expect_true(has_path_traversal(123))
})

test_that("has_path_traversal allows safe paths", {
  # Relative paths without traversal
  expect_false(has_path_traversal("file.txt"))
  expect_false(has_path_traversal("subdir/file.txt"))
  expect_false(has_path_traversal("a/b/c/file.txt"))

  # Absolute paths are allowed (is_path_within handles them)
  expect_false(has_path_traversal("/etc/passwd"))
  expect_false(has_path_traversal("/var/log/syslog"))
  expect_false(has_path_traversal("/Users/test/file.txt"))
})

test_that("truncate_string works correctly", {
  # Short strings unchanged
  expect_equal(truncate_string("hello", 10), "hello")

  # Long strings truncated
  long_string <- paste(rep("a", 100), collapse = "")
  result <- truncate_string(long_string, 20)
  expect_equal(nchar(result), 20)
  expect_true(endsWith(result, "..."))

  # NULL handling
  expect_null(truncate_string(NULL))

  # Custom suffix
  result <- truncate_string(long_string, 20, suffix = "[...]")
  expect_true(endsWith(result, "[...]"))
})

test_that("format_cost formats correctly", {
  expect_equal(format_cost(0), "$0.0000")
  expect_equal(format_cost(0.0123), "$0.0123")
  expect_equal(format_cost(1.5), "$1.5000")

  # NULL/NA handling
  expect_equal(format_cost(NULL), "$0.00")
  expect_equal(format_cost(NA), "$0.00")
})

# Symlink and path security tests
test_that("is_path_within handles NULL and invalid inputs", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # NULL inputs should return FALSE

  expect_false(is_path_within(NULL, temp_dir))
  expect_false(is_path_within(temp_dir, NULL))
  expect_false(is_path_within(NULL, NULL))

  # Empty strings should return FALSE
  expect_false(is_path_within("", temp_dir))
  expect_false(is_path_within(temp_dir, ""))

  # Non-character inputs should return FALSE
  expect_false(is_path_within(123, temp_dir))
  expect_false(is_path_within(temp_dir, 123))
})

test_that("is_path_within handles tilde in literal path component", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Create a directory with literal ~ in the name
  tilde_dir <- file.path(temp_dir, "~subdir")
  dir.create(tilde_dir)
  withr::defer(unlink(tilde_dir, recursive = TRUE))

  # A path with ~ as a directory component (not at start) should be within
  # The ~ should NOT be expanded since it's in the middle of the path
  inner_path <- file.path(tilde_dir, "file.txt")
  expect_true(is_path_within(inner_path, temp_dir))
})

test_that("is_path_within blocks home directory reference at start", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Path starting with ~ should NOT be considered within temp_dir
  # even if after expansion it happens to resolve somewhere
  home_path <- "~/test/file.txt"
  expect_false(is_path_within(home_path, temp_dir))
})

test_that("resolve_symlinks follows symlink chains", {
  skip_on_os("windows") # Symlinks behave differently on Windows

  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Create a file
  real_file <- file.path(temp_dir, "real.txt")
  writeLines("test", real_file)

  # Create a symlink to the file
  link1 <- file.path(temp_dir, "link1")
  file.symlink(real_file, link1)
  withr::defer(unlink(link1))

  # Create a symlink to the symlink (chain)
  link2 <- file.path(temp_dir, "link2")
  file.symlink(link1, link2)
  withr::defer(unlink(link2))

  # resolve_symlinks should follow the chain
  resolved <- resolve_symlinks(link2)
  expect_equal(normalizePath(resolved), normalizePath(real_file))
})

test_that("resolve_symlinks returns NA for non-existent paths", {
  # Non-existent path should return NA (security: don't return unverified paths)
  result <- resolve_symlinks("/nonexistent/path")
  expect_true(is.na(result))
})

test_that("is_path_within blocks symlinks escaping directory", {
  skip_on_os("windows") # Symlinks behave differently on Windows

  withr::local_tempdir(pattern = "deputy-allowed") -> allowed_dir
  withr::local_tempdir(pattern = "deputy-escape") -> escape_dir

  # Create a file in the escape directory
  escape_file <- file.path(escape_dir, "secret.txt")
  writeLines("secret", escape_file)

  # Create a symlink in allowed_dir that points to escape_dir
  escape_link <- file.path(allowed_dir, "escape_link")
  file.symlink(escape_dir, escape_link)
  withr::defer(unlink(escape_link))

  # Path through symlink should be blocked (resolves outside allowed_dir)
  escape_path <- file.path(escape_link, "secret.txt")
  expect_false(is_path_within(escape_path, allowed_dir))
})

test_that("expand_and_normalize expands home directory", {
  # ~ should expand to home directory
  expanded <- expand_and_normalize("~/test")
  expect_true(startsWith(expanded, path.expand("~")))
  expect_false(grepl("^~", expanded))

  # NULL should return NA
  expect_true(is.na(expand_and_normalize(NULL)))

  # Empty string should return NA
  expect_true(is.na(expand_and_normalize("")))
})

# Tests for TOCTOU mitigation functions

test_that("validate_path_at_operation performs validation and operation atomically", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Create a test file
  test_file <- file.path(temp_dir, "test.txt")
  writeLines("hello", test_file)

  # Operation should succeed for valid path
  result <- validate_path_at_operation(
    path = test_file,
    allowed_dir = temp_dir,
    operation = function(normalized_path) {
      paste(readLines(normalized_path), collapse = "\n")
    }
  )
  expect_equal(result, "hello")
})

test_that("validate_path_at_operation rejects path traversal", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Path with .. should be rejected
  expect_error(
    validate_path_at_operation(
      path = file.path(temp_dir, "..", "escape.txt"),
      allowed_dir = temp_dir,
      operation = function(p) p
    ),
    "Path traversal detected"
  )

  # Path with ~ should be rejected
  expect_error(
    validate_path_at_operation(
      path = "~/escape.txt",
      allowed_dir = temp_dir,
      operation = function(p) p
    ),
    "Path traversal detected"
  )
})

test_that("validate_path_at_operation rejects paths outside allowed directory", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  expect_error(
    validate_path_at_operation(
      path = "/etc/passwd",
      allowed_dir = temp_dir,
      operation = function(p) p
    ),
    "Path outside allowed directory"
  )
})

test_that("validate_path_at_operation rejects invalid paths", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # NULL path
  expect_error(
    validate_path_at_operation(
      path = NULL,
      allowed_dir = temp_dir,
      operation = function(p) p
    ),
    "Invalid path"
  )

  # Empty path
  expect_error(
    validate_path_at_operation(
      path = "",
      allowed_dir = temp_dir,
      operation = function(p) p
    ),
    "Invalid path"
  )
})

test_that("secure_write_file writes content safely", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  test_file <- file.path(temp_dir, "output.txt")

  # Write should succeed for valid path
  secure_write_file(test_file, "test content", allowed_dir = temp_dir)
  expect_true(file.exists(test_file))
  expect_equal(readLines(test_file), "test content")
})

test_that("secure_write_file creates parent directories", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  nested_file <- file.path(temp_dir, "sub", "dir", "file.txt")

  secure_write_file(nested_file, "nested", allowed_dir = temp_dir)
  expect_true(file.exists(nested_file))
  expect_equal(readLines(nested_file), "nested")
})

test_that("secure_write_file rejects path outside allowed directory", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  expect_error(
    secure_write_file("/tmp/evil.txt", "content", allowed_dir = temp_dir),
    "Path outside allowed directory"
  )
})

test_that("secure_read_file reads content safely", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  test_file <- file.path(temp_dir, "test.txt")
  writeLines(c("line 1", "line 2"), test_file)

  result <- secure_read_file(test_file, allowed_dir = temp_dir)
  expect_equal(result, "line 1\nline 2")
})

test_that("secure_read_file rejects path outside allowed directory", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  expect_error(
    secure_read_file("/etc/passwd", allowed_dir = temp_dir),
    "Path outside allowed directory"
  )
})

test_that("secure_read_file errors on non-existent file", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  nonexistent <- file.path(temp_dir, "nonexistent.txt")

  expect_error(
    secure_read_file(nonexistent, allowed_dir = temp_dir),
    "File not found"
  )
})
