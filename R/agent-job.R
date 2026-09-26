#' @include approval-store.R approval-record.R run-usage.R agent-result.R
NULL

# Durable host-owned Agent jobs. Persistence uses approval_store_*; there is no
# second revision or locking protocol.

job_status_values <- c(
  "queued",
  "running",
  "resuming",
  "approval_pending",
  "completed",
  "failed",
  "cancelled",
  "indeterminate"
)
job_terminal_statuses <- c(
  "completed",
  "failed",
  "cancelled",
  "indeterminate"
)
job_transition_targets <- list(
  queued = c("running", "cancelled", "failed"),
  running = c(
    "resuming",
    "approval_pending",
    "completed",
    "failed",
    "cancelled",
    "indeterminate"
  ),
  resuming = c(
    "approval_pending",
    "completed",
    "failed",
    "cancelled",
    "indeterminate"
  ),
  approval_pending = c("resuming", "cancelled", "failed"),
  completed = character(),
  failed = character(),
  # The active worker can discover a cleanup persistence failure after its
  # cancellation checkpoint. Public terminal entry points remain read-only.
  cancelled = "indeterminate",
  indeterminate = character()
)
job_max_events <- 512L
job_max_transitions <- 128L
job_max_event_bytes <- 32L * 1024L
job_max_error_bytes <- 16L * 1024L
job_max_task_bytes <- 1024L * 1024L

job_abort <- function(message, class = "job_error", parent = NULL, ...) {
  abort_deputy(
    message,
    class = class,
    parent = parent,
    ...,
    .envir = parent.frame()
  )
}

job_text <- function(value, field, max_bytes = job_max_task_bytes) {
  if (!is_nonempty_string(value) || length(attributes(value)) > 0L) {
    job_abort("{.arg {field}} must be one non-empty plain string.")
  }
  value <- enc2utf8(value)
  if (is.na(iconv(value, "UTF-8", "UTF-8"))) {
    job_abort("{.arg {field}} must contain valid UTF-8 text.")
  }
  if (nchar(value, type = "bytes") > max_bytes) {
    job_abort("{.arg {field}} exceeds its byte limit.")
  }
  value
}

job_revision <- function(value, field) {
  if (
    is.character(value) &&
      length(value) == 1L &&
      !is.na(value) &&
      nzchar(trimws(value)) &&
      length(attributes(value)) == 0L
  ) {
    return(enc2utf8(value))
  }
  if (
    is.numeric(value) &&
      length(value) == 1L &&
      !is.na(value) &&
      is.finite(value) &&
      length(attributes(value)) == 0L
  ) {
    return(as.numeric(value))
  }
  job_abort(
    "{.arg {field}} must be one non-missing character or numeric revision."
  )
}

job_plain_list <- function(value, field) {
  if (!is.list(value) || is.object(value)) {
    job_abort("{.arg {field}} must be a plain list.")
  }
  approval_portable(value)
  value
}

job_limits_record <- function(limits, field = "usage_limits") {
  if (!S7::S7_inherits(limits, UsageLimits)) {
    job_abort("{.arg {field}} must be a UsageLimits value.")
  }
  fields <- S7::props(limits)
  approval_portable(fields)
  fields
}

job_usage_record <- function(usage, field = "usage") {
  usage <- usage %||% AgentUsage()
  if (!S7::S7_inherits(usage, AgentUsage)) {
    job_abort("{.arg {field}} must be an AgentUsage value.")
  }
  fields <- S7::props(usage)
  approval_portable(fields)
  fields
}

job_usage_value <- function(usage, field = "usage") {
  if (is.null(usage)) {
    return(AgentUsage())
  }
  if (S7::S7_inherits(usage, AgentUsage)) {
    return(usage)
  }
  if (is.list(usage)) {
    return(tryCatch(
      approval_usage(usage),
      error = function(error) {
        job_abort(
          "The persisted job usage is invalid.",
          class = "job_corrupt",
          parent = error
        )
      }
    ))
  }
  job_abort("The persisted job usage is invalid.", "job_corrupt")
}

job_limits_value <- function(limits, field = "usage_limits") {
  if (S7::S7_inherits(limits, UsageLimits)) {
    return(limits)
  }
  if (is.list(limits)) {
    return(tryCatch(
      do.call(UsageLimits, limits),
      error = function(error) {
        job_abort(
          "The persisted job usage limits are invalid.",
          class = "job_corrupt",
          parent = error
        )
      }
    ))
  }
  job_abort("The persisted job usage limits are invalid.", "job_corrupt")
}

job_store_path <- function(path) {
  tryCatch(
    approval_store_path(path),
    error = function(error) {
      job_abort(
        "Job directory does not exist or is not a committed job store.",
        class = "job_corrupt",
        parent = error
      )
    }
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

job_safe_string <- function(value, max_bytes = job_max_error_bytes) {
  if (is.null(value)) {
    return(NULL)
  }
  value <- tryCatch(as.character(value[[1L]]), error = function(error) NULL)
  if (is.null(value) || is.na(value)) {
    return(NULL)
  }
  inspection_text(value, max_bytes)
}

job_bound_value <- function(value, max_bytes) {
  okay <- tryCatch(
    {
      approval_portable(value)
      if (!observation_payload_fits(value, max_bytes)) {
        FALSE
      } else {
        length(serialize(value, NULL, version = 3)) <= max_bytes
      }
    },
    error = function(error) FALSE
  )
  if (isTRUE(okay)) {
    value
  } else {
    list(omitted = "value exceeds the job evidence bound")
  }
}

job_safe_value <- function(value, depth = 0L, max_bytes = job_max_event_bytes) {
  if (depth > 32L) {
    return(list(omitted = "nesting limit"))
  }
  if (is.null(value)) {
    return(NULL)
  }
  if (S7::S7_inherits(value, AgentUsage)) {
    return(S7::props(value))
  }
  if (S7::S7_inherits(value, UsageLimits)) {
    return(S7::props(value))
  }
  if (S7::S7_inherits(value, AgentEvent)) {
    return(job_safe_event(value, max_bytes = max_bytes))
  }
  if (inherits(value, "condition")) {
    return(list(
      class = as.character(class(value)[[1L]] %||% "condition"),
      message = job_safe_string(conditionMessage(value))
    ))
  }
  if (
    is.function(value) ||
      is.environment(value) ||
      typeof(value) %in% c("externalptr", "weakref") ||
      isS4(value) ||
      S7::S7_inherits(value)
  ) {
    return(list(omitted = "runtime object"))
  }
  if (inherits(value, "POSIXct")) {
    value <- as.numeric(value)
  }
  if (is.list(value) && !is.object(value)) {
    fits <- tryCatch(
      {
        approval_portable(value)
        if (!observation_payload_fits(value, max_bytes)) {
          FALSE
        } else {
          length(serialize(value, NULL, version = 3)) <= max_bytes
        }
      },
      error = function(error) FALSE
    )
    if (!isTRUE(fits)) {
      return(list(omitted = "value exceeds the job evidence bound"))
    }
    output <- if (is.null(names(value))) {
      lapply(value, job_safe_value, depth = depth + 1L, max_bytes = max_bytes)
    } else {
      output <- vector("list", length(value))
      names(output) <- names(value)
      for (index in seq_along(value)) {
        output[index] <- list(job_safe_value(
          value[[index]],
          depth = depth + 1L,
          max_bytes = max_bytes
        ))
      }
      output
    }
    return(job_bound_value(output, max_bytes))
  }
  if (is.atomic(value)) {
    value <- tryCatch(
      {
        attributes(value) <- attributes(value)[
          intersect(names(attributes(value)), "names")
        ]
        value
      },
      error = function(error) NULL
    )
    if (is.null(value)) {
      return(list(omitted = "unsupported value"))
    }
    return(job_bound_value(value, max_bytes))
  }
  list(omitted = "unsupported value")
}

job_safe_event <- function(event, max_bytes = job_max_event_bytes) {
  if (S7::S7_inherits(event, AgentEvent)) {
    value <- list(
      type = event$type,
      timestamp = as.numeric(event$timestamp),
      data = job_safe_value(event$data, max_bytes = max_bytes)
    )
  } else if (is.list(event) && !is.object(event)) {
    value <- list(
      type = job_safe_string(event$type %||% "checkpoint", 256L) %||%
        "checkpoint",
      data = job_safe_value(event, max_bytes = max_bytes)
    )
  } else {
    value <- list(
      type = "checkpoint",
      data = job_safe_value(event, max_bytes = max_bytes)
    )
  }
  job_bound_value(value, max_bytes)
}

job_error_record <- function(error) {
  classes <- as.character(class(error))
  classes <- classes[nzchar(classes)]
  classes <- unname(unlist(
    lapply(utils::head(unique(classes), 4L), job_safe_string, max_bytes = 256L),
    use.names = FALSE
  ))
  message <- tryCatch(conditionMessage(error), error = function(e) "job error")
  reason <- tryCatch(error$reason, error = function(e) NULL)
  phase <- tryCatch(error$phase, error = function(e) NULL)
  job_bound_value(
    list(
      class = classes,
      message = job_safe_string(message, max_bytes = job_max_error_bytes / 2L),
      reason = job_safe_string(reason, max_bytes = 1024L),
      phase = job_safe_string(phase, max_bytes = 1024L)
    ),
    job_max_error_bytes
  )
}

job_result_record <- function(result) {
  if (is.null(result)) {
    return(NULL)
  }
  if (S7::S7_inherits(result, AgentResult)) {
    fields <- list(
      response = result$response,
      cost = result$cost,
      duration = result$duration,
      stop_reason = result$stop_reason,
      structured_output = result$structured_output,
      session_id = result$session_id,
      run_id = result$run_id,
      usage = if (is.null(result$usage)) NULL else S7::props(result$usage),
      agent_id = result$agent_id,
      agent_name = result$agent_name,
      parent_agent_id = result$parent_agent_id,
      parent_run_id = result$parent_run_id,
      delegation_id = result$delegation_id,
      run_context = result$run_context
    )
    safe <- lapply(
      fields,
      job_safe_value,
      max_bytes = 1024L * 1024L
    )
    names(safe) <- names(fields)
    return(job_bound_value(safe, 1024L * 1024L))
  }
  if (is.list(result) && !is.object(result)) {
    return(job_bound_value(job_safe_value(result), 1024L * 1024L))
  }
  list(omitted = "unsupported AgentResult")
}

job_is_cancelled_error <- function(error) {
  inherits(
    error,
    c("deputy_job_cancelled", "deputy_cancelled", "deputy_interrupted")
  ) ||
    identical(error$reason, "cancelled")
}

job_is_pending_error <- function(error) {
  inherits(error, "deputy_approval_pending") ||
    inherits(error, "deputy_approval_budget_exhausted") ||
    "approval_pending" %in% class(error)
}

job_pending_path <- function(pending) {
  if (is.character(pending) && length(pending) == 1L && !is.na(pending)) {
    return(pending)
  }
  if (S7::S7_inherits(pending, ApprovalContinuation)) {
    return(pending$source$path)
  }
  if (!is.list(pending)) {
    return(NULL)
  }
  pending$path %||% pending$source$path
}

job_pending_record <- function(pending) {
  if (is.null(pending)) {
    return(NULL)
  }
  if (is.character(pending)) {
    return(list(path = job_safe_string(pending, 4096L)))
  }
  if (S7::S7_inherits(pending, ApprovalContinuation)) {
    pending <- S7::props(pending)
    for (field in c("usage", "usage_limits", "budget_ceiling")) {
      if (S7::S7_inherits(pending[[field]], AgentUsage)) {
        pending[[field]] <- S7::props(pending[[field]])
      } else if (S7::S7_inherits(pending[[field]], UsageLimits)) {
        pending[[field]] <- S7::props(pending[[field]])
      }
    }
  }
  path <- job_safe_string(job_pending_path(pending), 4096L)
  # Reserve room for the separately retained resume path and its metadata.
  pending <- job_safe_value(pending, max_bytes = 1024L * 1024L - 8192L)
  if (!is.null(path)) {
    pending$path <- path
  }
  pending
}

job_event_append <- function(record, event) {
  events <- c(record$events %||% list(), list(job_safe_event(event)))
  dropped <- record$event_dropped %||% 0L
  if (length(events) > job_max_events) {
    dropped <- dropped + length(events) - job_max_events
    events <- tail(events, job_max_events)
  }
  record$events <- events
  record$event_dropped <- as.integer(dropped)
  record
}

job_transition <- function(record, status, reason = NULL) {
  if (!is_nonempty_string(status) || !status %in% job_status_values) {
    job_abort("Invalid Agent job status.", "job_corrupt")
  }
  if (status %in% job_terminal_statuses) {
    record["pending_approval"] <- list(NULL)
  }
  previous <- record$status
  if (identical(previous, status)) {
    return(record)
  }
  allowed <- job_transition_targets[[previous]] %||% character()
  if (!status %in% allowed) {
    job_abort(
      "The Agent job has an invalid lifecycle transition.",
      "job_corrupt"
    )
  }
  transition <- list(
    from = previous,
    to = status,
    at = as.numeric(Sys.time()),
    reason = job_safe_string(reason)
  )
  transitions <- c(record$transitions %||% list(), list(transition))
  dropped <- record$transition_dropped %||% 0L
  if (length(transitions) > job_max_transitions) {
    dropped <- dropped + length(transitions) - job_max_transitions
    transitions <- tail(transitions, job_max_transitions)
  }
  record$status <- status
  record$transitions <- transitions
  record$transition_dropped <- as.integer(dropped)
  record
}

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
  limits <- tryCatch(
    do.call(UsageLimits, record$usage_limits),
    error = function(error) {
      job_abort(
        "The committed Agent job limits are invalid.",
        "job_corrupt",
        parent = error
      )
    }
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
  record <- tryCatch(
    approval_store_read(path),
    error = function(error) {
      job_abort(
        "Cannot read the committed Agent job.",
        class = "job_corrupt",
        parent = error
      )
    }
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
  control <- tryCatch(
    approval_store_read(control_path),
    error = function(error) {
      job_abort(
        "Cannot read the Agent job cancellation record.",
        class = "job_corrupt",
        parent = error
      )
    }
  )
  job_control_validate(control, record)
  control
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

job_job <- function(path, record, envelope = NULL, control = NULL) {
  envelope <- envelope %||% approval_store_envelope(path)
  control <- control %||% job_control_read(path, record, missing_ok = TRUE)
  AgentJob(
    path = path,
    revision = envelope$revision,
    id = record$id,
    status = record$status,
    task = record$task,
    owner_id = record$owner_id,
    definition_revision = record$definition_revision,
    context_revision = record$context_revision,
    usage_limits = job_limits_value(record$usage_limits),
    usage = job_usage_value(record$usage),
    associations = record$associations,
    manifest = record$manifest,
    allocation = record$allocation,
    reservations = record$reservations,
    pending_approval = record$pending_approval,
    pending_decision = record$pending_decision,
    transitions = record$transitions,
    events = record$events,
    result = record$result,
    error = record$error,
    cleanup = record$cleanup,
    runtime = record$runtime,
    graph = record$graph,
    source = record$source,
    control = control
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
  result <- tryCatch(
    authorize(before),
    error = function(error) {
      job_abort(
        "The host did not authorize this Agent job.",
        class = "job_unauthorized",
        parent = error
      )
    }
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

#' Background job record
#'
#' A read-only snapshot of a background job, returned by [job_read()],
#' [job_run()] and [job_cancel()]. Read fields with `$`. It holds plain data
#' only, never an agent, chat, tools, callbacks or credentials.
#' @param path The job directory.
#' @param revision Revision number; it goes up with each update.
#' @param id Job ID.
#' @param status One of `"queued"`, `"running"`, `"resuming"`,
#'   `"approval_pending"`, `"completed"`, `"failed"`, `"cancelled"` or
#'   `"indeterminate"`. The last four are final.
#' @param task The task text.
#' @param owner_id The `owner_id` given to [job_create()].
#' @param definition_revision The `definition_revision` given to
#'   [job_create()].
#' @param context_revision The `context_revision` given to [job_create()].
#' @param usage_limits [UsageLimits] for the job.
#' @param usage [AgentUsage] so far.
#' @param associations The `associations` list given to [job_create()].
#' @param manifest The agent setup saved by [job_create()], which [job_run()]
#'   checks the rebuilt agent against.
#' @param allocation The usage limits set aside when the job was created.
#' @param reservations Whether that allocation is still held or has been
#'   released.
#' @param pending_approval Details of the approval the job is waiting for,
#'   including its `path`, or `NULL`.
#' @param pending_decision The approval decision being applied (`decision`,
#'   `tool_input`, `recorded_at`), or `NULL`.
#' @param transitions Status changes, each with `from`, `to`, `at` and
#'   `reason`. Only the latest 128 are kept.
#' @param events Simplified run events: at most the latest 512, fewer if
#'   needed to stay within the storage limit.
#' @param result Summary of the final [AgentResult] (`response`,
#'   `stop_reason`, `usage` and so on), or `NULL`.
#' @param error Summary of the error that ended the job (`class`, `message`
#'   and so on), or `NULL`.
#' @param cleanup Who is responsible for cleaning up the job's resources, and
#'   whether cleanup has run.
#' @param runtime State saved while the job ran, such as the tool calls it
#'   executed.
#' @param graph Usage and limits of the retained agent graph, or `NULL` for a
#'   single agent.
#' @param source IDs of the agents, sessions and runs involved.
#' @param control Cancellation state: whether [job_cancel()] was called, and
#'   its reason.
#'
#' @return An `AgentJob` object.
#' @export
AgentJob <- S7::new_class(
  "AgentJob",
  package = "deputy",
  properties = list(
    path = readonly_property("path", S7::class_character),
    revision = readonly_property("revision", S7::class_double),
    id = readonly_property("id", S7::class_character),
    status = readonly_property("status", S7::class_character),
    task = readonly_property("task", S7::class_character),
    owner_id = readonly_property("owner_id", S7::class_character),
    definition_revision = readonly_property(
      "definition_revision",
      S7::class_any
    ),
    context_revision = readonly_property("context_revision", S7::class_any),
    usage_limits = readonly_property("usage_limits", UsageLimits),
    usage = readonly_property("usage", AgentUsage),
    associations = readonly_property("associations", S7::class_list),
    manifest = readonly_property("manifest", S7::class_list),
    allocation = readonly_property("allocation", S7::class_list),
    reservations = readonly_property("reservations", S7::class_list),
    pending_approval = readonly_property(
      "pending_approval",
      S7::new_union(NULL, S7::class_list)
    ),
    pending_decision = readonly_property(
      "pending_decision",
      S7::new_union(NULL, S7::class_list)
    ),
    transitions = readonly_property("transitions", S7::class_list),
    events = readonly_property("events", S7::class_list),
    result = readonly_property("result", S7::new_union(NULL, S7::class_list)),
    error = readonly_property("error", S7::new_union(NULL, S7::class_list)),
    cleanup = readonly_property("cleanup", S7::class_list),
    runtime = readonly_property("runtime", S7::class_list),
    graph = readonly_property("graph", S7::new_union(NULL, S7::class_list)),
    source = readonly_property("source", S7::class_list),
    control = readonly_property("control", S7::class_list)
  ),
  constructor = function(
    path,
    revision,
    id,
    status,
    task,
    owner_id,
    definition_revision,
    context_revision,
    usage_limits,
    usage,
    associations = list(),
    manifest = list(),
    allocation = list(),
    reservations = list(),
    pending_approval = NULL,
    pending_decision = NULL,
    transitions = list(),
    events = list(),
    result = NULL,
    error = NULL,
    cleanup = list(),
    runtime = list(),
    graph = NULL,
    source = list(),
    control = list()
  ) {
    for (value in list(
      associations,
      manifest,
      allocation,
      reservations,
      pending_approval,
      pending_decision,
      transitions,
      events,
      result,
      error,
      cleanup,
      runtime,
      graph,
      source,
      control
    )) {
      if (!is.null(value)) approval_portable(value)
    }
    value <- S7::new_object(
      S7::S7_object(),
      path = job_text(path, "path", max_bytes = 4096L),
      revision = as.numeric(revision),
      id = job_text(id, "id", max_bytes = 256L),
      status = job_text(status, "status", max_bytes = 64L),
      task = job_text(task, "task"),
      owner_id = job_text(owner_id, "owner_id", max_bytes = 4096L),
      definition_revision = definition_revision,
      context_revision = context_revision,
      usage_limits = usage_limits,
      usage = usage,
      associations = associations,
      manifest = manifest,
      allocation = allocation,
      reservations = reservations,
      pending_approval = pending_approval,
      pending_decision = pending_decision,
      transitions = transitions,
      events = events,
      result = result,
      error = error,
      cleanup = cleanup,
      runtime = runtime,
      graph = graph,
      source = source,
      control = control
    )
    freeze_value(value)
  }
)

local({
  S7::method(`$`, AgentJob) <- function(x, name) S7::prop(x, name)
})

S7::method(print, AgentJob) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<AgentJob: {x$id}>")
    cli::cli_text("status: {x$status}")
    cli::cli_text("owner_id: {x$owner_id}")
    cli::cli_text("definition_revision: {x$definition_revision}")
    cli::cli_text("context_revision: {x$context_revision}")
    if (!is.null(x$result)) {
      cli::cli_text("result: persisted")
    }
    if (!is.null(x$error)) cli::cli_text("error: persisted")
  }))
  invisible(x)
}

job_control_requested <- function(path, record) {
  control <- job_control_read(path, record)
  isTRUE(control$requested)
}

job_initial_record <- function(
  id,
  control_id,
  task,
  owner_id,
  definition_revision,
  context_revision,
  usage_limits,
  associations,
  manifest
) {
  now <- as.numeric(Sys.time())
  graph <- manifest$graph %||% NULL
  limits <- S7::props(usage_limits)
  transition <- list(
    from = NULL,
    to = "queued",
    at = now,
    reason = "created"
  )
  list(
    schema_version = 1L,
    id = id,
    status = "queued",
    task = task,
    owner_id = owner_id,
    definition_revision = definition_revision,
    context_revision = context_revision,
    usage_limits = limits,
    associations = associations,
    manifest = manifest,
    allocation = list(
      usage_limits = limits,
      status = "reserved",
      created_at = now
    ),
    reservations = list(
      status = "reserved",
      released = FALSE,
      allocation = limits,
      created_at = now
    ),
    usage = S7::props(AgentUsage()),
    effects = list(),
    pending_approval = NULL,
    pending_decision = NULL,
    transitions = list(transition),
    transition_dropped = 0L,
    events = list(),
    event_dropped = 0L,
    result = NULL,
    error = NULL,
    cleanup = list(
      owner = "host",
      required = FALSE,
      status = "not_required",
      attempts = 0L
    ),
    runtime = list(
      attached = FALSE,
      effects = list(),
      graph = graph,
      source = list(),
      pending_approval = NULL
    ),
    graph = graph,
    source = list(),
    control_id = control_id
  )
}

job_control_record <- function(id, control_id) {
  list(
    schema_version = 1L,
    id = control_id,
    status = "idle",
    job_id = id,
    requested = FALSE,
    reason = NULL,
    created_at = as.numeric(Sys.time())
  )
}

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
  max_bytes <- tryCatch(
    approval_store_limit(max_bytes),
    error = function(error) {
      job_abort(
        "The Agent job storage limit is invalid.",
        class = "job_invalid",
        parent = error
      )
    }
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
  directory <- tryCatch(
    approval_store_path(directory),
    error = function(error) {
      job_abort(
        "The Agent job directory is invalid.",
        class = "job_invalid",
        parent = error
      )
    }
  )
  if (!is.function(job_agent_manifest)) {
    job_abort("The Agent job manifest helper is unavailable.", "job_invalid")
  }
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
  manifest <- tryCatch(
    job_agent_manifest(agent),
    error = function(error) {
      job_abort(
        "The Agent job manifest could not be captured.",
        class = "job_invalid",
        parent = error
      )
    }
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
  snapshot <- tryCatch(
    job_runtime_snapshot(agent, event),
    error = function(error) {
      job_abort(
        "The Agent job runtime snapshot could not be persisted.",
        class = "job_persistence",
        parent = error
      )
    }
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
  if (!requireNamespace("later", quietly = TRUE)) {
    return(invisible(NULL))
  }
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
  tryCatch(
    job_record_write(worker$path, record, worker$lock, settling = TRUE),
    error = function(error) {
      job_abort(
        "The Agent job cleanup ledger could not be persisted.",
        class = "job_persistence",
        parent = error
      )
    }
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
      # settlement fails.  Keep its bounded portable summary alongside the
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

job_bound_agent <- function(bound) {
  cleanup <- NULL
  agent <- bound
  if (is.list(bound) && !inherits(bound, "Agent")) {
    agent <- bound$agent
    cleanup <- bound$cleanup %||% NULL
    if (!is.null(cleanup) && !is.function(cleanup)) {
      job_abort(
        "The Agent job binder cleanup must be a function.",
        "job_invalid"
      )
    }
  }
  if (!inherits(agent, "Agent") || inherits(agent, "LeadAgent")) {
    job_abort(
      "The Agent job binder must return an ordinary Agent.",
      "job_invalid"
    )
  }
  list(agent = agent, cleanup = cleanup)
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
    return(job_job(
      path,
      record,
      approval_store_envelope(path),
      job_control_read(path, record)
    ))
  }
  if (identical(record$status, "queued") && !is.null(decision)) {
    job_abort(
      "An approval decision requires a job in approval_pending status.",
      "job_invalid"
    )
  }
  if (isTRUE(control$requested)) {
    record$error <- list(
      class = "job_cancelled",
      message = "The host requested cancellation before binding.",
      reason = job_safe_string(control$reason %||% "cancelled")
    )
    record <- job_transition(
      record,
      "cancelled",
      control$reason %||% "cancelled"
    )
    record <- job_release_reservation(
      record,
      release = TRUE,
      reason = control$reason %||% "cancelled"
    )
    record["pending_approval"] <- list(NULL)
    record <- job_record_write(path, record, lock)
    job_control_write(
      path,
      record,
      "cancelled",
      control$reason %||% "cancelled"
    )
    return(job_job(
      path,
      record,
      approval_store_envelope(path),
      job_control_read(path, record)
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

  bound_error <- tryCatch(
    {
      supplied <- bind(job_job(
        path,
        bind_record,
        approval_store_envelope(path),
        job_control_read(path, bind_record)
      ))
      worker$agent <- if (is.list(supplied) && !inherits(supplied, "Agent")) {
        supplied$agent
      } else {
        supplied
      }
      worker$cleanup <- if (is.list(supplied) && !inherits(supplied, "Agent")) {
        supplied$cleanup %||% NULL
      } else {
        NULL
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
      job_bound_agent(supplied)
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
      worker$record <- job_record_write(path, worker$record, lock)
      job_worker_start_poller(worker)
      NULL
    },
    error = identity
  )
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
    return(job_job(
      path,
      record,
      approval_store_envelope(path),
      job_control_read(path, record)
    ))
  }

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
        worker$record <- job_record_write(path, candidate, lock)
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
    tryCatch(worker$agent$pending_approval(), error = function(error) {
      NULL
    })
  }
  pending_path <- if (!is.null(pending)) job_pending_path(pending) else NULL
  if (
    is.null(pending_path) &&
      !is.null(run_error) &&
      job_is_pending_error(run_error)
  ) {
    pending_path <- run_error$path %||% NULL
  }

  worker$poller_active <- FALSE
  cleanup_error <- tryCatch(
    job_worker_cleanup(worker),
    error = identity
  )
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
      worker$record <- job_record_write(path, worker$record, lock)
    }
    return(job_job(
      path,
      worker$record,
      approval_store_envelope(path),
      job_control_read(path, worker$record)
    ))
  }

  record <- worker$record
  control <- job_control_read(path, record)
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
        worker$record <- job_record_write(path, record, lock)
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
  job_job(
    path,
    worker$record,
    approval_store_envelope(path),
    job_control_read(path, worker$record)
  )
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
    return(job_job(
      path,
      record,
      loaded$envelope,
      control
    ))
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
    return(job_job(
      path,
      record,
      loaded$envelope,
      control
    ))
  }
  if (record$status %in% c("queued", "approval_pending")) {
    record$error <- list(
      class = "job_cancelled",
      message = "The host requested cancellation.",
      reason = reason
    )
    record <- job_transition(record, "cancelled", reason)
    record <- job_release_reservation(record, release = TRUE, reason = reason)
    record["pending_approval"] <- list(NULL)
    record <- job_record_write(path, record, execution_lock)
    control <- job_control_acknowledge(path, record, reason)
    return(job_job(
      path,
      record,
      approval_store_envelope(path),
      control
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
  job_job(
    path,
    record,
    approval_store_envelope(path),
    control
  )
}
