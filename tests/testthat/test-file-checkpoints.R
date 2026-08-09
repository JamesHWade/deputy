test_that("checkpoints restore exact binary file contents", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "binary.dat")
  original <- as.raw(c(0, 10, 13, 127, 128, 255))
  checkpoint_test_write_raw(path, original)
  store <- FileCheckpointStore$new(root)

  checkpoint_id <- store$checkpoint(
    "before binary write",
    metadata = list(turn = 3L)
  )
  expect_identical(
    store$before_tool(
      "Write",
      list(file_path = "binary.dat"),
      "tool-binary"
    ),
    TRUE
  )
  checkpoint_test_write_raw(path, as.raw(c(1, 2, 3)))
  expect_identical(store$after_tool("tool-binary", TRUE), TRUE)

  result <- store$rewind(checkpoint_id)

  expect_identical(checkpoint_test_read_raw(path), original)
  expect_identical(result$restored_changes, 1L)
  checkpoints <- store$list_checkpoints()
  expect_identical(checkpoints$checkpoint_id, checkpoint_id)
  expect_identical(checkpoints$metadata[[1]]$turn, 3L)
})

test_that("absolute paths through a filesystem root alias are accepted", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "absolute-alias.bin")
  original <- as.raw(c(0, 17, 255))
  checkpoint_test_write_raw(path, original)
  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("absolute path")

  expect_identical(
    store$before_tool(
      "Write",
      list(file_path = path),
      "absolute-alias"
    ),
    TRUE
  )
  checkpoint_test_write_raw(path, charToRaw("changed"))
  store$after_tool("absolute-alias", TRUE)
  store$rewind(checkpoint_id)

  expect_identical(checkpoint_test_read_raw(path), original)
})

test_that("journal activity is lazy and failed tool calls are discarded", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "file.txt")
  checkpoint_test_write_raw(path, charToRaw("original"))
  store <- FileCheckpointStore$new(root)

  expect_identical(
    store$before_tool(
      "write_file",
      list(path = "file.txt"),
      "before-checkpoint"
    ),
    FALSE
  )
  checkpoint_id <- store$checkpoint("start")
  expect_identical(
    store$before_tool(
      "read_file",
      list(path = "file.txt"),
      "read-only"
    ),
    FALSE
  )
  expect_identical(
    store$before_tool(
      "write_file",
      list(path = "file.txt"),
      "failed-write"
    ),
    TRUE
  )
  expect_identical(store$after_tool("failed-write", FALSE), FALSE)

  result <- store$rewind(checkpoint_id)
  expect_identical(result$restored_changes, 0L)
  expect_length(store$export_state()$journal, 0L)
})

test_that("failed tools retain preimages after partial writes", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "partial.txt")
  checkpoint_test_write_raw(path, charToRaw("original"))
  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("before partial write")

  store$before_tool(
    "write_file",
    list(path = "partial.txt"),
    "partial-write"
  )
  checkpoint_test_write_raw(path, charToRaw("truncated"))
  expect_identical(store$after_tool("partial-write", FALSE), TRUE)

  result <- store$rewind(checkpoint_id)

  expect_identical(checkpoint_test_read_raw(path), charToRaw("original"))
  expect_identical(result$restored_changes, 1L)
})

test_that("run teardown finalizes captures without tool results", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "orphaned.txt")
  checkpoint_test_write_raw(path, charToRaw("before"))
  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("before orphaned tool")

  store$before_tool(
    "write_file",
    list(path = "orphaned.txt"),
    "orphaned-tool"
  )
  checkpoint_test_write_raw(path, charToRaw("after"))

  expect_identical(store$finalize_pending(), 1L)
  expect_identical(store$finalize_pending(), 0L)
  expect_identical(store$rewind(checkpoint_id)$restored_changes, 1L)
  expect_identical(checkpoint_test_read_raw(path), charToRaw("before"))
})

test_that("verification errors journal failed tool preimages transactionally", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "became-directory.txt")
  original <- charToRaw("original")
  checkpoint_test_write_raw(path, original)
  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("before malformed write")

  store$before_tool(
    "write_file",
    list(path = "became-directory.txt"),
    "malformed-write"
  )
  expect_identical(unlink(path), 0L)
  expect_identical(dir.create(path), TRUE)

  expect_identical(store$after_tool("malformed-write", FALSE), TRUE)
  state <- store$export_state()
  expect_length(state$journal, 1L)
  expect_match(
    state$journal[[1]]$verification_error,
    "became a directory"
  )

  blocked <- checkpoint_test_error(store$rewind(checkpoint_id))
  expect_s3_class(blocked, "deputy_file_checkpoint_path_error")
  expect_length(store$export_state()$journal, 1L)

  expect_identical(unlink(path, recursive = TRUE), 0L)
  result <- store$rewind(checkpoint_id)
  expect_identical(checkpoint_test_read_raw(path), original)
  expect_identical(result$restored_changes, 1L)
})

test_that("verification errors retain preimages across unsafe symlinks", {
  skip_on_os("windows")
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  outside <- withr::local_tempdir(pattern = "deputy-checkpoint-outside-")
  path <- file.path(root, "became-link.txt")
  outside_path <- file.path(outside, "outside.txt")
  original <- charToRaw("original")
  checkpoint_test_write_raw(path, original)
  checkpoint_test_write_raw(outside_path, charToRaw("outside"))
  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("before unsafe link")

  store$before_tool(
    "write_file",
    list(path = "became-link.txt"),
    "unsafe-link"
  )
  expect_identical(unlink(path), 0L)
  expect_identical(file.symlink(outside_path, path), TRUE)

  expect_identical(store$after_tool("unsafe-link", FALSE), TRUE)
  expect_length(store$export_state()$journal, 1L)

  expect_identical(unlink(path), 0L)
  store$rewind(checkpoint_id)
  expect_identical(checkpoint_test_read_raw(path), original)
  expect_identical(checkpoint_test_read_raw(outside_path), charToRaw("outside"))
})

test_that("concurrent captures for one target fail closed", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "shared.txt")
  original <- charToRaw("original")
  checkpoint_test_write_raw(path, original)
  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("before overlapping writes")

  store$before_tool("Write", list(file_path = "shared.txt"), "write-a")
  checkpoint_test_write_raw(path, charToRaw("write-a"))
  overlap_error <- checkpoint_test_error(store$before_tool(
    "Edit",
    list(file_path = "shared.txt"),
    "write-b"
  ))

  expect_s3_class(overlap_error, "deputy_file_checkpoint_error")
  expect_match(conditionMessage(overlap_error), "concurrent writes")
  store$after_tool("write-a", TRUE)
  store$rewind(checkpoint_id)
  expect_identical(checkpoint_test_read_raw(path), original)
})

test_that("rewind follows capture order across reversed hard-link completion", {
  skip_on_os("windows")
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-hard-link-")
  first_path <- file.path(root, "first.txt")
  alias_path <- file.path(root, "alias.txt")
  original <- charToRaw("original")
  intermediate <- charToRaw("intermediate")
  final <- charToRaw("final")
  checkpoint_test_write_raw(first_path, original)
  if (!isTRUE(file.link(first_path, alias_path))) {
    skip("The test filesystem does not support hard links.")
  }

  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("before overlapping hard-link writes")

  store$before_tool("Write", list(path = "first.txt"), "write-first")
  checkpoint_test_write_raw(first_path, intermediate)
  expect_identical(checkpoint_test_read_raw(alias_path), intermediate)

  store$before_tool("Write", list(path = "alias.txt"), "write-alias")
  checkpoint_test_write_raw(alias_path, final)
  expect_identical(checkpoint_test_read_raw(first_path), final)

  store$after_tool("write-alias", TRUE)
  store$after_tool("write-first", TRUE)
  state <- store$export_state()
  expect_identical(
    vapply(
      state$journal,
      function(entry) entry$capture_sequence,
      integer(1)
    ),
    c(2L, 1L)
  )

  result <- store$rewind(checkpoint_id)
  expect_identical(result$restored_changes, 2L)
  expect_identical(checkpoint_test_read_raw(first_path), original)
  expect_identical(checkpoint_test_read_raw(alias_path), original)
})

test_that("per-file checkpoint byte limits reject oversized preimages", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "oversized.bin")
  original <- as.raw(1:5)
  checkpoint_test_write_raw(path, original)
  store <- FileCheckpointStore$new(
    root,
    max_file_bytes = 4,
    max_journal_bytes = 4096
  )
  store$checkpoint("before oversized capture")

  error <- checkpoint_test_error(store$before_tool(
    "write_file",
    list(path = "oversized.bin"),
    "oversized"
  ))

  expect_s3_class(error, "deputy_file_checkpoint_limit_error")
  expect_match(conditionMessage(error), "max_file_bytes")
  expect_identical(checkpoint_test_read_raw(path), original)
  state <- store$export_state()
  expect_length(state$journal, 0L)
  expect_identical(state$next_capture_sequence, 1L)
})

test_that("total checkpoint byte limits include journaled preimages", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  first_path <- file.path(root, "first.bin")
  second_path <- file.path(root, "second.bin")
  checkpoint_test_write_raw(first_path, as.raw(1:3))
  checkpoint_test_write_raw(second_path, as.raw(4:6))
  store <- FileCheckpointStore$new(
    root,
    max_file_bytes = 10,
    max_journal_bytes = 800
  )
  store$checkpoint("before total limit")

  store$before_tool("Write", list(path = "first.bin"), "first")
  checkpoint_test_write_raw(first_path, as.raw(7:9))
  store$after_tool("first", TRUE)
  error <- checkpoint_test_error(store$before_tool(
    "Write",
    list(path = "second.bin"),
    "second"
  ))

  expect_s3_class(error, "deputy_file_checkpoint_limit_error")
  expect_match(conditionMessage(error), "max_journal_bytes")
  expect_identical(checkpoint_test_read_raw(second_path), as.raw(4:6))
  state <- store$export_state()
  expect_length(state$journal, 1L)
  expect_identical(state$next_capture_sequence, 2L)
})

test_that("journal limits include checkpoint metadata and empty preimages", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-state-limit-")
  metadata_limited <- FileCheckpointStore$new(
    root,
    max_file_bytes = 100,
    max_journal_bytes = 100
  )
  metadata_error <- checkpoint_test_error(
    metadata_limited$checkpoint("metadata is state", list(note = "large"))
  )
  expect_s3_class(metadata_error, "deputy_file_checkpoint_limit_error")
  expect_equal(nrow(metadata_limited$list_checkpoints()), 0L)

  store <- FileCheckpointStore$new(
    root,
    max_file_bytes = 100,
    max_journal_bytes = 800
  )
  store$checkpoint("before empty files")
  store$before_tool("Write", list(path = "first.txt"), "first-empty")
  writeLines(character(), file.path(root, "first.txt"))
  store$after_tool("first-empty", TRUE)
  second_error <- checkpoint_test_error(store$before_tool(
    "Write",
    list(path = "second.txt"),
    "second-empty"
  ))
  expect_s3_class(second_error, "deputy_file_checkpoint_limit_error")
  expect_match(conditionMessage(second_error), "max_journal_bytes")
})

test_that("restored checkpoint state honors configured byte limits", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "restore-limit.bin")
  checkpoint_test_write_raw(path, as.raw(1:6))
  source <- FileCheckpointStore$new(root)
  source$checkpoint("before restore")
  source$before_tool("Write", list(path = "restore-limit.bin"), "write")
  checkpoint_test_write_raw(path, as.raw(7:12))
  source$after_tool("write", TRUE)

  file_limited <- FileCheckpointStore$new(
    root,
    max_file_bytes = 5,
    max_journal_bytes = 100
  )
  file_error <- checkpoint_test_error(
    file_limited$restore_state(source$export_state())
  )
  expect_s3_class(file_error, "deputy_file_checkpoint_limit_error")

  journal_limited <- FileCheckpointStore$new(
    root,
    max_file_bytes = 10,
    max_journal_bytes = 5
  )
  journal_error <- checkpoint_test_error(
    journal_limited$restore_state(source$export_state())
  )
  expect_s3_class(journal_error, "deputy_file_checkpoint_limit_error")
})

test_that("rewind removes files created after a checkpoint", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("empty root")
  path <- file.path(root, "nested", "new.bin")

  store$before_tool(
    "tool_write_file",
    list(path = "nested/new.bin"),
    "new-file"
  )
  checkpoint_test_write_raw(path, as.raw(c(0, 255)))
  store$after_tool("new-file", TRUE)

  expect_identical(file.exists(path), TRUE)
  store$rewind(checkpoint_id)
  expect_identical(file.exists(path), FALSE)
})

test_that("native and SDK aliases reverse multiple changes in order", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "sequence.txt")
  checkpoint_test_write_raw(path, charToRaw("zero"))
  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("zero")

  aliases <- list(
    list("Edit", list(file_path = "sequence.txt")),
    list("tool_multi_edit", list(path = "sequence.txt")),
    list("MultiEdit", list(file_path = "sequence.txt")),
    list("edit_file", list(path = "sequence.txt"))
  )
  values <- c("one", "two", "three", "four")

  for (i in seq_along(aliases)) {
    tool_use_id <- paste0("edit-", i)
    store$before_tool(aliases[[i]][[1]], aliases[[i]][[2]], tool_use_id)
    checkpoint_test_write_raw(path, charToRaw(values[[i]]))
    store$after_tool(tool_use_id, TRUE)
  }

  result <- store$rewind(checkpoint_id)
  expect_identical(checkpoint_test_read_raw(path), charToRaw("zero"))
  expect_identical(result$restored_changes, 4L)
})

test_that("all supported mutating tool aliases are recognized", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "aliases.txt")
  checkpoint_test_write_raw(path, charToRaw("unchanged"))
  store <- FileCheckpointStore$new(root)
  store$checkpoint("aliases")

  aliases <- c(
    "write_file",
    "tool_write_file",
    "Write",
    "edit_file",
    "tool_edit_file",
    "Edit",
    "multi_edit",
    "tool_multi_edit",
    "MultiEdit",
    "todo_write",
    "tool_todo_write",
    "TodoWrite"
  )

  for (i in seq_along(aliases)) {
    tool_use_id <- paste0("alias-", i)
    input <- if (i %% 2L == 0L) {
      list(file_path = "aliases.txt")
    } else {
      list(path = "aliases.txt")
    }
    expect_identical(
      store$before_tool(aliases[[i]], input, tool_use_id),
      TRUE,
      info = aliases[[i]]
    )
    expect_identical(
      store$after_tool(tool_use_id, FALSE),
      FALSE,
      info = aliases[[i]]
    )
  }
})

test_that("TodoWrite uses its default checkpoint path", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  todo_path <- file.path(root, ".deputy", "todos.json")
  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("before todos")

  store$before_tool("TodoWrite", list(todos = list()), "todo-write")
  checkpoint_test_write_raw(todo_path, charToRaw("[]"))
  store$after_tool("todo-write", TRUE)
  store$rewind(checkpoint_id)

  expect_identical(file.exists(todo_path), FALSE)
})

test_that("rewind invalidates future checkpoints and journal history", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "branch.txt")
  checkpoint_test_write_raw(path, charToRaw("root"))
  store <- FileCheckpointStore$new(root)
  root_checkpoint <- store$checkpoint("root")

  store$before_tool("write_file", list(path = "branch.txt"), "first")
  checkpoint_test_write_raw(path, charToRaw("first"))
  store$after_tool("first", TRUE)
  future_checkpoint <- store$checkpoint("future")

  store$before_tool("write_file", list(path = "branch.txt"), "second")
  checkpoint_test_write_raw(path, charToRaw("second"))
  store$after_tool("second", TRUE)
  store$rewind(root_checkpoint)

  expect_identical(store$list_checkpoints()$checkpoint_id, root_checkpoint)
  invalidated <- checkpoint_test_error(store$rewind(future_checkpoint))
  expect_s3_class(invalidated, "deputy_file_checkpoint_error")

  store$before_tool("Write", list(path = "branch.txt"), "replacement")
  checkpoint_test_write_raw(path, charToRaw("replacement"))
  store$after_tool("replacement", TRUE)
  second_rewind <- store$rewind(root_checkpoint)

  expect_identical(checkpoint_test_read_raw(path), charToRaw("root"))
  expect_identical(second_rewind$restored_changes, 1L)
})

test_that("exported journals restore into another store for the same root", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "persisted.bin")
  original <- as.raw(c(0, 1, 254, 255))
  checkpoint_test_write_raw(path, original)

  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("persisted", list(source = "test"))
  store$before_tool("write_file", list(path = "persisted.bin"), "persist")
  checkpoint_test_write_raw(path, charToRaw("changed"))
  store$after_tool("persist", TRUE)
  state <- store$export_state()
  expect_identical(state$version, 2L)
  expect_identical(state$next_capture_sequence, 2L)

  restored <- FileCheckpointStore$new(root)
  expect_identical(restored$restore_state(state), restored)
  expect_identical(
    restored$list_checkpoints()$checkpoint_id,
    checkpoint_id
  )
  restored$rewind(checkpoint_id)
  expect_identical(checkpoint_test_read_raw(path), original)

  restored$before_tool("Write", list(path = "persisted.bin"), "continued")
  checkpoint_test_write_raw(path, charToRaw("continued"))
  restored$after_tool("continued", TRUE)
  continued_state <- restored$export_state()
  expect_identical(
    continued_state$journal[[1]]$capture_sequence,
    2L
  )
  restored$rewind(checkpoint_id)
  expect_identical(checkpoint_test_read_raw(path), original)

  other_root <- withr::local_tempdir(pattern = "deputy-checkpoint-other-")
  wrong_root <- FileCheckpointStore$new(other_root)
  error <- checkpoint_test_error(wrong_root$restore_state(state))
  expect_s3_class(error, "deputy_file_checkpoint_path_error")
})

test_that("restored state validates capture sequences and marker boundaries", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-order-state-")
  first_path <- file.path(root, "first.txt")
  second_path <- file.path(root, "second.txt")
  checkpoint_test_write_raw(first_path, charToRaw("first"))
  checkpoint_test_write_raw(second_path, charToRaw("second"))

  store <- FileCheckpointStore$new(root)
  store$checkpoint("initial")
  store$before_tool("Write", list(path = "first.txt"), "first")
  checkpoint_test_write_raw(first_path, charToRaw("changed first"))
  store$after_tool("first", TRUE)
  store$checkpoint("between captures")
  store$before_tool("Write", list(path = "second.txt"), "second")
  checkpoint_test_write_raw(second_path, charToRaw("changed second"))
  store$after_tool("second", TRUE)
  state <- store$export_state()

  duplicate <- state
  duplicate$journal[[2]]$capture_sequence <- 1L
  duplicate_error <- checkpoint_test_error(
    FileCheckpointStore$new(root)$restore_state(duplicate)
  )
  expect_s3_class(duplicate_error, "deputy_file_checkpoint_error")
  expect_match(conditionMessage(duplicate_error), "duplicate capture")

  crossing <- state
  crossing$journal[[1]]$capture_sequence <- 2L
  crossing$journal[[2]]$capture_sequence <- 1L
  crossing_error <- checkpoint_test_error(
    FileCheckpointStore$new(root)$restore_state(crossing)
  )
  expect_s3_class(crossing_error, "deputy_file_checkpoint_error")
  expect_match(conditionMessage(crossing_error), "crosses a checkpoint")

  stale_counter <- state
  stale_counter$next_capture_sequence <- 2L
  counter_error <- checkpoint_test_error(
    FileCheckpointStore$new(root)$restore_state(stale_counter)
  )
  expect_s3_class(counter_error, "deputy_file_checkpoint_error")
  expect_match(conditionMessage(counter_error), "does not follow")
})

test_that("checkpoint identifiers fail closed at integer exhaustion", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  store <- FileCheckpointStore$new(root)
  state <- store$export_state()

  exhausted <- state
  exhausted$next_checkpoint_id <- .Machine$integer.max
  store$restore_state(exhausted)
  exhausted_error <- checkpoint_test_error(store$checkpoint("too far"))
  expect_s3_class(exhausted_error, "deputy_file_checkpoint_error")
  expect_match(conditionMessage(exhausted_error), "space is exhausted")
  expect_identical(
    store$export_state()$next_checkpoint_id,
    .Machine$integer.max
  )

  malformed <- state
  malformed$next_checkpoint_id <- as.double(.Machine$integer.max) + 1
  malformed_error <- checkpoint_test_error(
    FileCheckpointStore$new(root)$restore_state(malformed)
  )
  expect_s3_class(malformed_error, "deputy_file_checkpoint_error")
  expect_match(conditionMessage(malformed_error), "counter is malformed")
})

test_that("paths outside the root are refused", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  outside <- withr::local_tempdir(pattern = "deputy-checkpoint-outside-")
  outside_file <- file.path(outside, "outside.txt")
  checkpoint_test_write_raw(outside_file, charToRaw("outside"))
  store <- FileCheckpointStore$new(root)
  store$checkpoint("safe root")

  absolute_error <- checkpoint_test_error(store$before_tool(
    "write_file",
    list(path = outside_file),
    "absolute-escape"
  ))
  expect_s3_class(absolute_error, "deputy_file_checkpoint_path_error")

  relative_error <- checkpoint_test_error(store$before_tool(
    "Write",
    list(file_path = file.path("..", basename(outside), "outside.txt")),
    "relative-escape"
  ))
  expect_s3_class(relative_error, "deputy_file_checkpoint_path_error")
})

test_that("symlink escapes including dangling links are refused", {
  skip_on_os("windows")
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  outside <- withr::local_tempdir(pattern = "deputy-checkpoint-outside-")
  outside_file <- file.path(outside, "outside.txt")
  checkpoint_test_write_raw(outside_file, charToRaw("outside"))
  store <- FileCheckpointStore$new(root)
  store$checkpoint("safe root")

  link <- file.path(root, "escape")
  expect_identical(file.symlink(outside, link), TRUE)
  symlink_error <- checkpoint_test_error(store$before_tool(
    "Edit",
    list(file_path = "escape/outside.txt"),
    "symlink-escape"
  ))
  expect_s3_class(symlink_error, "deputy_file_checkpoint_path_error")

  dangling <- file.path(root, "dangling")
  expect_identical(
    file.symlink(file.path(outside, "not-created.txt"), dangling),
    TRUE
  )
  dangling_error <- checkpoint_test_error(store$before_tool(
    "Write",
    list(file_path = "dangling"),
    "dangling-escape"
  ))
  expect_s3_class(dangling_error, "deputy_file_checkpoint_path_error")
})

test_that("symlinks that remain inside the root restore their targets", {
  skip_on_os("windows")
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  target <- file.path(root, "target.bin")
  link <- file.path(root, "link.bin")
  original <- as.raw(c(0, 42, 255))
  checkpoint_test_write_raw(target, original)
  expect_identical(file.symlink(target, link), TRUE)
  store <- FileCheckpointStore$new(root)
  checkpoint_id <- store$checkpoint("before internal link")

  store$before_tool("Write", list(file_path = "link.bin"), "internal-link")
  checkpoint_test_write_raw(link, charToRaw("changed"))
  store$after_tool("internal-link", TRUE)
  store$rewind(checkpoint_id)

  expect_identical(checkpoint_test_read_raw(target), original)
  expect_identical(Sys.readlink(link), target)
})

test_that("restored state rejects tampered journal paths", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-")
  path <- file.path(root, "safe.txt")
  checkpoint_test_write_raw(path, charToRaw("safe"))
  store <- FileCheckpointStore$new(root)
  store$checkpoint("safe")
  store$before_tool("write_file", list(path = "safe.txt"), "safe-write")
  checkpoint_test_write_raw(path, charToRaw("changed"))
  store$after_tool("safe-write", TRUE)
  state <- store$export_state()
  state$journal[[1]]$path <- "../outside.txt"

  restored <- FileCheckpointStore$new(root)
  error <- checkpoint_test_error(restored$restore_state(state))

  expect_s3_class(error, "deputy_file_checkpoint_path_error")
})
