test_that("checkpoint operations share the worker queue and restore only selected data", {
  directory <- withr::local_tempdir()
  agent <- Agent$new(chat = create_mock_chat(), working_dir = directory)
  session <- RSession$new(
    agent,
    checkpoint_dir = directory,
    checkpoint_owner_id = "one"
  )
  withr::defer(session$close())

  setup <- session$run(paste(
    "data <- data.frame(n = c(1L, NA_integer_), when = as.Date('2026-11-17'),",
    "group = factor(c('a', 'b'))); scratch <- 17"
  ))
  first <- session$checkpoint("data")
  update <- session$run("data$n[2] <- 3L")
  second <- session$checkpoint("data")
  r_session_await(setup)
  first <- r_session_await(first)
  r_session_await(update)
  second <- r_session_await(second)
  expect_identical(first$bindings, "data")
  expect_identical(first$generation, 1L)
  expect_false(identical(first$id, second$id))
  expect_false(identical(first$sha256, second$sha256))
  expect_error(
    r_session_await(session$restore_checkpoint(first$id)),
    class = "deputy_r_session_checkpoint"
  )

  session$cancel()
  restored <- r_session_await(session$restore_checkpoint(first$id))
  expect_identical(restored$restored_generation, 2L)
  expect_identical(restored$sha256, first$sha256)
  recovered <- r_session_await(session$run(paste(
    "stopifnot(identical(data$n, c(1L, NA_integer_)),",
    "identical(data$when, rep(as.Date('2026-11-17'), 2)),",
    "identical(data$group, factor(c('a', 'b'))),",
    "!exists('scratch', envir = globalenv(), inherits = FALSE));",
    "cat('recovered')"
  )))
  expect_match(r_session_text(recovered), "recovered")
})

test_that("invalid captures do not evaluate bindings or persist partial data", {
  directory <- withr::local_tempdir()
  agent <- Agent$new(chat = create_mock_chat(), working_dir = directory)
  session <- RSession$new(
    agent,
    checkpoint_dir = directory,
    checkpoint_owner_id = "one"
  )
  withr::defer(session$close())
  r_session_await(session$run(paste(
    "ok <- 42; callback <- function() 1;",
    "hidden <- structure(1, callback = callback);",
    "too_large <- raw(9 * 1024^2);",
    "assign('active_called', FALSE, envir = globalenv());",
    "makeActiveBinding('active', function() { active_called <<- TRUE; 1 }, globalenv());",
    "delayedAssign('lazy', { active_called <<- TRUE; 1 }, assign.env = globalenv())"
  )))
  for (binding in c(
    "callback",
    "hidden",
    "too_large",
    "active",
    "lazy",
    "absent"
  )) {
    expect_error(
      r_session_await(session$checkpoint(c("ok", binding))),
      class = "deputy_r_session_checkpoint"
    )
  }
  expect_length(list.files(directory, all.files = TRUE, no.. = TRUE), 0L)
  result <- r_session_await(session$run("stopifnot(!active_called); cat(ok)"))
  expect_match(r_session_text(result), "42")
  expect_identical(r_session_await(session$checkpoint("ok"))$bindings, "ok")
})

test_that("reset rejects a queued checkpoint without creating an artifact", {
  directory <- withr::local_tempdir()
  agent <- Agent$new(chat = create_mock_chat(), working_dir = directory)
  session <- RSession$new(
    agent,
    checkpoint_dir = directory,
    checkpoint_owner_id = "one"
  )
  withr::defer(session$close())
  first <- session$run("data <- 4L; Sys.sleep(10)")
  checkpoint <- promises::catch(session$checkpoint("data"), identity)
  session$cancel()
  expect_identical(r_session_await(first)@extra$deputy_r$outcome, "cancelled")
  expect_error(
    r_session_await(checkpoint),
    class = "deputy_r_session_checkpoint"
  )
  expect_length(list.files(directory, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("a restore checks the entire artifact and its owner before starting a worker", {
  directory <- withr::local_tempdir()
  open_session <- function(owner = "team-a", agent = "analysis", id = "trial") {
    RSession$new(
      Agent$new(
        chat = create_mock_chat(),
        working_dir = directory,
        agent_id = agent,
        session_id = id
      ),
      checkpoint_dir = directory,
      checkpoint_owner_id = owner
    )
  }
  source <- open_session()
  withr::defer(source$close())
  r_session_await(source$run("x <- 12L"))
  capture <- r_session_await(source$checkpoint("x"))
  r_session_await(source$run("x <- 14L"))
  other_capture <- r_session_await(source$checkpoint("x"))
  source$close()
  artifact <- list.files(directory, pattern = capture$id, full.names = TRUE)
  other_artifact <- list.files(
    directory,
    pattern = other_capture$id,
    full.names = TRUE
  )
  expect_length(artifact, 1L)
  expect_length(other_artifact, 1L)

  reject <- function(session, id = capture$id) {
    on.exit(session$close(), add = TRUE)
    expect_error(
      r_session_await(session$restore_checkpoint(id)),
      class = "deputy_r_session_checkpoint"
    )
    expect_null(session$status()$pid)
  }
  reject(open_session(owner = "team-b"))
  reject(open_session(agent = "other"))
  reject(open_session(id = "other"))
  reject(open_session(), id = "../unrelated")

  bytes <- file_checkpoint_read_raw(artifact)
  expect_true(file.copy(other_artifact, artifact, overwrite = TRUE))
  reject(open_session())
  changed <- bytes
  last <- length(changed)
  changed[[last]] <- as.raw(bitwXor(as.integer(changed[[last]]), 1L))
  file_checkpoint_write_raw(artifact, changed)
  reject(open_session())
  unlink(artifact)
  reject(open_session())
})
