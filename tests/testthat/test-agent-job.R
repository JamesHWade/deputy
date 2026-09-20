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

test_that("job strings stay within UTF-8 byte boundaries", {
  one <- "a"
  two <- intToUtf8(0x00e9)
  three <- intToUtf8(0x20ac)
  four <- intToUtf8(0x1f600)

  expect_identical(job_safe_string(one, 0L), "")
  expect_identical(job_safe_string(two, 1L), "")
  expect_identical(job_safe_string(three, 2L), "")
  expect_identical(job_safe_string(four, 3L), "")
  expect_identical(job_safe_string(two, 2L), two)
  expect_identical(job_safe_string(three, 3L), three)
  expect_identical(job_safe_string(four, 4L), four)
})

test_that("error records retain metadata within the serialized bound", {
  two <- intToUtf8(0x00e9)
  three <- intToUtf8(0x20ac)
  four <- intToUtf8(0x1f600)
  error <- structure(
    list(
      message = strrep(two, 10000L),
      reason = strrep(three, 10000L),
      phase = strrep(four, 10000L)
    ),
    class = c("job_test_error", strrep("x", 300L), "condition")
  )

  record <- job_error_record(error)

  expect_named(record, c("class", "message", "reason", "phase"))
  expect_identical(record$class[[1L]], "job_test_error")
  expect_lte(nchar(record$class[[2L]], type = "bytes"), 256L)
  expect_lte(
    nchar(record$message, type = "bytes"),
    job_max_error_bytes / 2L
  )
  expect_lte(nchar(record$reason, type = "bytes"), 1024L)
  expect_lte(nchar(record$phase, type = "bytes"), 1024L)
  expect_lt(nchar(record$message, type = "chars"), 10000L)
  expect_lte(length(serialize(record, NULL, version = 3)), job_max_error_bytes)
})

test_that("large approval evidence retains its bounded resume path", {
  directory <- withr::local_tempdir(pattern = "deputy-job-pending-record-")
  pending_path <- file.path(directory, "approval")
  pending <- ApprovalContinuation(
    id = "approval-1",
    status = "pending",
    request = list(
      tool_call_id = "call-1",
      name = "write",
      tool_input = list(value = "x"),
      reason = "review",
      kind = "tool"
    ),
    source = list(
      path = pending_path,
      prior_evidence = strrep("x", 1024^2 + 1024L)
    )
  )

  record <- job_pending_record(pending)

  expect_identical(record$path, pending_path)
  expect_true("omitted" %in% names(record))
  expect_lte(length(serialize(record, NULL, version = 3)), 1024^2)

  medium <- ApprovalContinuation(
    id = "approval-2",
    status = "pending",
    request = list(
      tool_call_id = "call-2",
      name = "write",
      tool_input = list(value = "y"),
      reason = "review",
      kind = "tool"
    ),
    source = list(
      path = pending_path,
      prior_evidence = strrep("m", 64L * 1024L)
    )
  )
  first_record <- job_pending_record(medium)
  repeated_record <- job_pending_record(first_record)
  expect_identical(repeated_record$path, pending_path)
  expect_identical(
    nchar(repeated_record$source$prior_evidence, type = "bytes"),
    64L * 1024L
  )

  oversized_list <- list(
    source = list(
      path = pending_path,
      prior_evidence = strrep("z", 1024^2 + 1024L)
    )
  )
  oversized_record <- job_pending_record(oversized_list)
  expect_identical(oversized_record$path, pending_path)
  expect_true("omitted" %in% names(oversized_record))
  expect_lte(length(serialize(oversized_record, NULL, version = 3)), 1024^2)
})

test_that("event journals evict oldest entries within the store budget", {
  directory <- withr::local_tempdir(pattern = "deputy-job-event-budget-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "size probe",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L),
    max_bytes = 2500000
  )
  record <- job_record_read(path)$record
  for (index in seq_len(100L)) {
    record <- job_event_append(
      record,
      list(
        type = sprintf("event-%03d", index),
        data = strrep("x", 30000L)
      )
    )
  }
  lock <- approval_store_lock(path)
  on.exit(approval_store_unlock(lock), add = TRUE)
  worker <- new.env(parent = emptyenv())
  worker$path <- path
  worker$lock <- lock
  worker$record <- record
  worker$finished <- FALSE
  local_mocked_bindings(
    job_runtime_snapshot = function(agent, event = NULL) list(),
    .package = "deputy"
  )

  job_worker_checkpoint(
    worker,
    agent,
    list(type = "event-101", data = strrep("x", 30000L))
  )

  persisted <- job_record_read(path)$record
  expect_gt(worker$record$event_dropped, 0L)
  expect_identical(worker$record$events, persisted$events)
  expect_identical(worker$record$event_dropped, persisted$event_dropped)
  expect_identical(
    tail(worker$record$events, 1L)[[1L]]$type,
    "event-101"
  )
  dropped <- worker$record$event_dropped

  job_worker_finish(worker, "failed", error = simpleError("terminal"))
  terminal <- job_record_read(path)$record
  expect_identical(terminal$status, "failed")
  expect_identical(terminal$events, persisted$events)
  expect_identical(terminal$event_dropped, dropped)
  expect_identical(
    tail(terminal$events, 1L)[[1L]]$type,
    "event-101"
  )
})

test_that("non-size store errors are not retried or trimmed", {
  directory <- withr::local_tempdir(pattern = "deputy-job-event-error-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "size probe",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L),
    max_bytes = 2500000
  )
  record <- job_record_read(path)$record
  record <- job_event_append(
    record,
    list(type = "event-001", data = strrep("x", 30000L))
  )
  lock <- approval_store_lock(path)
  on.exit(approval_store_unlock(lock), add = TRUE)
  attempts <- 0L
  local_mocked_bindings(
    approval_store_write = function(
      path,
      record,
      lock,
      max_bytes,
      reserve_bytes = 0
    ) {
      attempts <<- attempts + 1L
      abort_deputy(
        "simulated commit failure",
        class = "approval_error",
        reason = "commit_failed"
      )
    },
    .package = "deputy"
  )

  error <- tryCatch(
    job_record_write(path, record, lock),
    error = identity
  )
  expect_s3_class(error, "deputy_approval_error")
  expect_identical(error$reason, "commit_failed")
  expect_identical(attempts, 1L)
  expect_identical(record$event_dropped, 0L)
  expect_identical(job_record_read(path)$envelope$revision, 1)
  expect_length(job_record_read(path)$record$events, 0L)
})

test_that("non-event size overflow is propagated without changing revision", {
  directory <- withr::local_tempdir(pattern = "deputy-job-record-budget-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "size probe",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L),
    max_bytes = 2500000
  )
  record <- job_record_read(path)$record
  record$manifest$oversized <- strrep("m", 2600000L)
  lock <- approval_store_lock(path)
  on.exit(approval_store_unlock(lock), add = TRUE)

  error <- tryCatch(
    job_record_write(path, record, lock),
    error = identity
  )
  expect_s3_class(error, "deputy_approval_error")
  expect_identical(error$reason, "size_limit")
  expect_identical(job_record_read(path)$envelope$revision, 1)
  expect_length(job_record_read(path)$record$events, 0L)
})

test_that("over-capacity snapshots preserve committed worker evidence", {
  accepted_payloads <- lapply(seq_len(5L), function(index) {
    strrep(intToUtf8(96L + index), 900L * 1024L)
  })
  payloads <- lapply(seq_len(5L), function(index) {
    strrep(intToUtf8(64L + index), 2600L * 1024L)
  })
  make_snapshot <- function(agent, payloads, usage = NULL) {
    snapshot <- list(
      effects = lapply(seq_along(payloads), function(index) {
        list(
          agent_id = agent$agent_id,
          run_id = sprintf("run-%d", index),
          tool_call_id = sprintf("call-%d", index),
          request = list(name = "write", arguments = list(index = index)),
          signature = sprintf("signature-%d", index),
          executed = TRUE,
          status = "completed",
          result = list(payload = payloads[[index]])
        )
      })
    )
    if (!is.null(usage)) {
      snapshot$usage <- usage
    }
    snapshot
  }
  make_worker <- function(path) {
    record <- job_record_read(path)$record
    record <- job_transition(record, "running", "worker started")
    lock <- approval_store_lock(path)
    record <- tryCatch(
      job_record_write(path, record, lock),
      finally = approval_store_unlock(lock)
    )
    lock <- approval_store_lock(path)
    worker <- new.env(parent = emptyenv())
    worker$path <- path
    worker$lock <- lock
    worker$record <- record
    worker$finished <- FALSE
    worker$terminal <- NULL
    worker$detach <- NULL
    worker$cleanup <- NULL
    worker$cleanup_called <- FALSE
    worker$persistence_error <- NULL
    worker
  }
  directory <- withr::local_tempdir(pattern = "deputy-job-snapshot-budget-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "large snapshot",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L),
    max_bytes = 50 * 1024^2
  )
  snapshot_state <- new.env(parent = emptyenv())
  snapshot_state$current <- make_snapshot(
    agent,
    accepted_payloads,
    usage = S7::props(AgentUsage(requests = 1L))
  )
  local_mocked_bindings(
    job_runtime_snapshot = function(agent, event = NULL) {
      snapshot_state$current
    },
    .package = "deputy"
  )
  worker <- make_worker(path)
  on.exit(
    if (!is.null(worker$lock)) approval_store_unlock(worker$lock),
    add = TRUE
  )
  job_worker_checkpoint(worker, agent, list(type = "accepted-effects"))
  accepted <- job_read(path)
  expect_identical(
    lapply(accepted$runtime$effects, function(effect) {
      effect$result$payload
    }),
    accepted_payloads
  )
  snapshot_state$current <- make_snapshot(
    agent,
    payloads,
    usage = S7::props(AgentUsage(requests = 2L))
  )
  expect_error(
    job_worker_checkpoint(worker, agent, list(type = "large-effects")),
    class = "deputy_job_persistence"
  )

  persisted <- job_record_read(path)
  expect_true(!is.null(worker$persistence_error))
  expect_identical(worker$record, persisted$record)
  expect_equal(persisted$record$usage$requests, 1L)
  expect_identical(
    lapply(persisted$record$effects, function(effect) effect$result$payload),
    accepted_payloads
  )
  expect_identical(
    persisted$record$runtime$effects,
    persisted$record$effects
  )
  expect_identical(persisted$envelope$revision, 3)

  expect_no_error(
    job_worker_finish(
      worker,
      "indeterminate",
      error = worker$persistence_error,
      reason = "snapshot persistence failed"
    )
  )
  settled <- job_read(path)
  expect_identical(worker$record, job_record_read(path)$record)
  expect_identical(settled$status, "indeterminate")
  expect_identical(settled$reservations$status, "preserved")
  expect_false(settled$reservations$released)
  expect_equal(settled$usage$requests, 1L)
  expect_identical(
    settled$runtime$effects,
    job_record_read(path)$record$effects
  )
})

test_that("near-capacity active jobs settle bounded result and cleanup", {
  directory <- withr::local_tempdir(pattern = "deputy-job-near-capacity-")
  agent <- job_test_agent()
  path <- job_create(
    directory,
    agent,
    "near capacity",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L),
    max_bytes = 8 * 1024^2
  )
  record <- job_record_read(path)$record
  record <- job_transition(record, "running", "worker started")
  lock <- approval_store_lock(path)
  record <- tryCatch(
    job_record_write(path, record, lock),
    finally = approval_store_unlock(lock)
  )
  lock <- approval_store_lock(path)
  worker <- new.env(parent = emptyenv())
  worker$path <- path
  worker$lock <- lock
  worker$record <- record
  worker$finished <- FALSE
  worker$terminal <- NULL
  worker$detach <- NULL
  worker$cleanup <- NULL
  worker$cleanup_called <- FALSE
  worker$persistence_error <- NULL
  payload <- strrep("x", 1400L * 1024L)
  snapshot <- list(
    effects = list(
      list(
        agent_id = agent$agent_id,
        run_id = "near-run",
        tool_call_id = "near-call",
        request = list(name = "write", arguments = list()),
        signature = "near-signature",
        executed = TRUE,
        status = "completed",
        result = list(payload = payload)
      )
    )
  )
  local_mocked_bindings(
    job_runtime_snapshot = function(agent, event = NULL) snapshot,
    .package = "deputy"
  )
  on.exit(approval_store_unlock(lock), add = TRUE)
  expect_no_error(
    job_worker_checkpoint(worker, agent, list(type = "near-effects"))
  )
  expect_identical(job_read(path)$runtime$effects[[1L]]$result$payload, payload)

  worker$record$cleanup <- list(
    owner = "binder",
    required = TRUE,
    status = "attached",
    attempts = 0L
  )
  cleanups <- 0L
  worker$cleanup <- function() cleanups <<- cleanups + 1L
  expect_no_error(job_worker_cleanup(worker))
  expect_identical(cleanups, 1L)
  expect_identical(job_read(path)$cleanup$status, "completed")
  expect_false(job_read(path)$cleanup$required)

  expect_no_error(
    job_worker_finish(
      worker,
      "failed",
      result = AgentResult(response = strrep("r", 900L * 1024L)),
      error = simpleError(strrep("e", 4096L)),
      reason = "bounded settlement"
    )
  )
  settled <- job_read(path)
  expect_identical(settled$status, "failed")
  expect_equal(nchar(settled$result$response, type = "bytes"), 900L * 1024L)
  expect_true(!is.null(settled$error))
  expect_identical(settled$cleanup$status, "completed")
  expect_false(settled$cleanup$required)
  expect_identical(settled$reservations$status, "released")
  expect_true(settled$reservations$released)
})

test_that("job admission rejects a store without settlement reserve", {
  directory <- withr::local_tempdir(pattern = "deputy-job-tiny-store-")
  error <- tryCatch(
    job_create(
      directory,
      job_test_agent(),
      "tiny store",
      "owner-1",
      "definition-1",
      "context-1",
      UsageLimits(max_requests = 1L),
      max_bytes = 2 * 1024^2
    ),
    error = identity
  )
  expect_s3_class(error, "deputy_approval_error")
  expect_identical(error$reason, "size_limit")
  expect_length(list.dirs(directory, recursive = FALSE), 0L)
})

test_that("job_run retains committed evidence after swallowed checkpoint failure", {
  directory <- withr::local_tempdir(pattern = "deputy-job-run-persistence-")
  holder <- new.env(parent = emptyenv())
  holder$callback <- NULL
  holder$snapshot_calls <- 0L
  holder$swallowed <- FALSE
  make_effect <- function(payload, index = 1L) {
    list(
      agent_id = "job-agent",
      run_id = "run-1",
      tool_call_id = sprintf("call-%d", index),
      request = list(name = "write", arguments = list(index = index)),
      signature = sprintf("signature-%d", index),
      executed = TRUE,
      status = "executing",
      result = NULL,
      payload = payload
    )
  }
  saved_snapshot <- list(
    effects = list(make_effect("saved")),
    usage = S7::props(AgentUsage(requests = 1L))
  )
  oversized_snapshot <- list(
    effects = lapply(seq_len(5L), function(index) {
      make_effect(
        strrep(intToUtf8(64L + index), 2600L * 1024L),
        index
      )
    }),
    usage = S7::props(AgentUsage(requests = 2L))
  )
  local_snapshot <- list(
    effects = list(make_effect("local")),
    usage = S7::props(AgentUsage(requests = 3L))
  )
  swallowed_agent_class <- R6::R6Class(
    "JobSwallowedCheckpointAgent",
    inherit = Agent,
    public = list(
      run_sync = function(...) {
        holder$callback(self, list(type = "saved"))
        tryCatch(
          holder$callback(self, list(type = "oversized")),
          deputy_job_persistence = function(error) {
            holder$swallowed <- TRUE
          }
        )
        expect_identical(holder$swallowed, TRUE)
        AgentResult(response = "local result")
      }
    )
  )
  agent <- swallowed_agent_class$new(
    chat = create_mock_chat(responses = list("unused"))
  )
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 3L),
    max_bytes = 50 * 1024^2
  )
  local_mocked_bindings(
    job_attach_runtime = function(agent, checkpoint, record = NULL) {
      holder$callback <- checkpoint
      function() invisible(NULL)
    },
    job_runtime_snapshot = function(agent, event = NULL) {
      holder$snapshot_calls <- holder$snapshot_calls + 1L
      switch(
        as.character(holder$snapshot_calls),
        `1` = saved_snapshot,
        `2` = oversized_snapshot,
        local_snapshot
      )
    },
    .package = "deputy"
  )

  settled <- job_run(
    path,
    bind = function(job) agent,
    authorize = job_test_receipt
  )
  persisted <- job_read(path)

  expect_true(holder$swallowed)
  expect_identical(holder$snapshot_calls, 2L)
  expect_identical(settled$status, "indeterminate")
  expect_identical(persisted$status, settled$status)
  expect_identical(settled$result$response, "local result")
  expect_identical(
    settled$runtime$effects[[1L]]$payload,
    "saved"
  )
  expect_false(any(vapply(
    settled$runtime$effects,
    function(effect) identical(effect$payload, "local"),
    logical(1)
  )))
  expect_identical(persisted$runtime$effects, settled$runtime$effects)
  expect_identical(settled$reservations$status, "preserved")
  expect_false(settled$reservations$released)
  expect_identical(settled$cleanup$owner, "host")
  expect_identical(settled$cleanup$status, "not_required")
  expect_false(settled$cleanup$required)

  recovered <- job_run(
    path,
    bind = function(job) stop("an indeterminate job must not bind again"),
    authorize = job_test_receipt
  )
  expect_identical(recovered$cleanup, settled$cleanup)
})

test_that("checkpoint cancellation settles executing effects as indeterminate", {
  directory <- withr::local_tempdir(pattern = "deputy-job-checkpoint-effect-")
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
  on.exit(approval_store_unlock(lock), add = TRUE)
  record <- job_record_write(path, record, lock)
  job_control_write(path, record, "requested", "host stop")
  worker <- new.env(parent = emptyenv())
  worker$path <- path
  worker$lock <- lock
  worker$record <- record
  worker$finished <- FALSE
  snapshot <- list(
    effects = list(
      list(
        agent_id = agent$agent_id,
        run_id = "run-1",
        tool_call_id = "call-1",
        request = list(name = "write", arguments = list()),
        signature = "signature",
        executed = TRUE,
        status = "executing",
        result = NULL
      )
    ),
    pending_approval = NULL
  )
  local_mocked_bindings(
    job_runtime_snapshot = function(agent, event = NULL) snapshot,
    .package = "deputy"
  )

  expect_error(
    job_worker_checkpoint(worker, agent),
    class = "deputy_job_cancelled"
  )

  persisted <- job_read(path)
  expect_identical(worker$record$status, "indeterminate")
  expect_identical(persisted$status, worker$record$status)
  expect_identical(persisted$runtime$effects, worker$record$runtime$effects)
  expect_identical(persisted$runtime$effects[[1L]]$status, "executing")
  expect_identical(worker$record$reservations$status, "preserved")
  expect_false(worker$record$reservations$released)
  expect_identical(persisted$reservations, worker$record$reservations)
  expect_identical(persisted$control$status, "acknowledged")
  expect_true(persisted$control$requested)
})

test_that("checkpoint cancellation clears a pending approval snapshot", {
  directory <- withr::local_tempdir(pattern = "deputy-job-checkpoint-approval-")
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
  on.exit(approval_store_unlock(lock), add = TRUE)
  record <- job_record_write(path, record, lock)
  job_control_write(path, record, "requested", "host stop")
  worker <- new.env(parent = emptyenv())
  worker$path <- path
  worker$lock <- lock
  worker$record <- record
  worker$finished <- FALSE
  pending_path <- file.path(directory, "pending-approval")
  snapshot <- list(pending_approval = pending_path)
  local_mocked_bindings(
    job_runtime_snapshot = function(agent, event = NULL) snapshot,
    .package = "deputy"
  )

  expect_error(
    job_worker_checkpoint(worker, agent),
    class = "deputy_job_cancelled"
  )

  persisted <- job_read(path)
  expect_identical(worker$record$status, "cancelled")
  expect_identical(persisted$status, worker$record$status)
  expect_identical(persisted$runtime$pending_approval, pending_path)
  expect_null(worker$record$pending_approval)
  expect_null(persisted$pending_approval)
  expect_identical(persisted$control$status, "cancelled")
  expect_true(persisted$control$requested)
  expect_identical(persisted$reservations, worker$record$reservations)
  expect_true(persisted$reservations$released)
})

test_that("full job_run clears pending approval after checkpoint cancellation", {
  directory <- withr::local_tempdir(pattern = "deputy-job-run-approval-cancel-")
  pending_path <- file.path(directory, "approval")
  checkpoint_holder <- new.env(parent = emptyenv())
  checkpoint_holder$callback <- NULL
  checkpoint_holder$called <- FALSE
  cancellable_agent_class <- R6::R6Class(
    "JobCheckpointCancellationAgent",
    inherit = Agent,
    public = list(
      run_sync = function(...) {
        checkpoint_holder$called <- TRUE
        record <- job_record_read(path)$record
        job_control_write(path, record, "requested", "checkpoint stop")
        checkpoint_holder$callback(self, NULL)
      }
    )
  )
  agent <- cancellable_agent_class$new(
    chat = create_mock_chat(responses = list("unused"))
  )
  path <- job_create(
    directory,
    agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  local_mocked_bindings(
    job_attach_runtime = function(agent, checkpoint, record = NULL) {
      checkpoint_holder$callback <- checkpoint
      function() invisible(NULL)
    },
    job_runtime_snapshot = function(agent, event = NULL) {
      list(pending_approval = pending_path)
    },
    .package = "deputy"
  )

  cancelled <- job_run(
    path,
    bind = function(job) agent,
    authorize = job_test_receipt
  )
  persisted <- job_read(path)

  expect_true(checkpoint_holder$called)
  expect_identical(cancelled$status, "cancelled")
  expect_null(cancelled$pending_approval)
  expect_identical(cancelled$runtime$pending_approval, pending_path)
  expect_identical(persisted$status, "cancelled")
  expect_null(persisted$pending_approval)
  expect_identical(persisted$runtime$pending_approval, pending_path)
  expect_identical(persisted$control$status, "cancelled")
  expect_true(persisted$control$requested)
})

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

test_that("job_create rejects an Agent with an outstanding approval", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "effect", arguments = list(value = "b")),
    runtime_reply(text = "finished")
  ))
  directory <- withr::local_tempdir(pattern = "deputy-job-pending-admission-")
  approvals <- file.path(directory, "approvals")
  jobs <- file.path(directory, "jobs")
  dir.create(approvals)
  effects <- new.env(parent = emptyenv())
  effects$values <- character()
  agent <- Agent$new(
    chat = runtime_chat(server),
    tools = list(ellmer::tool(
      function(value) {
        effects$values <- c(effects$values, value)
        value
      },
      name = "effect",
      description = "Record an observable effect",
      arguments = list(value = ellmer::type_string()),
      convert = FALSE
    )),
    permissions = Permissions(can_use_tool = function(...) {
      PermissionResultPending("Review this operation")
    }),
    approval_dir = approvals,
    working_dir = directory,
    agent_id = "pending-admission-agent",
    session_id = "pending-admission-session"
  )

  first <- agent$run_sync("Perform the operation")
  pending_path <- agent$pending_approval()$source$path
  expect_identical(first$stop_reason, "approval_pending")
  expect_identical(approval_read(pending_path)$status, "pending")

  error <- tryCatch(
    job_create(
      directory = jobs,
      agent = agent,
      task = "resume the operation",
      owner_id = "owner-1",
      definition_revision = "definition-1",
      context_revision = "context-1",
      usage_limits = UsageLimits(max_requests = 2L)
    ),
    error = identity
  )
  expect_s3_class(error, "deputy_job_invalid")
  expect_true(dir.exists(jobs))
  expect_length(list.dirs(jobs, recursive = FALSE), 0L)
  expect_identical(approval_read(pending_path)$status, "pending")

  denied <- agent$resume_approval(pending_path, "deny")
  expect_identical(trimws(denied$response), "finished")
  expect_identical(approval_read(pending_path)$status, "completed")
  expect_false(approval_read(pending_path)$effects$call_fixture$executed)
  expect_identical(effects$values, character())
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
  expect_false(first$cleanup$required)
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
  expect_true(failed$cleanup$required)
  expect_match(failed$cleanup$error$message, "cleanup failed")
})

test_that("cleanup ledger failures settle every worker mode", {
  directory <- withr::local_tempdir(pattern = "deputy-job-cleanup-ledger-")
  original_record_write <- job_record_write
  original_attach_runtime <- job_attach_runtime
  original_runtime_snapshot <- job_runtime_snapshot
  failure <- new.env(parent = emptyenv())
  failure$active <- FALSE
  failure$failed <- FALSE
  failure$stage <- NULL
  runtime <- new.env(parent = emptyenv())
  runtime$mode <- NULL
  runtime$callback <- NULL
  local_mocked_bindings(
    job_record_write = function(path, record, lock, settling = FALSE) {
      if (
        isTRUE(failure$active) &&
          !isTRUE(failure$failed) &&
          isTRUE(settling) &&
          identical(record$cleanup$status, failure$stage)
      ) {
        failure$failed <- TRUE
        abort_deputy(
          "simulated cleanup ledger failure",
          class = "approval_error",
          reason = "cleanup_write"
        )
      }
      original_record_write(path, record, lock, settling = settling)
    },
    job_attach_runtime = function(agent, checkpoint, record = NULL) {
      if (identical(runtime$mode, "checkpointcancellation")) {
        runtime$callback <- checkpoint
        return(function() invisible(NULL))
      }
      original_attach_runtime(agent, checkpoint, record = record)
    },
    job_runtime_snapshot = function(agent, event = NULL) {
      if (identical(runtime$mode, "checkpointcancellation")) {
        return(list())
      }
      original_runtime_snapshot(agent, event = event)
    },
    .package = "deputy"
  )

  modes <- c(
    "success",
    "runerror",
    "bindfailure",
    "checkpointcancellation"
  )
  for (mode in modes) {
    for (with_cleanup in c(TRUE, FALSE)) {
      if (identical(mode, "bindfailure") && !with_cleanup) {
        next
      }
      stages <- if (with_cleanup) c("running", "completed") else "not_required"
      for (stage in stages) {
        failure$active <- TRUE
        failure$failed <- FALSE
        failure$stage <- stage
        runtime$mode <- mode
        runtime$callback <- NULL
        cleanup_calls <- 0L

        if (identical(mode, "runerror")) {
          mode_class <- R6::R6Class(
            "CleanupLedgerRunErrorAgent",
            inherit = Agent,
            public = list(
              run_sync = function(...) stop("simulated run failure")
            )
          )
          agent <- mode_class$new(
            chat = create_mock_chat(responses = list("unused"))
          )
        } else if (identical(mode, "checkpointcancellation")) {
          mode_class <- R6::R6Class(
            "CleanupLedgerCancellationAgent",
            inherit = Agent,
            public = list(
              run_sync = function(...) {
                record <- job_record_read(path)$record
                job_control_write(
                  path,
                  record,
                  "requested",
                  "checkpoint stop"
                )
                runtime$callback(self, NULL)
              }
            )
          )
          agent <- mode_class$new(
            chat = create_mock_chat(responses = list("unused"))
          )
        } else {
          agent <- job_test_agent()
        }
        path <- job_create(
          directory,
          agent,
          "answer once",
          "owner-1",
          "definition-1",
          "context-1",
          UsageLimits(max_requests = 2L)
        )
        wrong_agent <- if (identical(mode, "bindfailure")) {
          job_test_agent()
        } else {
          NULL
        }
        bind <- if (identical(mode, "bindfailure")) {
          function(job) {
            list(
              agent = wrong_agent,
              cleanup = function() {
                cleanup_calls <<- cleanup_calls + 1L
              }
            )
          }
        } else if (with_cleanup) {
          function(job) {
            list(
              agent = agent,
              cleanup = function() {
                cleanup_calls <<- cleanup_calls + 1L
              }
            )
          }
        } else {
          function(job) agent
        }

        settled <- job_run(
          path,
          bind = bind,
          authorize = job_test_receipt
        )
        persisted <- job_read(path)

        expect_true(
          failure$failed,
          info = sprintf(
            "mode=%s cleanup=%s stage=%s",
            mode,
            with_cleanup,
            stage
          )
        )
        expect_identical(settled$status, "indeterminate")
        expect_identical(persisted$status, "indeterminate")
        expect_identical(settled$reservations$status, "preserved")
        expect_false(settled$reservations$released)
        expect_identical(persisted$reservations, settled$reservations)
        expect_true("deputy_job_persistence" %in% settled$error$class)
        if (identical(mode, "success")) {
          expect_identical(settled$result$response, "done")
        } else {
          expect_null(settled$result)
        }
        if (with_cleanup) {
          expect_identical(cleanup_calls, 1L)
          expect_identical(settled$cleanup$owner, "binder")
          expect_identical(settled$cleanup$status, "completed")
          expect_false(settled$cleanup$required)
        } else {
          expect_identical(cleanup_calls, 0L)
          expect_identical(settled$cleanup$owner, "host")
          expect_identical(settled$cleanup$status, "not_required")
          expect_false(settled$cleanup$required)
        }
        expect_identical(persisted$cleanup, settled$cleanup)
        if (identical(mode, "checkpointcancellation")) {
          expect_identical(settled$control$status, "acknowledged")
          expect_true(settled$control$requested)
        }
        failure$active <- FALSE
      }
    }
  }
})

test_that("failed cleanup makes an approval pending run terminal", {
  directory <- withr::local_tempdir(pattern = "deputy-job-pending-cleanup-")
  pending_agent_class <- R6::R6Class(
    "PendingCleanupAgent",
    inherit = Agent,
    public = list(
      pending_path = NULL,
      run_sync = function(...) {
        approval_abort(
          "approval required",
          class = "approval_pending",
          path = self$pending_path
        )
      },
      pending_approval = function() list(path = self$pending_path)
    )
  )
  for (fails in c(FALSE, TRUE)) {
    pending_path <- file.path(
      directory,
      if (fails) "pending-failed" else "pending-success"
    )
    pending_agent <- pending_agent_class$new(
      chat = create_mock_chat(responses = list("unused"))
    )
    pending_agent$pending_path <- pending_path
    path <- job_create(
      directory,
      pending_agent,
      "answer once",
      "owner-1",
      "definition-1",
      "context-1",
      UsageLimits(max_requests = 2L)
    )
    bound <- 0L
    cleanups <- 0L
    first <- job_run(
      path,
      bind = function(job) {
        bound <<- bound + 1L
        list(
          agent = pending_agent,
          cleanup = function() {
            cleanups <<- cleanups + 1L
            if (fails) stop("cleanup failed")
          }
        )
      },
      authorize = job_test_receipt
    )

    expect_identical(cleanups, 1L)
    expect_identical(bound, 1L)
    if (fails) {
      expect_identical(first$status, "failed")
      expect_identical(first$cleanup$status, "failed")
      expect_true(first$cleanup$required)
      expect_null(first$pending_approval)
      expect_identical(first$runtime$pending_approval, pending_path)
      second <- job_run(
        path,
        bind = function(job) stop("failed cleanup must not rebind"),
        authorize = job_test_receipt
      )
      expect_identical(second$status, "failed")
      expect_identical(bound, 1L)
    } else {
      expect_identical(first$status, "approval_pending")
      expect_identical(first$cleanup$status, "completed")
      expect_false(first$cleanup$required)
      expect_identical(first$runtime$pending_approval, pending_path)
    }
  }
})

test_that("prebind cleanup is unknown for fresh and resumed jobs", {
  directory <- withr::local_tempdir(pattern = "deputy-job-prebind-cleanup-")
  pending_agent_class <- R6::R6Class(
    "PrebindCleanupAgent",
    inherit = Agent,
    public = list(
      pending_path = NULL,
      run_sync = function(...) {
        approval_abort(
          "approval required",
          class = "approval_pending",
          path = self$pending_path
        )
      },
      pending_approval = function() list(path = self$pending_path)
    )
  )
  pending_agent <- pending_agent_class$new(
    chat = create_mock_chat(responses = list("unused"))
  )
  pending_agent$pending_path <- file.path(directory, "approval")
  path <- job_create(
    directory,
    pending_agent,
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )

  first_seen <- NULL
  first <- job_run(
    path,
    bind = function(job) {
      first_seen <<- job
      list(
        agent = pending_agent,
        cleanup = function() invisible(NULL)
      )
    },
    authorize = job_test_receipt
  )

  expect_identical(first$status, "approval_pending")
  expect_identical(first$cleanup$status, "completed")
  expect_false(first$cleanup$required)
  expect_identical(first_seen$cleanup$owner, "unknown")
  expect_identical(first_seen$cleanup$status, "unknown")
  expect_true(first_seen$cleanup$required)
  expect_null(first_seen$runtime$detached_at)
  expect_null(first_seen$runtime$detach_error)

  second_seen <- NULL
  second <- job_run(
    path,
    bind = function(job) {
      second_seen <<- job
      stop("inspect the resumed bind record")
    },
    authorize = job_test_receipt,
    decision = "approve"
  )

  expect_identical(second$status, "failed")
  expect_identical(second_seen$cleanup$owner, "unknown")
  expect_identical(second_seen$cleanup$status, "unknown")
  expect_true(second_seen$cleanup$required)
  expect_null(second_seen$runtime$detached_at)
  expect_null(second_seen$runtime$detach_error)
})

test_that("fresh approval resume preserves exhausted usage and can deny", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "effect", arguments = list(value = "b"))
  ))
  directory <- withr::local_tempdir(pattern = "deputy-job-budget-resume-")
  approvals <- file.path(directory, "approvals")
  dir.create(approvals)
  effects <- new.env(parent = emptyenv())
  effects$values <- character()
  make_agent <- function() {
    Agent$new(
      chat = runtime_chat(server),
      tools = list(ellmer::tool(
        function(value) {
          effects$values <- c(effects$values, value)
          value
        },
        name = "effect",
        description = "effect",
        arguments = list(value = ellmer::type_string()),
        convert = FALSE
      )),
      permissions = Permissions(can_use_tool = function(...) {
        PermissionResultPending("Review this operation")
      }),
      approval_dir = approvals,
      working_dir = directory,
      agent_id = "a",
      session_id = "s"
    )
  }
  agent <- make_agent()
  path <- job_create(
    directory,
    agent,
    "task",
    "owner",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 1L)
  )

  first <- job_run(
    path,
    bind = function(job) agent,
    authorize = job_test_receipt
  )
  approval_path <- first$pending_approval$path
  expect_identical(first$status, "approval_pending")
  expect_equal(first$usage$requests, 1)
  expect_identical(effects$values, character())

  approved <- job_run(
    path,
    bind = function(job) make_agent(),
    authorize = job_test_receipt,
    decision = "approve"
  )
  expect_identical(approved$status, "approval_pending")
  expect_equal(approved$usage$requests, 1)
  expect_identical(approved$pending_approval$path, approval_path)
  expect_identical(approval_read(approval_path)$status, "pending")
  expect_identical(effects$values, character())

  denied <- job_run(
    path,
    bind = function(job) make_agent(),
    authorize = job_test_receipt,
    decision = "deny"
  )
  expect_identical(denied$status, "completed")
  expect_equal(denied$usage$requests, 1)
  expect_null(denied$pending_approval)
  expect_identical(approval_read(approval_path)$status, "stopped")
  expect_identical(effects$values, character())
})

test_that("a failing approval continuation binder clears pending approval", {
  directory <- withr::local_tempdir(pattern = "deputy-job-pending-bind-")
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
  pending_path <- file.path(directory, "approval")
  record <- job_record_read(path)$record
  record <- job_transition(record, "running", "worker started")
  record <- job_transition(record, "approval_pending", "approval requested")
  record$pending_approval <- list(path = pending_path)
  record$runtime$pending_approval <- pending_path
  lock <- approval_store_lock(path)
  tryCatch(
    job_record_write(path, record, lock),
    finally = approval_store_unlock(lock)
  )

  bound <- 0L
  failed <- job_run(
    path,
    bind = function(job) {
      bound <<- bound + 1L
      stop("binder failed while resuming approval")
    },
    authorize = job_test_receipt,
    decision = "approve"
  )

  expect_identical(bound, 1L)
  expect_identical(failed$status, "failed")
  expect_null(failed$pending_approval)
  expect_null(job_read(path)$pending_approval)
  expect_identical(job_read(path)$runtime$pending_approval, pending_path)

  terminal <- job_run(
    path,
    bind = function(job) {
      bound <<- bound + 1L
      stop("a failed continuation must not bind again")
    },
    authorize = job_test_receipt
  )
  expect_identical(terminal$status, "failed")
  expect_identical(bound, 1L)
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
  expect_false(persisted$cleanup$required)
  expect_identical(persisted$cleanup$attempts, 1L)
  recovered <- job_run(
    path,
    bind = function(job) stop("interrupted jobs must not bind again"),
    authorize = job_test_receipt
  )
  expect_identical(recovered$status, "indeterminate")
  expect_identical(recovered$cleanup, persisted$cleanup)
})

test_that("failed detach keeps attachment uncertainty with successful cleanup", {
  directory <- withr::local_tempdir(pattern = "deputy-job-detach-failure-")
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
  record$runtime$attached <- TRUE
  lock <- approval_store_lock(path)
  on.exit(approval_store_unlock(lock), add = TRUE)
  job_record_write(path, record, lock)
  cleanups <- 0L
  worker <- new.env(parent = emptyenv())
  worker$path <- path
  worker$lock <- lock
  worker$record <- record
  worker$detach <- function() stop("detach failed")
  worker$cleanup <- function() cleanups <<- cleanups + 1L
  worker$cleanup_called <- FALSE

  detach_error <- job_worker_cleanup(worker)
  persisted <- job_read(path)

  expect_match(conditionMessage(detach_error), "detach failed")
  expect_identical(cleanups, 1L)
  expect_true(worker$record$runtime$attached)
  expect_null(worker$record$runtime$detached_at)
  expect_identical(worker$record$cleanup$status, "unknown")
  expect_true(worker$record$cleanup$required)
  expect_true(persisted$runtime$attached)
  expect_null(persisted$runtime$detached_at)
  expect_identical(persisted$cleanup$status, "unknown")
  expect_true(persisted$cleanup$required)
  expect_match(persisted$runtime$detach_error$message, "detach failed")
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

test_that("recovery preserves terminal cleanup evidence", {
  directory <- withr::local_tempdir(pattern = "deputy-job-cleanup-recovery-")
  cleanup_states <- list(
    completed = list(
      owner = "binder",
      required = FALSE,
      status = "completed",
      attempts = 1L,
      completed_at = 123,
      error = NULL
    ),
    failed = list(
      owner = "binder",
      required = TRUE,
      status = "failed",
      attempts = 1L,
      completed_at = 123,
      error = list(message = "cleanup failed")
    ),
    host_not_required = list(
      owner = "host",
      required = FALSE,
      status = "not_required",
      attempts = 0L
    )
  )
  for (cleanup_state in cleanup_states) {
    for (recover in c("run", "cancel")) {
      path <- job_create(
        directory,
        job_test_agent(),
        "interrupted task",
        "owner-1",
        "definition-1",
        "context-1",
        UsageLimits(max_requests = 2L)
      )
      record <- job_record_read(path)$record
      record <- job_transition(record, "running", "worker started")
      record$cleanup <- cleanup_state
      lock <- approval_store_lock(path)
      tryCatch(
        job_record_write(path, record, lock),
        finally = approval_store_unlock(lock)
      )
      recovered <- if (recover == "run") {
        job_run(
          path,
          bind = function(job) stop("recovery must not bind"),
          authorize = job_test_receipt
        )
      } else {
        job_cancel(path, authorize = job_test_receipt)
      }
      expect_identical(recovered$status, "indeterminate")
      expect_identical(recovered$cleanup, record$cleanup)
      expect_identical(job_read(path)$cleanup, record$cleanup)
      expect_false(recovered$reservations$released)
    }
  }
})

test_that("pending dispatch settles a committed cancellation without binding", {
  directory <- withr::local_tempdir(pattern = "deputy-job-pending-cancel-")
  path <- job_create(
    directory,
    job_test_agent(),
    "answer once",
    "owner-1",
    "definition-1",
    "context-1",
    UsageLimits(max_requests = 2L)
  )
  record <- job_record_read(path)$record
  record <- job_transition(record, "running", "worker started")
  record <- job_transition(record, "approval_pending", "approval requested")
  record$pending_approval <- list(path = file.path(directory, "approval"))
  lock <- approval_store_lock(path)
  tryCatch(
    job_record_write(path, record, lock),
    finally = approval_store_unlock(lock)
  )
  # Simulate a host stopping after its durable control request, before it can
  # acquire the execution lock and settle the pending job.
  job_control_write(path, record, "requested", "host stopped waiting")
  expect_identical(job_read(path)$status, "approval_pending")
  expect_true(job_read(path)$control$requested)
  bound <- 0L
  cancelled <- job_run(
    path,
    bind = function(job) {
      bound <<- bound + 1L
      stop("cancelled pending work must not bind")
    },
    authorize = job_test_receipt
  )
  expect_identical(bound, 0L)
  expect_identical(cancelled$status, "cancelled")
  expect_null(cancelled$pending_approval)
  expect_identical(cancelled$reservations$status, "released")
  expect_true(cancelled$reservations$released)
  expect_identical(cancelled$control$status, "cancelled")
  expect_true(cancelled$control$requested)
  expect_identical(job_read(path)$status, "cancelled")
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
