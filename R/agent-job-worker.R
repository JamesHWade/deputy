#' @include agent-job-store.R agent-job-runtime.R
NULL

# Active job worker lifecycle: binding, checkpointing, cancellation polling,
# governed execution, cleanup ledgers, and durable settlement.

job_snapshot_limit <- function(worker) {
  worker$snapshot_limit %||%
    floor(approval_store_envelope(worker$path)$max_bytes / 2)
}

job_merge_snapshot <- function(record, snapshot, event = NULL, max_bytes) {
  if (!is.null(event)) {
    record <- job_event_append(record, event)
  }
  if (is.null(snapshot)) {
    return(record)
  }
  if (!is.list(snapshot) || is.object(snapshot)) {
    job_abort(
      "The Agent job runtime returned a non-portable snapshot.",
      "job_persistence"
    )
  }
  snapshot <- job_safe_value(snapshot, max_bytes = max_bytes)
  if (!is.list(snapshot) || !is.null(snapshot$omitted)) {
    job_abort(
      "The Agent job runtime snapshot exceeded its persistence bound.",
      "job_persistence"
    )
  }
  runtime <- record$runtime %||% list()
  for (field in c(
    "usage",
    "node_usage",
    "effects",
    "graph",
    "source",
    "pending_approval",
    "event"
  )) {
    if (field %in% names(snapshot)) runtime[[field]] <- snapshot[[field]]
  }
  runtime <- job_bound_value(runtime, max_bytes)
  if (!is.null(runtime$omitted)) {
    job_abort(
      "The Agent job runtime snapshot exceeded its persistence bound.",
      "job_persistence"
    )
  }
  record$runtime <- runtime
  if ("usage" %in% names(snapshot) && is.list(snapshot$usage)) {
    record$usage <- snapshot$usage
  }
  if ("effects" %in% names(snapshot) && is.list(snapshot$effects)) {
    record$effects <- snapshot$effects
  }
  if ("graph" %in% names(snapshot) && is.list(snapshot$graph)) {
    record$graph <- snapshot$graph
  }
  if ("source" %in% names(snapshot) && is.list(snapshot$source)) {
    record$source <- snapshot$source
  }
  if (
    !record$status %in% job_terminal_statuses &&
      "pending_approval" %in% names(snapshot)
  ) {
    record["pending_approval"] <- list(
      if (is.null(snapshot$pending_approval)) {
        NULL
      } else {
        job_pending_record(snapshot$pending_approval)
      }
    )
  }
  record
}

job_record_has_executing_effect <- function(record) {
  effects <- record$effects %||% record$runtime$effects %||% list()
  if (!length(effects)) {
    return(FALSE)
  }
  any(vapply(
    effects,
    function(effect) is.list(effect) && identical(effect$status, "executing"),
    logical(1)
  ))
}

job_worker_checkpoint <- function(worker, agent, event = NULL) {
  if (!is.null(worker$persistence_error)) {
    rlang::cnd_signal(worker$persistence_error)
  }
  tryCatch(
    job_worker_checkpoint_commit(worker, agent, event),
    error = function(error) {
      if (inherits(error, "deputy_job_cancelled")) {
        rlang::cnd_signal(error)
      }
      failure <- tryCatch(
        job_abort(
          "The Agent job checkpoint could not be persisted.",
          class = "job_persistence",
          parent = error
        ),
        error = identity
      )
      worker$persistence_error <- worker$persistence_error %||% failure
      rlang::cnd_signal(worker$persistence_error)
    }
  )
}

job_worker_checkpoint_commit <- function(worker, agent, event = NULL) {
  if (isTRUE(worker$finished)) {
    return(invisible(NULL))
  }
  snapshot <- job_store_call(
    job_runtime_snapshot(agent, event),
    "The Agent job runtime snapshot could not be persisted.",
    class = "job_persistence"
  )
  record <- job_merge_snapshot(
    worker$record,
    snapshot,
    event,
    max_bytes = job_snapshot_limit(worker)
  )
  record <- job_record_write(worker$path, record, worker$lock)
  worker$record <- record
  if (job_control_requested(worker$path, record)) {
    reason <- job_control_read(
      worker$path,
      record
    )$reason %||%
      "cancelled"
    executing <- job_record_has_executing_effect(record)
    status <- if (executing) "indeterminate" else "cancelled"
    record$error <- list(
      class = "job_cancelled",
      message = "The host requested cancellation.",
      reason = job_safe_string(reason)
    )
    worker$record <- record
    job_worker_finish(worker, status, reason = reason)
    job_abort(
      "The Agent job was cancelled.",
      class = "job_cancelled",
      reason = reason
    )
  }
  invisible(NULL)
}

job_worker_start_poller <- function(worker) {
  worker$poller_active <- TRUE
  poll <- NULL
  poll <- function() {
    if (!isTRUE(worker$poller_active)) {
      return(invisible(NULL))
    }
    requested <- tryCatch(
      job_control_requested(worker$path, worker$record),
      error = function(error) FALSE
    )
    if (requested && !is.null(worker$agent)) {
      reason <- tryCatch(
        job_control_read(
          worker$path,
          worker$record,
          missing_ok = TRUE
        )$reason %||%
          "cancelled",
        error = function(error) "cancelled"
      )
      try(worker$agent$interrupt(reason), silent = TRUE)
    }
    if (isTRUE(worker$poller_active)) {
      try(later::later(poll, delay = 0.25), silent = TRUE)
    }
    invisible(NULL)
  }
  try(later::later(poll, delay = 0.25), silent = TRUE)
  invisible(NULL)
}

job_cleanup_write <- function(worker, record) {
  job_store_call(
    job_record_write(worker$path, record, worker$lock, settling = TRUE),
    "The Agent job cleanup ledger could not be persisted.",
    class = "job_persistence"
  )
}

job_worker_cleanup <- function(worker) {
  record <- worker$record
  detach_error <- NULL
  detaching <- !is.null(worker$detach)
  if (detaching) {
    detach_error <- tryCatch(
      {
        worker$detach()
        NULL
      },
      error = identity
    )
    worker$detach <- NULL
    if (is.null(detach_error)) {
      record$runtime$attached <- FALSE
      record$runtime$detached_at <- as.numeric(Sys.time())
      if (is.null(worker$cleanup)) {
        record$cleanup <- list(
          owner = "host",
          required = FALSE,
          status = "not_required",
          attempts = 0L
        )
      }
    } else {
      record$runtime$detach_error <- job_error_record(detach_error)
      record$cleanup$status <- "unknown"
      record$cleanup$required <- TRUE
      record$cleanup$reason <- "runtime detach failed"
    }
  }
  cleanup_error <- NULL
  if (!is.null(worker$cleanup) && !isTRUE(worker$cleanup_called)) {
    worker$cleanup_called <- TRUE
    record$cleanup$attempts <- as.integer(record$cleanup$attempts %||% 0L) + 1L
    record$cleanup$status <- "running"
    record$cleanup$required <- TRUE
    record$cleanup$owner <- "binder"
    ledger_error <- tryCatch(
      {
        record <- job_cleanup_write(worker, record)
        worker$record <- record
        NULL
      },
      error = identity
    )
    cleanup_error <- tryCatch(
      {
        worker$cleanup()
        NULL
      },
      error = identity
    )
    if (is.null(cleanup_error)) {
      if (is.null(detach_error)) {
        record$cleanup$status <- "completed"
        record$cleanup$required <- FALSE
        record$cleanup$completed_at <- as.numeric(Sys.time())
      } else {
        record$cleanup$status <- "unknown"
        record$cleanup$required <- TRUE
        record$cleanup$reason <- "runtime detach failed"
      }
    } else {
      record$cleanup$status <- "failed"
      record$cleanup$required <- TRUE
      record$cleanup$error <- job_error_record(cleanup_error)
    }
    post_error <- tryCatch(
      {
        record <- job_cleanup_write(worker, record)
        worker$record <- record
        NULL
      },
      error = identity
    )
    cleanup_error <- ledger_error %||% post_error %||% cleanup_error
  }
  if (detaching && is.null(worker$cleanup)) {
    cleanup_error <- tryCatch(
      {
        record <- job_cleanup_write(worker, record)
        NULL
      },
      error = identity
    )
  }
  worker$record <- record
  if (!is.null(detach_error) && is.null(cleanup_error)) {
    cleanup_error <- detach_error
  }
  invisible(cleanup_error)
}

job_worker_finish <- function(
  worker,
  status,
  result = NULL,
  error = NULL,
  reason = NULL
) {
  record <- worker$record
  if (!identical(record$status, status)) {
    record <- job_transition(record, status, reason)
  }
  record["result"] <- list(
    if (identical(status, "completed")) {
      job_result_record(result)
    } else if (!is.null(result) && S7::S7_inherits(result, AgentResult)) {
      # A successful task result remains useful when cleanup or durable
      # settlement fails. Keep its bounded portable summary alongside the
      # failure/indeterminate disposition so hosts can inspect both outcomes.
      job_result_record(result)
    } else {
      record$result %||% NULL
    }
  )
  if (identical(status, "completed")) {
    record["error"] <- list(NULL)
  } else if (!is.null(error)) {
    record["error"] <- list(job_error_record(error))
  }
  if (status %in% job_terminal_statuses) {
    record["pending_approval"] <- list(NULL)
  }
  if (identical(status, "indeterminate")) {
    record <- job_release_reservation(record, release = FALSE, reason = reason)
    if (!job_cleanup_settled(record$cleanup)) {
      record$cleanup$status <- "unknown"
      record$cleanup$required <- TRUE
    }
  } else {
    record <- job_release_reservation(record, release = TRUE, reason = reason)
  }
  record <- job_record_write(worker$path, record, worker$lock)
  worker$record <- record
  worker$terminal <- status
  control_status <- if (identical(status, "cancelled")) {
    "cancelled"
  } else {
    "acknowledged"
  }
  try(
    job_control_write(worker$path, record, control_status, reason),
    silent = TRUE
  )
  invisible(record)
}

job_cancel_unstarted <- function(
  path,
  record,
  lock,
  reason,
  message,
  acknowledge = FALSE
) {
  record$error <- list(
    class = "job_cancelled",
    message = message,
    reason = job_safe_string(reason)
  )
  record <- job_transition(record, "cancelled", reason)
  record <- job_release_reservation(record, release = TRUE, reason = reason)
  record["pending_approval"] <- list(NULL)
  record <- job_record_write(path, record, lock)
  control <- if (isTRUE(acknowledge)) {
    job_control_acknowledge(path, record, reason)
  } else {
    job_control_write(path, record, "cancelled", reason)
    job_control_read(path, record)
  }
  job_job(path, record, approval_store_envelope(path), control)
}

# Bind the host-supplied agent and attach its cleanup callback before rejecting
# an invalid agent, so binder-acquired resources are still released on failure.
job_worker_bind <- function(worker, bind, bind_record, checkpoint) {
  tryCatch(
    {
      supplied <- bind(job_snapshot(worker$path, bind_record))
      if (is.list(supplied) && !inherits(supplied, "Agent")) {
        worker$agent <- supplied$agent
        worker$cleanup <- supplied$cleanup %||% NULL
      } else {
        worker$agent <- supplied
        worker$cleanup <- NULL
      }
      if (!is.null(worker$cleanup) && !is.function(worker$cleanup)) {
        job_abort(
          "The Agent job binder cleanup must be a function.",
          "job_invalid"
        )
      }
      if (!is.null(worker$cleanup)) {
        worker$record$cleanup <- list(
          owner = "binder",
          required = TRUE,
          status = "attached",
          attempts = 0L,
          attached_at = as.numeric(Sys.time())
        )
      }
      if (
        !inherits(worker$agent, "Agent") ||
          inherits(worker$agent, "LeadAgent")
      ) {
        job_abort(
          "The Agent job binder must return an ordinary Agent.",
          "job_invalid"
        )
      }
      job_bind_agent(worker$agent, bind_record)
      worker$detach <- job_attach_runtime(
        worker$agent,
        checkpoint,
        record = bind_record
      )
      if (!is.function(worker$detach)) {
        job_abort(
          "The Agent job runtime did not return a detach function.",
          "job_invalid"
        )
      }
      worker$record$runtime$attached <- TRUE
      worker$record$runtime$attached_at <- as.numeric(Sys.time())
      worker$record <- job_record_write(
        worker$path,
        worker$record,
        worker$lock
      )
      job_worker_start_poller(worker)
      NULL
    },
    error = identity
  )
}

job_worker_execute <- function(
  worker,
  bind_record,
  resuming,
  decision,
  tool_input
) {
  result <- NULL
  run_error <- NULL
  run_id_before <- worker$agent$.__enclos_env__$private$current_run_id
  if (resuming) {
    pending_path <- job_pending_path(worker$record$pending_approval)
    if (is.null(pending_path)) {
      run_error <- simpleError("The pending approval path is missing.")
    } else {
      result <- tryCatch(
        worker$agent$resume_approval(
          pending_path,
          decision = decision,
          tool_input = tool_input,
          usage_limits = job_limits_value(worker$record$usage_limits)
        ),
        error = identity
      )
    }
  } else {
    run_context <- worker$record$manifest$nodes$root$run_context %||% list()
    result <- tryCatch(
      worker$agent$run_sync(
        worker$record$task,
        usage_limits = job_limits_value(worker$record$usage_limits),
        run_context = run_context
      ),
      error = identity
    )
  }
  if (inherits(result, "condition")) {
    run_error <- result
    result <- NULL
  }
  checkpoint_error <- tryCatch(
    {
      private <- worker$agent$.__enclos_env__$private
      state <- private$.job_state
      if (is.null(state)) NULL else state$checkpoint_error
    },
    error = function(error) NULL
  )
  checkpoint_error <- worker$persistence_error %||% checkpoint_error
  if (!is.null(checkpoint_error) && is.null(run_error)) {
    run_error <- checkpoint_error
  }

  # A fresh Agent has no resumed usage until its run actually starts. A
  # preflight rejection must not replace the saved ledger with that empty state.
  resume_not_started <- resuming &&
    !is.null(run_error) &&
    identical(
      run_id_before,
      worker$agent$.__enclos_env__$private$current_run_id
    )
  snapshot_error <- if (resume_not_started || !is.null(checkpoint_error)) {
    NULL
  } else {
    tryCatch(
      {
        snapshot <- job_runtime_snapshot(worker$agent)
        candidate <- job_merge_snapshot(
          worker$record,
          snapshot,
          max_bytes = job_snapshot_limit(worker)
        )
        worker$record <- job_record_write(worker$path, candidate, worker$lock)
        NULL
      },
      error = identity
    )
  }
  if (!is.null(snapshot_error) && is.null(run_error)) {
    run_error <- snapshot_error
  }
  pending <- if (resume_not_started && job_is_pending_error(run_error)) {
    bind_record$pending_approval
  } else {
    tryCatch(worker$agent$pending_approval(), error = function(error) NULL)
  }
  pending_path <- if (!is.null(pending)) job_pending_path(pending) else NULL
  if (
    is.null(pending_path) &&
      !is.null(run_error) &&
      job_is_pending_error(run_error)
  ) {
    pending_path <- run_error$path %||% NULL
  }
  list(
    result = result,
    run_error = run_error,
    checkpoint_error = checkpoint_error,
    snapshot_error = snapshot_error,
    pending = pending,
    pending_path = pending_path
  )
}

job_worker_settle <- function(worker, outcome) {
  result <- outcome$result
  run_error <- outcome$run_error
  checkpoint_error <- outcome$checkpoint_error
  snapshot_error <- outcome$snapshot_error
  pending <- outcome$pending
  pending_path <- outcome$pending_path

  worker$poller_active <- FALSE
  cleanup_error <- tryCatch(job_worker_cleanup(worker), error = identity)
  worker$finished <- TRUE
  cleanup_failed <- !is.null(cleanup_error)
  if (cleanup_failed && !is.null(pending_path)) {
    worker$record$runtime$pending_approval <- pending_path
  }
  if (
    cleanup_failed &&
      (inherits(cleanup_error, "deputy_job_persistence") ||
        is.null(run_error) ||
        job_is_pending_error(run_error))
  ) {
    run_error <- cleanup_error
  }
  persistence_error <- checkpoint_error %||%
    snapshot_error %||%
    if (inherits(cleanup_error, "deputy_job_persistence")) {
      cleanup_error
    } else if (inherits(run_error, "deputy_job_persistence")) {
      run_error
    } else {
      NULL
    }
  persistence_failure <- !is.null(persistence_error)
  if (!is.null(worker$terminal)) {
    if (persistence_failure) {
      job_worker_finish(
        worker,
        "indeterminate",
        result = result,
        error = persistence_error,
        reason = "job settlement persistence failed"
      )
    } else {
      worker$record <- job_record_write(
        worker$path,
        worker$record,
        worker$lock
      )
    }
    return(job_snapshot(worker$path, worker$record))
  }

  record <- worker$record
  control <- job_control_read(worker$path, record)
  requested <- isTRUE(control$requested)
  executing <- job_record_has_executing_effect(record)
  if (
    isTRUE(persistence_failure) ||
      isTRUE(requested) ||
      (!is.null(run_error) && job_is_cancelled_error(run_error))
  ) {
    status <- if (persistence_failure || executing) {
      "indeterminate"
    } else {
      "cancelled"
    }
    reason <- if (persistence_failure) {
      "job persistence failed"
    } else {
      control$reason %||% run_error$reason %||% "cancelled"
    }
    worker$record <- record
    job_worker_finish(
      worker,
      status,
      result = result,
      error = persistence_error %||%
        run_error %||%
        simpleError("The Agent job was cancelled."),
      reason = reason
    )
  } else if (
    !cleanup_failed &&
      !is.null(pending_path) &&
      (is.null(run_error) || job_is_pending_error(run_error))
  ) {
    record$pending_approval <- if (!is.null(pending)) {
      job_pending_record(pending)
    } else {
      job_pending_record(pending_path)
    }
    record$runtime$pending_approval <- pending_path
    record["error"] <- list(NULL)
    record <- job_transition(record, "approval_pending", "approval requested")
    pending_error <- tryCatch(
      {
        worker$record <- job_record_write(worker$path, record, worker$lock)
        NULL
      },
      error = identity
    )
    if (!is.null(pending_error)) {
      # The pending evidence must fit with its own future settlement reserve.
      # If it does not, retain the committed ledger and settle uncertainty.
      job_worker_finish(
        worker,
        "indeterminate",
        error = pending_error,
        reason = "approval checkpoint could not be persisted"
      )
    }
  } else if (is.null(run_error) && S7::S7_inherits(result, AgentResult)) {
    worker$record <- record
    job_worker_finish(worker, "completed", result = result)
  } else {
    if (is.null(run_error)) {
      run_error <- simpleError("The Agent run ended without a result.")
    }
    worker$record <- record
    job_worker_finish(
      worker,
      if (executing || persistence_failure) "indeterminate" else "failed",
      result = result,
      error = run_error,
      reason = "run failed"
    )
  }
  job_snapshot(worker$path, worker$record)
}
