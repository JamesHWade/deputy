test_that("approval revisions survive reads and reject duplicate creation", {
  directory <- withr::local_tempdir()
  record <- list(
    schema_version = 1L,
    id = "approval_one",
    status = "pending",
    data = "private"
  )
  path <- approval_store_create(directory, record)
  expect_identical(
    path,
    normalizePath(file.path(directory, record$id), winslash = "/")
  )
  expect_identical(approval_store_read(path), record)
  expect_error(
    approval_store_create(directory, record),
    class = "deputy_approval_error"
  )
  expect_identical(approval_store_read(path), record)

  lock <- approval_store_lock(path)
  withr::defer(approval_store_unlock(lock))
  completed <- record
  completed$status <- "completed"
  approval_store_write(path, completed, lock)
  expect_identical(approval_store_read(path), completed)
  expect_length(approval_store_files(path), 2L)
  expect_identical(
    approval_store_decode(readRDS(approval_store_files(path)[[1]]), path),
    record
  )
  if (.Platform$OS.type != "windows") {
    expect_identical(as.character(file.info(path)$mode), "700")
    expect_true(all(
      as.character(file.info(approval_store_files(path))$mode) == "600"
    ))
  }
})

test_that("invalid and oversized writes preserve the preceding committed state", {
  directory <- withr::local_tempdir()
  record <- list(
    schema_version = 1L,
    id = "approval_bounded",
    status = "pending"
  )
  path <- approval_store_create(directory, record, max_bytes = 2000)
  lock <- approval_store_lock(path)
  withr::defer(approval_store_unlock(lock))

  invalid <- record
  invalid$schema_version <- 2L
  expect_error(
    approval_store_write(path, invalid, lock),
    class = "deputy_approval_error"
  )
  oversized <- record
  oversized$payload <- raw(3000)
  expect_error(
    approval_store_write(path, oversized, lock),
    class = "deputy_approval_error"
  )
  expect_identical(approval_store_read(path), record)
  expect_length(approval_store_files(path), 1L)
  expect_length(
    list.files(path, pattern = "^\\.pending-", all.files = TRUE),
    0L
  )

  # The aggregate bound also rejects records that fit individually.
  next_record <- record
  next_record$status <- "approved"
  next_record$payload <- raw(1200)
  expect_error(
    approval_store_write(path, next_record, lock),
    class = "deputy_approval_error"
  )
  expect_identical(approval_store_read(path), record)
  expect_length(approval_store_files(path), 1L)
  expect_length(
    list.files(path, pattern = "^\\.pending-", all.files = TRUE),
    0L
  )
})

test_that("failed rename leaves the previous record readable and cleans temporary data", {
  directory <- withr::local_tempdir()
  record <- list(
    schema_version = 1L,
    id = "approval_atomic",
    status = "pending"
  )
  path <- approval_store_create(directory, record)
  lock <- approval_store_lock(path)
  withr::defer(approval_store_unlock(lock))
  local_mocked_bindings(approval_store_rename = function(...) FALSE)
  completed <- record
  completed$status <- "completed"
  expect_error(
    approval_store_write(path, completed, lock),
    class = "deputy_approval_error"
  )
  expect_identical(approval_store_read(path), record)
  expect_length(approval_store_files(path), 1L)
  expect_length(
    list.files(path, pattern = "^\\.pending-", all.files = TRUE),
    0L
  )
})

test_that("inspection ignores uncommitted files but fails on corrupt committed data", {
  directory <- withr::local_tempdir()
  record <- list(
    schema_version = 1L,
    id = "approval_corrupt",
    status = "pending"
  )
  path <- approval_store_create(directory, record)
  writeLines("partial write", file.path(path, ".pending-crashed"))
  expect_identical(approval_store_read(path), record)
  lock <- approval_store_lock(path)
  withr::defer(approval_store_unlock(lock))
  record$status <- "approved"
  approval_store_write(path, record, lock)
  latest <- tail(approval_store_files(path), 1L)
  envelope <- readRDS(latest)
  envelope$payload[[1]] <- as.raw(0L)
  saveRDS(envelope, latest)
  expect_error(
    approval_store_read(path),
    "integrity",
    class = "deputy_approval_error"
  )
  expect_error(
    approval_store_write(path, record, lock),
    class = "deputy_approval_error"
  )
  writeLines("incomplete", latest)
  expect_error(approval_store_read(path), class = "deputy_approval_error")
})

test_that("writers require a live lock for the same approval", {
  directory <- withr::local_tempdir()
  record <- list(schema_version = 1L, id = "approval_a", status = "pending")
  first <- approval_store_create(directory, record)
  second_record <- record
  second_record$id <- "approval_b"
  second <- approval_store_create(directory, second_record)
  lock <- approval_store_lock(first)
  withr::defer(approval_store_unlock(lock))
  expect_error(approval_store_lock(first), class = "deputy_approval_error")
  expect_error(
    approval_store_write(second, second_record, lock),
    class = "deputy_approval_error"
  )
  expect_error(
    approval_store_write(first, record, NULL),
    class = "deputy_approval_error"
  )
  expect_identical(approval_store_read(first), record)
  approval_store_unlock(lock)
  expect_error(
    approval_store_write(first, record, lock),
    class = "deputy_approval_error"
  )
  fresh_lock <- approval_store_lock(first)
  withr::defer(approval_store_unlock(fresh_lock))
  expect_error(
    approval_store_write(first, record, lock),
    class = "deputy_approval_error"
  )
  expect_no_error(approval_store_write(first, record, fresh_lock))
})

test_that("cross-process locks block writers without blocking inspection", {
  directory <- withr::local_tempdir()
  record <- list(
    schema_version = 1L,
    id = "approval_process",
    status = "pending"
  )
  path <- approval_store_create(directory, record)
  lock <- approval_store_lock(path)
  withr::defer(approval_store_unlock(lock))
  result <- callr::r(
    function(path, package_path) {
      if (file.exists(file.path(package_path, "R", "agent.R"))) {
        pkgload::load_all(package_path, quiet = TRUE)
      } else {
        library(deputy, lib.loc = dirname(package_path))
      }
      read <- getFromNamespace("approval_store_read", "deputy")
      lock <- getFromNamespace("approval_store_lock", "deputy")
      list(
        record = read(path),
        error = tryCatch(lock(path), deputy_approval_error = function(e) {
          e$reason
        })
      )
    },
    args = list(path, getNamespaceInfo(asNamespace("deputy"), "path")),
    libpath = .libPaths()
  )
  expect_identical(result$record, record)
  expect_identical(result$error, "busy")
})

test_that("the operating system releases an approval lock when its process dies", {
  directory <- withr::local_tempdir()
  record <- list(schema_version = 1L, id = "approval_crash", status = "pending")
  path <- approval_store_create(directory, record)
  ready <- file.path(directory, "ready")
  child <- callr::r_bg(
    function(path, ready) {
      handle <- filelock::lock(file.path(path, ".lock"), timeout = 0)
      saveRDS(!is.null(handle), paste0(ready, ".tmp"))
      file.rename(paste0(ready, ".tmp"), ready)
      Sys.sleep(60)
    },
    args = list(path, ready),
    libpath = .libPaths()
  )
  withr::defer(child$kill())
  deadline <- Sys.time() + 10
  while (!file.exists(ready) && child$is_alive() && Sys.time() < deadline) {
    Sys.sleep(0.02)
  }
  expect_true(file.exists(ready))
  expect_true(readRDS(ready))
  expect_error(approval_store_lock(path), class = "deputy_approval_error")
  child$kill()
  child$wait(timeout = 5000)
  expect_false(child$is_alive())
  lock <- approval_store_lock(path)
  withr::defer(approval_store_unlock(lock))
  record$status <- "completed"
  expect_no_error(approval_store_write(path, record, lock))
  expect_identical(approval_store_read(path), record)
})

test_that("externally released lock handles cannot authorize writes", {
  directory <- withr::local_tempdir()
  record <- list(
    schema_version = 1L,
    id = "approval_unlocked",
    status = "pending"
  )
  path <- approval_store_create(directory, record)
  lock <- approval_store_lock(path)
  withr::defer(approval_store_unlock(lock))
  filelock::unlock(lock$handle)
  expect_error(
    approval_store_write(path, record, lock),
    class = "deputy_approval_error"
  )
  expect_no_error(approval_store_unlock(lock))
  next_lock <- approval_store_lock(path)
  withr::defer(approval_store_unlock(next_lock))
  expect_no_error(approval_store_write(path, record, next_lock))
})

test_that("invalid creation cannot escape the store or leave partial approvals", {
  directory <- withr::local_tempdir()
  record <- list(schema_version = 1L, id = "../escaped", status = "pending")
  expect_error(
    approval_store_create(directory, record),
    class = "deputy_approval_error"
  )
  record$id <- "approval_tiny"
  expect_error(
    approval_store_create(directory, record, max_bytes = 1),
    class = "deputy_approval_error"
  )
  expect_false(dir.exists(file.path(directory, record$id)))
  expect_error(
    approval_store_create(directory, record, max_bytes = Inf),
    class = "deputy_approval_error"
  )
  expect_error(
    approval_store_read(file.path(directory, "missing")),
    class = "deputy_approval_error"
  )
  expect_error(
    approval_store_lock(file.path(directory, "missing")),
    class = "deputy_approval_error"
  )
})
