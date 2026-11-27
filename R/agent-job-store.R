#' @include agent-job-record.R
NULL

# Persisted job store validation, revision reads/writes, control records,
# host authorization receipts, and abandoned-worker recovery.

job_store_call <- function(expr, message, class = "job_corrupt") {
  tryCatch(
    expr,
    error = function(error) {
      job_abort(message, class = class, parent = error)
    }
  )
}

job_store_path <- function(path) {
  job_store_call(
    approval_store_path(path),
    "Job directory does not exist or is not a committed job store."
  )
}

job_control_id <- function(record) {
  id <- record$control_id
  if (
    !is.character(id) ||
      length(id) != 1L ||
      is.na(id) ||
      !grepl("^[A-Za-z0-9_]+$", id)
  ) {
    job_abort("The persisted job control identifier is invalid.", "job_corrupt")
  }
  id
}

job_control_path <- function(path, record) {
  file.path(path, job_control_id(record))
}

# Leave room for both serialized revisions during atomic replacement, including
# the bounded cancellation reason and envelope metadata.
job_control_limit <- function(max_bytes) min(max_bytes, 64L * 1024L)

job_record_validate <- function(record, allow_control = FALSE) {
  required <- if (allow_control) {
    c("schema_version", "id", "status")
  } else {
    c(
      "schema_version",
      "id",
      "status",
      "task",
      "owner_id",
      "definition_revision",
      "context_revision",
      "usage_limits",
      "associations",
      "manifest",
      "allocation",
      "reservations",
      "usage",
      "transitions",
      "events",
      "pending_approval",
      "pending_decision",
      "result",
      "error",
      "cleanup",
      "runtime",
      "graph",
      "source",
      "control_id"
    )
  }
  approval_store_record(record)
  statuses <- if (allow_control) {
    c("idle", "requested", "acknowledged", "cancelled", "unknown")
  } else {
    job_status_values
  }
  if (
    !all(required %in% names(record)) ||
      !identical(record$schema_version, 1L) ||
      !is.character(record$status) ||
      length(record$status) != 1L ||
      is.na(record$status) ||
      !record$status %in% statuses
  ) {
    job_abort("The committed Agent job record is invalid.", "job_corrupt")
  }
  if (allow_control) {
    return(invisible(record))
  }
  if (
    !is_nonempty_string(record$task) ||
      nchar(record$task, "bytes") > job_max_task_bytes ||
      !is_nonempty_string(record$owner_id)
  ) {
    job_abort(
      "The committed Agent job identity or task is invalid.",
      "job_corrupt"
    )
  }
  job_revision(record$definition_revision, "definition_revision")
  job_revision(record$context_revision, "context_revision")
  limits <- job_store_call(
    do.call(UsageLimits, record$usage_limits),
    "The committed Agent job limits are invalid."
  )
  job_limits_record(limits)
  job_usage_record(job_usage_value(record$usage))
  for (field in c(
    "associations",
    "manifest",
    "allocation",
    "reservations",
    "transitions",
    "events",
    "cleanup",
    "runtime",
    "graph",
    "source"
  )) {
    if (identical(field, "graph") && is.null(record[[field]])) {
      next
    }
    job_plain_list(record[[field]], field)
  }
  for (field in c("pending_approval", "pending_decision", "result", "error")) {
    if (!is.null(record[[field]])) job_plain_list(record[[field]], field)
  }
  job_control_id(record)
  approval_portable(record)
  invisible(record)
}

job_control_validate <- function(control, record = NULL) {
  job_record_validate(control, allow_control = TRUE)
  if (!is.null(record)) {
    if (
      !identical(control$job_id, record$id) ||
        !identical(control$id, record$control_id)
    ) {
      job_abort(
        "The committed job cancellation record is mismatched.",
        "job_corrupt"
      )
    }
  }
  if (
    !is.logical(control$requested) ||
      length(control$requested) != 1L ||
      is.na(control$requested)
  ) {
    job_abort(
      "The committed job cancellation record is invalid.",
      "job_corrupt"
    )
  }
  invisible(control)
}

job_record_read <- function(path) {
  path <- job_store_path(path)
  record <- job_store_call(
    approval_store_read(path),
    "Cannot read the committed Agent job."
  )
  job_record_validate(record)
  list(path = path, record = record, envelope = approval_store_envelope(path))
}

job_control_read <- function(path, record, missing_ok = FALSE) {
  control_path <- job_control_path(path, record)
  if (!dir.exists(control_path)) {
    if (isTRUE(missing_ok)) {
      return(list(
        schema_version = 1L,
        id = record$control_id,
        status = "unknown",
        job_id = record$id,
        requested = FALSE,
        reason = "control record unavailable"
      ))
    }
    job_abort("The Agent job cancellation record is missing.", "job_corrupt")
  }
  control <- job_store_call(
    approval_store_read(control_path),
    "Cannot read the Agent job cancellation record."
  )
  job_control_validate(control, record)
  control
}

job_control_requested <- function(path, record) {
  control <- job_control_read(path, record)
  isTRUE(control$requested)
}

job_record_trim_events <- function(record) {
  events <- record$events %||% list()
  count <- length(events)
  if (!count) {
    return(NULL)
  }
  dropped <- max(1L, ceiling(count / 2L))
  record$events <- if (dropped >= count) {
    list()
  } else {
    tail(events, count - dropped)
  }
  record$event_dropped <- as.integer(record$event_dropped %||% 0L) +
    as.integer(dropped)
  record
}

# Active revisions leave room for the bounded result (1 MiB), cleanup evidence,
# and terminal diagnostics. The store applies this to the complete serialized
# envelope and its atomic replacement, without lowering its persisted limit.
job_settlement_reserve <- 1024^2 + 128 * 1024

job_record_write <- function(path, record, lock, settling = FALSE) {
  job_record_validate(record)
  envelope <- approval_store_envelope(path)
  candidate <- record
  repeat {
    write_error <- tryCatch(
      {
        approval_store_write(
          path,
          candidate,
          lock,
          max_bytes = envelope$max_bytes,
          reserve_bytes = if (
            settling || candidate$status %in% job_terminal_statuses
          ) {
            0
          } else {
            job_settlement_reserve
          }
        )
        NULL
      },
      error = identity
    )
    if (is.null(write_error)) {
      return(invisible(candidate))
    }
    if (!identical(write_error$reason, "size_limit")) {
      rlang::cnd_signal(write_error)
    }
    trimmed <- job_record_trim_events(candidate)
    if (is.null(trimmed)) {
      rlang::cnd_signal(write_error)
    }
    candidate <- trimmed
  }
}

job_control_write <- function(path, record, status, reason = NULL) {
  control_path <- job_control_path(path, record)
  lock <- approval_store_lock(control_path)
  on.exit(approval_store_unlock(lock), add = TRUE)
  current <- job_control_read(path, record)
  current$status <- status
  if (status %in% c("requested", "cancelled")) {
    current$requested <- TRUE
  }
  current$reason <- job_safe_string(reason)
  current$updated_at <- as.numeric(Sys.time())
  job_control_validate(current, record)
  envelope <- approval_store_envelope(control_path)
  approval_store_write(
    control_path,
    current,
    lock,
    max_bytes = envelope$max_bytes
  )
  invisible(current)
}

job_control_acknowledge <- function(path, record, reason) {
  tryCatch(
    job_control_write(
      path,
      record,
      status = if (identical(record$status, "cancelled")) {
        "cancelled"
      } else {
        "acknowledged"
      },
      reason = reason
    ),
    error = function(error) {
      if (identical(error$reason, "busy")) {
        job_abort(
          "The Agent job cancellation record is busy; retry cancellation.",
          class = "job_busy",
          parent = error
        )
      }
      job_abort(
        "The Agent job cancellation record could not be reconciled.",
        class = "job_persistence",
        parent = error
      )
    }
  )
}

job_authorization_fields <- function(record) {
  list(
    job_id = record$id,
    owner_id = record$owner_id,
    definition_revision = record$definition_revision,
    context_revision = record$context_revision
  )
}

job_authorize <- function(path, record, authorize) {
  if (!is.function(authorize)) {
    job_abort("{.arg authorize} must be a function.")
  }
  before <- job_job(path, record)
  result <- job_store_call(
    authorize(before),
    "The host did not authorize this Agent job.",
    class = "job_unauthorized"
  )
  if (!is.list(result) || is.object(result)) {
    job_abort(
      "The host did not return a valid Agent job authorization receipt.",
      "job_unauthorized"
    )
  }
  if ("authorized" %in% names(result) && !isTRUE(result$authorized)) {
    job_abort("The host denied this Agent job.", "job_unauthorized")
  }
  receipt <- result$receipt %||% result$identity %||% result$id %||% result
  if (!is.list(receipt) || is.object(receipt)) {
    job_abort(
      "The host did not return a valid Agent job authorization receipt.",
      "job_unauthorized"
    )
  }
  expected <- job_authorization_fields(record)
  if (
    !setequal(names(receipt), names(expected)) ||
      length(receipt) != length(expected) ||
      any(vapply(
        names(expected),
        function(field) !identical(receipt[[field]], expected[[field]]),
        logical(1)
      ))
  ) {
    job_abort("The Agent job authorization receipt is stale.", "job_stale")
  }
  approval_portable(receipt)
  current <- job_record_read(path)$record
  for (field in c(
    "id",
    "owner_id",
    "definition_revision",
    "context_revision"
  )) {
    if (!identical(current[[field]], record[[field]])) {
      job_abort(
        "The Agent job changed while it was being authorized.",
        "job_stale"
      )
    }
  }
  receipt
}

job_release_reservation <- function(record, release = TRUE, reason = NULL) {
  reservation <- record$reservations %||% list()
  reservation$released <- isTRUE(release)
  reservation$status <- if (isTRUE(release)) "released" else "preserved"
  reservation$updated_at <- as.numeric(Sys.time())
  reservation$reason <- job_safe_string(reason)
  record$reservations <- reservation
  record
}

job_cleanup_settled <- function(cleanup) {
  isTRUE(cleanup$status %in% c("completed", "failed")) ||
    (identical(cleanup$owner, "host") &&
      identical(cleanup$status, "not_required") &&
      identical(cleanup$required, FALSE))
}

job_mark_recovery <- function(path, record, lock, reason) {
  record$cleanup <- record$cleanup %||%
    list(
      owner = "unknown",
      status = "unknown",
      required = TRUE,
      attempts = 0L
    )
  if (!job_cleanup_settled(record$cleanup)) {
    record$cleanup$status <- "unknown"
    record$cleanup$required <- TRUE
    record$cleanup$reason <- job_safe_string(reason)
  }
  record <- job_release_reservation(record, release = FALSE, reason = reason)
  record <- job_transition(record, "indeterminate", reason)
  record$error <- list(
    class = "job_recovery",
    message = "The previous worker ended before durable settlement.",
    reason = job_safe_string(reason)
  )
  record <- job_record_write(path, record, lock)
  try(job_control_write(path, record, "acknowledged", reason), silent = TRUE)
  record
}
