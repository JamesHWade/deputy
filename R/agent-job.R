#' @include agent-job-worker.R
NULL

# Public entry points for durable host-owned Agent jobs. Persistence uses
# approval_store_*; record contracts, store helpers, and worker execution live
# in agent-job-record.R, agent-job-store.R, and agent-job-worker.R.

#' Create a background job
#'
#' Saves a task in a new job directory so that [job_run()] can run it later,
#' possibly in another R process. The agent isn't saved: Deputy records its
#' setup (model, system prompt, tools, permissions, conversation and so on),
#' and `job_run()` checks that the agent you rebuild matches it.
#'
#' The agent must be idle and must be a plain [Agent] (not a [LeadAgent]) or
#' the root of a graph from `agent$retain_agent_graph()`. Fallback chats and
#' provider-native tools aren't supported.
#'
#' @param directory Directory to create the job directory in. It is created
#'   if needed.
#' @param agent The [Agent] to describe. `bind` in [job_run()] must rebuild an
#'   agent with the same setup.
#' @param task The task, as one non-empty string.
#' @param owner_id ID of the user or tenant that owns the job.
#' @param definition_revision Your label (a string or number) for the current
#'   version of the agent's configuration. [job_run()] runs the job only if
#'   `authorize` returns the same value.
#' @param context_revision Your label (a string or number) for the current
#'   version of the context the agent works from, checked the same way.
#' @param usage_limits [UsageLimits] for the job.
#' @param associations Optional plain list of your own data to keep with the
#'   job, such as a conversation ID.
#' @param max_bytes Size limit for the job's saved record, in bytes (50 MiB
#'   by default). While the job is active, the record must stay below half
#'   this limit minus about 1.1 MiB, which is kept free for the final result
#'   and cleanup. `job_create()` errors if the first record is too big.
#' @return The path to the new job directory. Keep it to run, read or cancel
#'   the job.
#' @seealso `vignette("background-jobs")`
#' @export
job_create <- function(
  directory,
  agent,
  task,
  owner_id,
  definition_revision,
  context_revision,
  usage_limits,
  associations = list(),
  max_bytes = 50 * 1024^2
) {
  max_bytes <- job_store_call(
    approval_store_limit(max_bytes),
    "The Agent job storage limit is invalid.",
    class = "job_invalid"
  )
  if (
    !is.character(directory) ||
      length(directory) != 1L ||
      is.na(directory) ||
      !nzchar(directory)
  ) {
    job_abort("{.arg directory} must be one non-empty path.")
  }
  if (!dir.exists(directory)) {
    if (!dir.create(directory, recursive = TRUE, mode = "0700")) {
      job_abort("The Agent job directory cannot be created.", "job_invalid")
    }
  }
  directory <- job_store_call(
    approval_store_path(directory),
    "The Agent job directory is invalid.",
    class = "job_invalid"
  )
  task <- job_text(task, "task")
  owner_id <- job_text(owner_id, "owner_id", max_bytes = 4096L)
  definition_revision <- job_revision(
    definition_revision,
    "definition_revision"
  )
  context_revision <- job_revision(context_revision, "context_revision")
  usage_limits <- if (S7::S7_inherits(usage_limits, UsageLimits)) {
    usage_limits
  } else {
    job_abort("{.arg usage_limits} must be a UsageLimits value.")
  }
  associations <- job_plain_list(associations, "associations")
  manifest <- job_store_call(
    job_agent_manifest(agent),
    "The Agent job manifest could not be captured.",
    class = "job_invalid"
  )
  if (!is.list(manifest) || is.object(manifest)) {
    job_abort(
      "The Agent job manifest is not portable.",
      "job_invalid"
    )
  }
  approval_portable(manifest)
  id <- gsub("-", "", new_deputy_id("job_"), fixed = TRUE)
  control_id <- paste0(id, "_control")
  record <- job_initial_record(
    id = id,
    control_id = control_id,
    task = task,
    owner_id = owner_id,
    definition_revision = definition_revision,
    context_revision = context_revision,
    usage_limits = usage_limits,
    associations = associations,
    manifest = manifest
  )
  job_record_validate(record)
  path <- approval_store_create(
    directory,
    record,
    max_bytes = max_bytes,
    reserve_bytes = job_settlement_reserve
  )
  control <- job_control_record(id, control_id)
  committed <- FALSE
  tryCatch(
    {
      approval_store_create(
        path,
        control,
        max_bytes = job_control_limit(max_bytes)
      )
      committed <- TRUE
    },
    error = function(error) {
      unlink(path, recursive = TRUE, force = TRUE)
      job_abort(
        "The Agent job cancellation record could not be committed.",
        class = "job_persistence",
        parent = error
      )
    }
  )
  if (!committed) {
    unlink(path, recursive = TRUE, force = TRUE)
    job_abort("The Agent job was not committed.", "job_persistence")
  }
  path
}

#' Read a background job
#'
#' Returns the job's saved state. It doesn't rebuild the agent, call the model
#' or run tools, so it's safe to use for status displays.
#'
#' @param path Job directory returned by [job_create()].
#' @return An [AgentJob].
#' @export
job_read <- function(path) {
  loaded <- job_record_read(path)
  job_job(
    loaded$path,
    loaded$record,
    loaded$envelope,
    job_control_read(loaded$path, loaded$record, missing_ok = TRUE)
  )
}

#' Run a background job
#'
#' Runs a queued job, or resumes one waiting for approval, in the current R
#' process and returns when the run ends. It calls `authorize` first; a
#' refusal errors and leaves the job untouched. It then calls `bind`; if that
#' fails, or the rebuilt agent doesn't match the setup saved by
#' [job_create()], the job fails. A running job is locked, so a second
#' `job_run()` on it errors.
#'
#' A finished job is returned unchanged, and so is a job waiting for approval
#' unless you pass `decision`. If a previous `job_run()` stopped partway, for
#' example because its process was killed, the job is marked `"indeterminate"`
#' and not run again: a tool may already have had effects, so check what
#' happened before creating new work.
#'
#' @param path Job directory returned by [job_create()].
#' @param bind Function that takes the [AgentJob] and returns the rebuilt
#'   [Agent], or `list(agent = , cleanup = )` where `cleanup` is a function
#'   that `job_run()` calls when it is done with the agent.
#' @param authorize Function that takes the [AgentJob] and returns a list of
#'   your app's current `job_id`, `owner_id`, `definition_revision` and
#'   `context_revision` for it; the job runs only if they match the saved
#'   values. Look them up rather than copying them from the job, and signal an
#'   error to refuse.
#' @param decision `"approve"` or `"deny"`, to resume a job waiting for
#'   approval.
#' @param tool_input Optional edited tool arguments (a named list) to approve
#'   with.
#' @return The updated [AgentJob].
#' @export
job_run <- function(
  path,
  bind,
  authorize,
  decision = NULL,
  tool_input = NULL
) {
  if (!is.function(bind)) {
    job_abort("{.arg bind} must be a function.")
  }
  if (!is.function(authorize)) {
    job_abort("{.arg authorize} must be a function.")
  }
  if (!is.null(decision)) {
    decision <- match.arg(decision, c("approve", "deny"))
  }
  if (!is.null(tool_input)) {
    if (!is.list(tool_input) || is.object(tool_input)) {
      job_abort("{.arg tool_input} must be a plain portable list.")
    }
    approval_portable(tool_input)
  }
  loaded <- job_record_read(path)
  path <- loaded$path
  lock <- approval_store_lock(path)
  on.exit(
    {
      if (!is.null(lock)) approval_store_unlock(lock)
    },
    add = TRUE
  )
  loaded <- job_record_read(path)
  record <- loaded$record
  control <- job_control_read(path, record)

  if (record$status %in% job_terminal_statuses) {
    return(job_job(path, record, loaded$envelope, control))
  }

  # Authorization precedes bind, and the exact identity is re-read under the
  # execution lock so a stale host receipt cannot consume a newer revision.
  job_authorize(path, record, authorize)
  loaded <- job_record_read(path)
  record <- loaded$record
  control <- job_control_read(path, record)
  if (record$status %in% job_terminal_statuses) {
    return(job_job(path, record, loaded$envelope, control))
  }
  if (record$status %in% c("running", "resuming")) {
    record <- job_mark_recovery(
      path,
      record,
      lock,
      "worker recovered after an unfinished execution"
    )
    return(job_snapshot(path, record))
  }
  if (identical(record$status, "queued") && !is.null(decision)) {
    job_abort(
      "An approval decision requires a job in approval_pending status.",
      "job_invalid"
    )
  }
  if (isTRUE(control$requested)) {
    return(job_cancel_unstarted(
      path,
      record,
      lock,
      reason = control$reason %||% "cancelled",
      message = "The host requested cancellation before binding.",
      acknowledge = FALSE
    ))
  }
  if (identical(record$status, "approval_pending") && is.null(decision)) {
    return(job_job(path, record, loaded$envelope, control))
  }

  resuming <- identical(record$status, "approval_pending")
  next_status <- if (resuming) "resuming" else "running"
  record <- job_transition(
    record,
    next_status,
    if (resuming) {
      "authorized approval continuation"
    } else {
      "authorized worker dispatch"
    }
  )
  if (resuming) {
    record$pending_decision <- list(
      decision = decision,
      tool_input = job_safe_value(tool_input, max_bytes = 1024L * 1024L),
      recorded_at = as.numeric(Sys.time())
    )
  }
  # A new bind attempt may acquire resources before returning its callback.
  # Persist uncertainty before calling it, including on approval continuation;
  # the preceding attempt's cleanup evidence must not describe this attempt.
  record$cleanup <- list(
    owner = "unknown",
    required = TRUE,
    status = "unknown",
    attempts = 0L,
    reason = "binding not settled"
  )
  record$runtime$attached <- FALSE
  record$runtime$detached_at <- NULL
  record$runtime$detach_error <- NULL
  record <- job_record_write(path, record, lock)

  worker <- new.env(parent = emptyenv())
  worker$path <- path
  worker$snapshot_limit <- floor(loaded$envelope$max_bytes / 2)
  worker$lock <- lock
  worker$record <- record
  worker$agent <- NULL
  worker$detach <- NULL
  worker$cleanup <- NULL
  worker$cleanup_called <- FALSE
  worker$finished <- FALSE
  worker$terminal <- NULL
  worker$poller_active <- FALSE
  bind_record <- record
  if (resuming) {
    bind_record$status <- "approval_pending"
  }
  checkpoint <- function(agent, event = NULL) {
    job_worker_checkpoint(worker, agent, event)
  }
  on.exit(
    {
      if (!isTRUE(worker$finished)) {
        worker$poller_active <- FALSE
        try(job_worker_cleanup(worker), silent = TRUE)
        worker$finished <- TRUE
      }
    },
    add = TRUE,
    after = FALSE
  )

  bound_error <- job_worker_bind(worker, bind, bind_record, checkpoint)
  if (!is.null(bound_error)) {
    worker$poller_active <- FALSE
    cleanup_error <- tryCatch(
      job_worker_cleanup(worker),
      error = identity
    )
    worker$finished <- TRUE
    if (!is.null(cleanup_error)) {
      bound_error <- cleanup_error
    }
    record <- job_worker_finish(
      worker,
      if (inherits(bound_error, "deputy_job_persistence")) {
        "indeterminate"
      } else {
        "failed"
      },
      error = bound_error,
      reason = "Agent job binding failed"
    )
    return(job_snapshot(path, record))
  }

  outcome <- job_worker_execute(
    worker,
    bind_record,
    resuming,
    decision,
    tool_input
  )
  job_worker_settle(worker, outcome)
}

#' Cancel a background job
#'
#' Records a request to cancel the job. A queued job, or one waiting for
#' approval, is cancelled straight away. A job that is running stops at the
#' next point where its process checks for cancellation, so the job returned
#' here may still be `"running"`. A job left `"running"` by a process that
#' died is marked `"indeterminate"`. Cancelling a finished job does nothing.
#'
#' @param path Job directory returned by [job_create()].
#' @param authorize Function that checks the request, as in [job_run()].
#' @param reason Reason to record, as one string.
#' @return The updated [AgentJob].
#' @export
job_cancel <- function(path, authorize, reason = "cancelled") {
  if (!is.function(authorize)) {
    job_abort("{.arg authorize} must be a function.")
  }
  reason <- job_text(reason, "reason", max_bytes = 4096L)
  loaded <- job_record_read(path)
  path <- loaded$path
  record <- loaded$record
  if (record$status %in% job_terminal_statuses) {
    control <- job_control_read(path, record, missing_ok = TRUE)
    if (identical(control$status, "requested")) {
      # A previous reconciliation may have observed a terminal record while
      # its control store was busy. Only an authorized retry may repair that
      # requested control state; ordinary terminal inspection stays read-only.
      job_authorize(path, record, authorize)
      control <- job_control_acknowledge(
        path,
        record,
        control$reason %||% reason
      )
    }
    return(job_job(path, record, loaded$envelope, control))
  }
  job_authorize(path, record, authorize)
  control_path <- job_control_path(path, record)
  control_lock <- tryCatch(
    approval_store_lock(control_path),
    error = function(error) {
      if (identical(error$reason, "busy")) {
        job_abort(
          "The Agent job cancellation record is already locked.",
          class = "job_busy",
          parent = error
        )
      }
      job_abort(
        "The Agent job cancellation record could not be locked.",
        class = "job_persistence",
        parent = error
      )
    }
  )
  if (is.null(control_lock)) {
    job_abort(
      "The Agent job cancellation record is already locked.",
      class = "job_busy"
    )
  }
  on.exit(approval_store_unlock(control_lock), add = TRUE)
  control <- job_control_read(path, record)
  control$status <- "requested"
  control$requested <- TRUE
  control$reason <- reason
  control$updated_at <- as.numeric(Sys.time())
  job_control_validate(control, record)
  envelope <- approval_store_envelope(control_path)
  approval_store_write(
    control_path,
    control,
    control_lock,
    max_bytes = envelope$max_bytes
  )
  # Never hold the independent control lock while acquiring or inspecting the
  # execution lock. A worker settles its terminal record while holding the
  # execution lock and then needs this control lock to acknowledge a request.
  approval_store_unlock(control_lock)
  control_lock <- NULL

  execution_lock <- tryCatch(
    approval_store_lock(path),
    error = function(error) {
      if (identical(error$reason, "busy")) {
        return(NULL)
      }
      job_abort(
        "The Agent job execution record could not be locked.",
        class = "job_persistence",
        parent = error
      )
    }
  )
  if (is.null(execution_lock)) {
    # The worker may have committed a terminal record just after the lock
    # attempt became busy. Reconcile that immutable snapshot without holding
    # the control lock across the execution-lock attempt. If it is still
    # active, leave the durable request for the worker's checkpoint/poller.
    latest <- job_record_read(path)
    latest_record <- latest$record
    if (latest_record$status %in% job_terminal_statuses) {
      job_control_acknowledge(path, latest_record, reason)
    }
    return(job_job(
      path,
      latest_record,
      latest$envelope,
      job_control_read(path, latest_record)
    ))
  }
  on.exit(approval_store_unlock(execution_lock), add = TRUE)
  loaded <- job_record_read(path)
  record <- loaded$record
  control <- job_control_read(path, record)
  if (record$status %in% job_terminal_statuses) {
    control <- job_control_acknowledge(path, record, reason)
    return(job_job(path, record, loaded$envelope, control))
  }
  if (record$status %in% c("queued", "approval_pending")) {
    return(job_cancel_unstarted(
      path,
      record,
      execution_lock,
      reason = reason,
      message = "The host requested cancellation.",
      acknowledge = TRUE
    ))
  }
  # Acquiring the execution lock while a running/resuming record remains means
  # no worker owns it anymore. Recover it under the held lock instead of
  # leaving a requested record that can never settle.
  reason <- control$reason %||%
    "worker abandoned while cancellation was requested"
  record <- job_mark_recovery(path, record, execution_lock, reason)
  control <- job_control_read(path, record)
  if (identical(control$status, "requested")) {
    control <- job_control_acknowledge(path, record, reason)
  }
  job_job(path, record, approval_store_envelope(path), control)
}
