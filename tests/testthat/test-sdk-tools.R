# Tests for new built-in tools and compatibility aliases.

test_that("tool_edit_file replaces unique text", {
  withr::local_tempdir(pattern = "deputy-edit") -> temp_dir
  path <- file.path(temp_dir, "note.txt")
  writeLines(c("alpha", "beta"), path)

  result <- tool_edit_file(
    path = path,
    old_text = "beta",
    new_text = "gamma"
  )

  expect_match(result, "Successfully edited")
  expect_equal(readLines(path, warn = FALSE), c("alpha", "gamma"))
})

test_that("tool_multi_edit applies sequential edits", {
  withr::local_tempdir(pattern = "deputy-edit") -> temp_dir
  path <- file.path(temp_dir, "note.txt")
  writeLines(c("alpha", "beta"), path)

  result <- tool_multi_edit(
    path = path,
    edits = list(
      list(old_text = "alpha", new_text = "one"),
      list(old_text = "beta", new_text = "two")
    )
  )

  expect_match(result, "Successfully applied")
  expect_equal(readLines(path, warn = FALSE), c("one", "two"))
})

test_that("tool_glob_files and tool_grep_files search files", {
  withr::local_tempdir(pattern = "deputy-search") -> temp_dir
  dir.create(file.path(temp_dir, "R"), recursive = TRUE)
  writeLines("print('hello')", file.path(temp_dir, "R", "app.R"))
  writeLines("nothing to see", file.path(temp_dir, "README.txt"))

  globbed <- tool_glob_files(pattern = "R/*.R", path = temp_dir)
  grepped <- tool_grep_files(pattern = "hello", path = temp_dir)

  expect_match(globbed, "app.R")
  expect_match(grepped, "app.R:1")
})

test_that("todo tools round-trip JSON todo items", {
  withr::local_tempdir(pattern = "deputy-todo") -> temp_dir
  path <- file.path(temp_dir, "todos.json")

  written <- tool_todo_write(
    todos = list(
      list(id = "1", content = "Investigate regression", status = "pending"),
      list(id = "2", content = "Add tests", status = "done")
    ),
    path = path
  )
  read_back <- tool_todo_read(path = path)

  expect_equal(written$count, 2)
  expect_equal(length(read_back$items), 2)
  expect_equal(read_back$items[[1]]$content, "Investigate regression")
})

test_that("compatibility aliases resolve to expected tool names", {
  resolved <- compat_resolve_named_tools(c("Read", "Edit", "TodoWrite"))
  tool_names <- vapply(resolved, function(tool) tool@name, character(1))

  expect_equal(tool_names, c("Read", "Edit", "TodoWrite"))
})
