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
