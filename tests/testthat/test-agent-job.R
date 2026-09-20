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

  expect_true(S7::S7_inherits(job, AgentJob))
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
        cleanup = function() cleanups <<- cleanups + 1L
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
