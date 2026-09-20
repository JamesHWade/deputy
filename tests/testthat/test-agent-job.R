job_test_receipt <- function(job) {
  list(
    job_id = job$id,
    owner_id = job$owner_id,
    definition_revision = job$definition_revision,
    context_revision = job$context_revision
  )
}

job_test_agent <- function(responses = list("done")) {
  Agent$new(chat = create_mock_chat(responses = responses))
}

test_that("job_create commits a bounded queued inspection", {
  directory <- withr::local_tempdir(pattern = "deputy-job-create-")
  agent <- job_test_agent()

  path <- job_create(
    directory = directory,
    agent = agent,
    task = "answer once",
    owner_id = "owner-1",
    definition_revision = "definition-1",
    context_revision = "context-1",
    usage_limits = UsageLimits(max_requests = 2L),
    associations = list(conversation_id = "conversation-1")
  )
  job <- job_read(path)

  expect_s7_class(job, AgentJob)
  expect_identical(job$status, "queued")
  expect_identical(job$owner_id, "owner-1")
  expect_identical(job$associations$conversation_id, "conversation-1")
  expect_true(length(list.files(path, pattern = "^revision-")) == 1L)
  expect_error(job$status <- "completed")
})

test_that("terminal dispatch is durable and never binds twice", {
  directory <- withr::local_tempdir(pattern = "deputy-job-dispatch-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  bound <- 0L
  bind <- function(job) {
    bound <<- bound + 1L
    agent
  }

  first <- job_run(path, bind = bind, authorize = job_test_receipt)
  second <- job_run(
    path,
    bind = function(job) stop("a terminal job must not bind"),
    authorize = job_test_receipt
  )

  expect_identical(first$status, "completed")
  expect_identical(second$status, "completed")
  expect_identical(bound, 1L)
  expect_identical(second$result$response, "done")
})

test_that("authorization is an exact receipt and precedes binding", {
  directory <- withr::local_tempdir(pattern = "deputy-job-auth-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  bound <- 0L
  expect_error(
    job_run(
      path,
      bind = function(job) {
        bound <<- bound + 1L
        agent
      },
      authorize = function(job) {
        list(
          job_id = job$id,
          owner_id = job$owner_id,
          definition_revision = "stale",
          context_revision = job$context_revision
        )
      }
    ),
    class = "deputy_job_stale"
  )
  expect_identical(bound, 0L)
  expect_identical(job_read(path)$status, "queued")
  expect_error(
    job_run(path, bind = function(job) agent, authorize = function(job) TRUE),
    class = "deputy_job_unauthorized"
  )
})

test_that("binder cleanup is recorded and called once", {
  directory <- withr::local_tempdir(pattern = "deputy-job-cleanup-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  cleanups <- 0L
  first <- job_run(
    path,
    bind = function(job) {
      list(
        agent = agent,
        cleanup = function() {
          cleanups <<- cleanups + 1L
        }
      )
    },
    authorize = job_test_receipt
  )

  expect_identical(first$status, "completed")
  expect_identical(cleanups, 1L)
  expect_identical(first$cleanup$status, "completed")
  expect_identical(first$cleanup$attempts, 1L)
  second <- job_run(
    path,
    bind = function(job) stop("a terminal job must not bind"),
    authorize = job_test_receipt
  )
  expect_identical(second$status, "completed")
  expect_identical(cleanups, 1L)
})

test_that("cleanup failure retains the successful task result", {
  directory <- withr::local_tempdir(pattern = "deputy-job-cleanup-result-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )

  failed <- job_run(
    path,
    bind = function(job) {
      list(
        agent = agent,
        cleanup = function() stop("cleanup failed")
      )
    },
    authorize = job_test_receipt
  )

  expect_identical(failed$status, "failed")
  expect_identical(failed$result$response, "done")
  expect_identical(failed$cleanup$status, "failed")
  expect_match(failed$cleanup$error$message, "cleanup failed")
})

test_that("abnormal worker exit persists cleanup before releasing its lock", {
  directory <- withr::local_tempdir(pattern = "deputy-job-abort-cleanup-")
  interrupt_agent <- R6::R6Class(
    "JobInterruptAgent",
    inherit = Agent,
    public = list(
      run_sync = function(...) {
        stop(structure(
          list(message = "interrupt"),
          class = c("interrupt", "condition")
        ))
      }
    )
  )$new(chat = create_mock_chat(responses = list("unused")))
  path <- job_create(
    directory,
    interrupt_agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  marker <- file.path(directory, "cleanup-lock.txt")

  interrupted <- tryCatch(
    job_run(
      path,
      bind = function(job) {
        list(
          agent = interrupt_agent,
          cleanup = function() {
            probe <- tryCatch(
              approval_store_lock(path),
              error = identity
            )
            if (inherits(probe, "error") && identical(probe$reason, "busy")) {
              writeLines("locked", marker)
            } else {
              writeLines("unlocked", marker)
              if (is.list(probe)) approval_store_unlock(probe)
            }
          }
        )
      },
      authorize = job_test_receipt
    ),
    interrupt = identity
  )
  expect_s3_class(interrupted, "interrupt")

  persisted <- job_read(path)
  expect_identical(readLines(marker), "locked")
  expect_identical(persisted$status, "running")
  expect_identical(persisted$cleanup$status, "completed")
  expect_identical(persisted$cleanup$attempts, 1L)
})

test_that("cancellation persists maximum-length UTF-8 reasons", {
  directory <- withr::local_tempdir(pattern = "deputy-job-long-cancel-")
  for (reason in c(strrep("x", 4096L), strrep("\u00e9", 2048L))) {
    path <- job_create(
      directory,
      job_test_agent(),
      "answer once",
      "owner-1",
      "definition-1",
      "context-1",
      UsageLimits(max_requests = 2L)
    )
    cancelled <- job_cancel(path, job_test_receipt, reason = reason)
    restored <- job_read(path)
    expect_identical(cancelled$status, "cancelled")
    expect_identical(restored$control$status, "cancelled")
    expect_identical(restored$control$reason, reason)
  }
})

test_that("cancellation returns the committed control when completion races it", {
  directory <- withr::local_tempdir(pattern = "deputy-job-cancel-race-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  cancelled <- job_cancel(
    path,
    authorize = function(job) {
      # Finish after cancellation reads the queued record but before it can
      # acquire the execution lock, using the real governed job path.
      job_run(path, bind = function(job) agent, authorize = job_test_receipt)
      job_test_receipt(job)
    },
    reason = "finished during authorization"
  )
  restored <- job_read(path)
  expect_identical(cancelled$status, "completed")
  expect_identical(cancelled$control$status, "acknowledged")
  expect_identical(cancelled$control, restored$control)
  expect_identical(cancelled$result$response, "done")
})

test_that("cancellation control lock contention is surfaced for retry", {
  directory <- withr::local_tempdir(pattern = "deputy-job-cancel-busy-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  record <- job_record_read(path)$record
  control_lock <- approval_store_lock(job_control_path(path, record))
  on.exit(
    if (!is.null(control_lock)) approval_store_unlock(control_lock),
    add = TRUE
  )

  expect_error(
    job_cancel(path, authorize = job_test_receipt),
    class = "deputy_job_busy"
  )

  approval_store_unlock(control_lock)
  control_lock <- NULL
  cancelled <- job_cancel(path, authorize = job_test_receipt)
  expect_identical(cancelled$status, "cancelled")
  expect_identical(cancelled$control$status, "cancelled")
})

test_that("authorized retry repairs a requested terminal control", {
  directory <- withr::local_tempdir(pattern = "deputy-job-terminal-retry-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  record <- job_record_read(path)$record
  record <- job_transition(record, "running", "worker started")
  record <- job_transition(record, "completed", "worker completed")
  lock <- approval_store_lock(path)
  job_record_write(path, record, lock)
  approval_store_unlock(lock)
  job_control_write(path, record, "requested", "user_cancelled")

  control_lock <- approval_store_lock(job_control_path(path, record))
  on.exit(
    if (!is.null(control_lock)) approval_store_unlock(control_lock),
    add = TRUE
  )
  expect_error(
    job_cancel(path, authorize = job_test_receipt),
    class = "deputy_job_busy"
  )

  approval_store_unlock(control_lock)
  control_lock <- NULL
  repaired <- job_cancel(path, authorize = job_test_receipt)
  expect_identical(repaired$status, "completed")
  expect_identical(repaired$control$status, "acknowledged")
  expect_true(repaired$control$requested)
  expect_identical(repaired$control, job_read(path)$control)
})

test_that("busy execution lock reconciles a terminal worker control", {
  directory <- withr::local_tempdir(pattern = "deputy-job-cancel-settle-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  record <- job_record_read(path)$record
  record <- job_transition(record, "running", "worker started")
  lock <- approval_store_lock(path)
  job_record_write(path, record, lock)
  approval_store_unlock(lock)

  original_lock <- get("approval_store_lock", asNamespace("deputy"))
  original_unlock <- get("approval_store_unlock", asNamespace("deputy"))
  settled <- FALSE
  settling <- FALSE
  local_mocked_bindings(
    approval_store_lock = function(lock_path) {
      if (identical(lock_path, path) && !settling && !settled) {
        settled <<- TRUE
        settling <<- TRUE
        settlement_lock <- original_lock(path)
        latest <- job_record_read(path)$record
        latest <- job_transition(latest, "completed", "worker completed")
        job_record_write(path, latest, settlement_lock)
        try(
          job_control_write(path, latest, "acknowledged", "worker completed"),
          silent = TRUE
        )
        original_unlock(settlement_lock)
        settling <<- FALSE
        abort_deputy(
          "The simulated worker left the execution lock busy.",
          class = "approval_error",
          reason = "busy"
        )
      }
      original_lock(lock_path)
    },
    .package = "deputy"
  )

  requested <- job_cancel(
    path,
    authorize = job_test_receipt,
    reason = "user_cancelled"
  )
  restored <- job_read(path)
  expect_true(settled)
  expect_identical(requested$status, "completed")
  expect_identical(requested$control$status, "acknowledged")
  expect_true(requested$control$requested)
  expect_identical(requested$control, restored$control)
})

test_that("abandoned cancellation reports busy acknowledgement and can retry", {
  directory <- withr::local_tempdir(pattern = "deputy-job-recovery-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  record <- job_record_read(path)$record
  record <- job_transition(record, "running", "worker started")
  record$cleanup <- list(
    owner = "binder",
    required = FALSE,
    status = "attached",
    attempts = 0L
  )
  lock <- approval_store_lock(path)
  on.exit(approval_store_unlock(lock), add = TRUE)
  job_record_write(path, record, lock)
  approval_store_unlock(lock)
  lock <- NULL

  original_lock <- approval_store_lock
  control_path <- job_control_path(path, record)
  control_attempts <- 0L
  block_acknowledgement <- TRUE
  local_mocked_bindings(approval_store_lock = function(lock_path, ...) {
    if (identical(lock_path, control_path)) {
      control_attempts <<- control_attempts + 1L
      if (block_acknowledgement && control_attempts > 1L) {
        rlang::abort("control is busy", reason = "busy")
      }
    }
    original_lock(lock_path, ...)
  })
  expect_error(
    job_cancel(path, authorize = job_test_receipt),
    class = "deputy_job_busy"
  )
  pending <- job_read(path)
  expect_identical(pending$status, "indeterminate")
  expect_identical(pending$control$status, "requested")
  block_acknowledgement <- FALSE

  recovered <- job_cancel(
    path,
    authorize = job_test_receipt,
    reason = "worker abandoned"
  )

  expect_identical(recovered$status, "indeterminate")
  expect_identical(recovered$cleanup$status, "unknown")
  expect_true(recovered$cleanup$required)
  expect_identical(recovered$reservations$status, "preserved")
  expect_false(recovered$reservations$released)
  expect_identical(recovered$control$status, "acknowledged")
  expect_true(recovered$control$requested)
  expect_identical(
    job_run(
      path,
      bind = function(job) stop("an indeterminate job must not rebind"),
      authorize = job_test_receipt
    )$status,
    "indeterminate"
  )
})

test_that("job_run recovers an abandoned running job without rebinding", {
  directory <- withr::local_tempdir(pattern = "deputy-job-run-recovery-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  record <- job_record_read(path)$record
  record <- job_transition(record, "running", "worker started")
  record$cleanup <- list(
    owner = "binder",
    required = FALSE,
    status = "attached",
    attempts = 0L
  )
  lock <- approval_store_lock(path)
  on.exit(approval_store_unlock(lock), add = TRUE)
  job_record_write(path, record, lock)
  approval_store_unlock(lock)
  lock <- NULL

  bound <- 0L
  recovered <- job_run(
    path,
    bind = function(job) {
      bound <<- bound + 1L
      stop("an abandoned running job must not bind")
    },
    authorize = job_test_receipt
  )

  expect_identical(recovered$status, "indeterminate")
  expect_identical(recovered$cleanup$status, "unknown")
  expect_true(recovered$cleanup$required)
  expect_identical(recovered$reservations$status, "preserved")
  expect_false(recovered$reservations$released)
  expect_identical(bound, 0L)
})

test_that("queued cancellation is durable and prevents binding", {
  directory <- withr::local_tempdir(pattern = "deputy-job-cancel-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )

  cancelled <- job_cancel(
    path,
    authorize = job_test_receipt,
    reason = "host stop"
  )
  expect_identical(cancelled$status, "cancelled")
  expect_identical(cancelled$reservations$status, "released")
  expect_identical(cancelled$control$status, "cancelled")
  expect_identical(
    job_run(
      path,
      bind = function(job) stop("cancelled work must not bind"),
      authorize = job_test_receipt
    )$status,
    "cancelled"
  )
})
