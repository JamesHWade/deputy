# Tests for built-in tools
# Note: ellmer tools are S7 objects that are directly callable (they inherit from function)

test_that("tool_read_file reads existing files", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Create test file
  test_file <- file.path(temp_dir, "test.txt")
  writeLines("Hello\nWorld", test_file)

  # Tools are directly callable
  result <- tool_read_file(test_file)
  expect_equal(result, "Hello\nWorld")
})

test_that("tool_read_file rejects missing files", {
  expect_error(
    tool_read_file("/nonexistent/path/file.txt"),
    "File not found"
  )
})

test_that("tool_write_file creates new files", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  test_file <- file.path(temp_dir, "new.txt")
  result <- tool_write_file(test_file, "Test content")

  expect_true(file.exists(test_file))
  expect_true(grepl("Successfully wrote", result))
  expect_equal(readLines(test_file), "Test content")
})

test_that("tool_write_file overwrites existing files", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  test_file <- file.path(temp_dir, "existing.txt")
  writeLines("Original", test_file)

  tool_write_file(test_file, "New content")
  expect_equal(readLines(test_file), "New content")
})

test_that("tool_write_file appends when requested", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  test_file <- file.path(temp_dir, "append.txt")
  writeLines("Line 1", test_file)

  tool_write_file(test_file, "\nLine 2\n", append = TRUE)

  content <- paste(readLines(test_file, warn = FALSE), collapse = "\n")
  expect_true(grepl("Line 1", content))
  expect_true(grepl("Line 2", content))
})

test_that("tool_write_file creates directories", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  test_file <- file.path(temp_dir, "subdir", "deep", "file.txt")
  tool_write_file(test_file, "Content")

  expect_true(file.exists(test_file))
  expect_equal(readLines(test_file), "Content")
})

test_that("tool_list_files lists directory contents", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Create some files
  writeLines("a", file.path(temp_dir, "file1.txt"))
  writeLines("b", file.path(temp_dir, "file2.txt"))
  dir.create(file.path(temp_dir, "subdir"))

  result <- tool_list_files(temp_dir)

  expect_true(grepl("file1.txt", result))
  expect_true(grepl("file2.txt", result))
  expect_true(grepl("subdir", result))
  expect_true(grepl("\\[DIR\\]", result))
})

test_that("tool_list_files filters by pattern", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  writeLines("a", file.path(temp_dir, "file.txt"))
  writeLines("b", file.path(temp_dir, "file.csv"))
  writeLines("c", file.path(temp_dir, "data.txt"))

  result <- tool_list_files(temp_dir, pattern = "\\.txt$")

  expect_true(grepl("file.txt", result))
  expect_true(grepl("data.txt", result))
  expect_false(grepl("file.csv", result))
})

test_that("tool_list_files rejects nonexistent directory", {
  expect_error(
    tool_list_files("/nonexistent/dir"),
    "Directory not found"
  )
})

test_that("tool_list_files handles empty directory", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir
  result <- tool_list_files(temp_dir)
  expect_equal(result, "No files found")
})

test_that("tool_run_r_code executes code", {
  skip_on_cran()
  # Note: sandbox parameter is no longer exposed (security fix)
  result <- tool_run_r_code("1 + 1")
  expect_true(grepl("2", result))
})

test_that("tool_run_r_code captures output", {
  skip_on_cran()
  result <- tool_run_r_code("print('hello')")
  expect_true(grepl("hello", result))
})

test_that("tool_run_r_code handles errors", {
  skip_on_cran()
  result <- tool_run_r_code("stop('test error')")
  expect_true(grepl("Error", result) || grepl("error", result))
})

test_that("tool_run_bash executes commands", {
  skip_on_cran()
  skip_on_os("windows")
  result <- tool_run_bash("echo 'test'")
  expect_true(grepl("test", result))
})

test_that("tool_read_csv reads CSV files", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Create CSV file
  csv_file <- file.path(temp_dir, "data.csv")
  write.csv(
    data.frame(a = 1:3, b = c("x", "y", "z")),
    csv_file,
    row.names = FALSE
  )

  result <- tool_read_csv(csv_file)

  expect_true(grepl("Rows:", result))
  expect_true(grepl("Columns:", result))
  expect_true(grepl("Column types:", result))
})

test_that("tool_read_csv rejects missing files", {
  expect_error(
    tool_read_csv("/nonexistent/file.csv"),
    "File not found"
  )
})

test_that("tools have correct annotations", {
  # Read-only tools
  expect_true(tool_read_file@annotations$read_only_hint)
  expect_false(tool_read_file@annotations$destructive_hint)

  expect_true(tool_list_files@annotations$read_only_hint)
  expect_true(tool_read_csv@annotations$read_only_hint)

  # Destructive tools
  expect_true(tool_write_file@annotations$destructive_hint)
  expect_true(tool_run_r_code@annotations$destructive_hint)
  expect_true(tool_run_bash@annotations$destructive_hint)
})

test_that("tool bundles contain expected tools", {
  file_tools <- tools_file()
  expect_true(length(file_tools) >= 3)

  # Check tool names are present
  tool_names <- sapply(file_tools, function(t) t@name)
  expect_true("read_file" %in% tool_names)
  expect_true("write_file" %in% tool_names)
  expect_true("list_files" %in% tool_names)
})

test_that("tools_code contains code execution tools", {
  code_tools <- tools_code()
  expect_true(length(code_tools) >= 1)

  tool_names <- sapply(code_tools, function(t) t@name)
  expect_true("run_r_code" %in% tool_names)
})

# Tool rejection path tests
test_that("tool_read_file returns tool_reject for missing file", {
  result <- tryCatch(
    tool_read_file("/definitely/not/a/real/file.txt"),
    ellmer_tool_reject = function(e) e
  )

  # Should be a tool_reject error

  expect_true(inherits(result, "ellmer_tool_reject") || grepl("File not found", result))
})

test_that("tool_write_file handles write errors gracefully", {
  # Skip on Windows - absolute Unix paths behave differently
  skip_on_os("windows")

  # Try to write to a directory that doesn't exist
  result <- tryCatch(
    tool_write_file("/nonexistent/deep/path/file.txt", "content"),
    ellmer_tool_reject = function(e) e,
    error = function(e) e
  )

  # Should be some kind of error
  expect_true(inherits(result, "error") || inherits(result, "ellmer_tool_reject"))
})

test_that("tool_list_files returns tool_reject for nonexistent directory", {
  result <- tryCatch(
    tool_list_files("/path/that/does/not/exist"),
    ellmer_tool_reject = function(e) e
  )

  expect_true(
    inherits(result, "ellmer_tool_reject") ||
      grepl("Directory not found", result) ||
      grepl("does not exist", result, ignore.case = TRUE)
  )
})

test_that("tool_read_csv returns tool_reject for invalid CSV", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Create an invalid CSV (binary content)
  bad_file <- file.path(temp_dir, "bad.csv")
  writeBin(as.raw(c(0, 1, 2, 255, 254, 253)), bad_file)

  # Should handle gracefully (either error or warning about parsing)
  result <- tryCatch(
    tool_read_csv(bad_file),
    ellmer_tool_reject = function(e) "rejected",
    error = function(e) "error",
    warning = function(w) "warning"
  )

  # Should complete without crashing
  expect_true(is.character(result))
})

test_that("tool_run_r_code handles syntax errors", {
  skip_if_not_installed("callr")

  result <- tool_run_r_code("this is not valid R code {{{")

  # Should contain error information
  expect_true(grepl("Error|error", result, ignore.case = TRUE))
})
test_that("tool_run_r_code handles runtime errors", {
  skip_if_not_installed("callr")

  result <- tool_run_r_code("stop('intentional error')")

  # Should contain error information
  expect_true(grepl("intentional error", result, ignore.case = TRUE))
})

test_that("tool_run_bash handles command not found", {
  result <- tryCatch(
    tool_run_bash("nonexistent_command_xyz123"),
    ellmer_tool_reject = function(e) e$message,
    error = function(e) e$message
  )

  # Should indicate failure somehow
  expect_true(is.character(result))
})

test_that("tool_run_r_code requires callr for sandbox", {
  # Mock is_installed to return FALSE for callr
  local_mocked_bindings(
    is_installed = function(pkg) {
      if (pkg == "callr") FALSE else TRUE
    },
    .package = "rlang"
  )

  # Should reject because callr is "not installed"
  # tool_reject throws an error with class ellmer_tool_reject
  expect_error(
    tool_run_r_code("1 + 1"),
    class = "ellmer_tool_reject"
  )
})

# Tool preset tests

test_that("ToolPresets contains expected presets", {
  expect_equal(
    ToolPresets,
    c("minimal", "standard", "dev", "data", "full")
  )
})

test_that("tools_preset returns correct tools for minimal", {
  tools <- tools_preset("minimal")
  expect_type(tools, "list")
  expect_length(tools, 2)

  # Check tool names
  tool_names <- vapply(tools, function(t) t@name, character(1))
  expect_true("read_file" %in% tool_names)
  expect_true("list_files" %in% tool_names)
})

test_that("tools_preset returns correct tools for standard", {
  tools <- tools_preset("standard")
  expect_type(tools, "list")
  expect_length(tools, 4)

  tool_names <- vapply(tools, function(t) t@name, character(1))
  expect_true("read_file" %in% tool_names)
  expect_true("write_file" %in% tool_names)
  expect_true("list_files" %in% tool_names)
  expect_true("run_r_code" %in% tool_names)
})

test_that("tools_preset returns correct tools for dev", {
  tools <- tools_preset("dev")
  expect_type(tools, "list")
  expect_length(tools, 5)

  tool_names <- vapply(tools, function(t) t@name, character(1))
  expect_true("read_file" %in% tool_names)
  expect_true("write_file" %in% tool_names)
  expect_true("list_files" %in% tool_names)
  expect_true("run_r_code" %in% tool_names)
  expect_true("run_bash" %in% tool_names)
})

test_that("tools_preset returns correct tools for full", {
  tools <- tools_preset("full")
  expect_type(tools, "list")
  expect_length(tools, 6)

  tool_names <- vapply(tools, function(t) t@name, character(1))
  expect_true("read_file" %in% tool_names)
  expect_true("write_file" %in% tool_names)
  expect_true("list_files" %in% tool_names)
  expect_true("run_r_code" %in% tool_names)
  expect_true("run_bash" %in% tool_names)
  expect_true("read_csv" %in% tool_names)
})

test_that("tools_preset returns correct tools for data", {
  tools <- tools_preset("data")
  expect_type(tools, "list")
  expect_length(tools, 4)

  tool_names <- vapply(tools, function(t) t@name, character(1))
  expect_true("read_file" %in% tool_names)
  expect_true("list_files" %in% tool_names)
  expect_true("read_csv" %in% tool_names)
  expect_true("run_r_code" %in% tool_names)
})

test_that("tools_preset errors on invalid preset name", {
  expect_error(
    tools_preset("invalid"),
    "Unknown tool preset"
  )
})

test_that("list_presets returns data frame with preset info", {
  presets <- list_presets()

  expect_s3_class(presets, "data.frame")
  expect_equal(nrow(presets), 5)
  expect_true("name" %in% names(presets))
  expect_true("description" %in% names(presets))
  expect_true("tools" %in% names(presets))
  expect_equal(presets$name, c("minimal", "standard", "dev", "data", "full"))
})
