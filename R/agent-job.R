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
  cancelled = character(),
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
  value <- enc2utf8(value)
  if (nchar(value, type = "bytes") > max_bytes) {
    value <- substr(value, 1L, max_bytes)
  }
  value
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
  message <- tryCatch(conditionMessage(error), error = function(e) "job error")
  job_bound_value(
    list(
      class = unique(utils::head(classes, 4L)),
      message = job_safe_string(message),
      reason = job_safe_string(error$reason),
      phase = job_safe_string(error$phase)
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
    fields <- S7::props(pending)
    for (field in c("usage", "usage_limits", "budget_ceiling")) {
      if (S7::S7_inherits(fields[[field]], AgentUsage)) {
        fields[[field]] <- S7::props(fields[[field]])
      } else if (S7::S7_inherits(fields[[field]], UsageLimits)) {
        fields[[field]] <- S7::props(fields[[field]])
      }
    }
    fields <- job_safe_value(fields, max_bytes = 1024L * 1024L)
    if (!is.null(fields$source$path)) {
      fields$path <- job_safe_string(fields$source$path, 4096L)
    }
    return(fields)
  }
  job_bound_value(job_safe_value(pending), 1024L * 1024L)
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

job_record_write <- function(path, record, lock) {
  job_record_validate(record)
  envelope <- approval_store_envelope(path)
  approval_store_write(path, record, lock, max_bytes = envelope$max_bytes)
  invisible(record)
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

job_merge_snapshot <- function(record, snapshot, event = NULL) {
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
  snapshot <- job_safe_value(snapshot, max_bytes = 4L * 1024L * 1024L)
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
  record$runtime <- job_bound_value(runtime, 4L * 1024L * 1024L)
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
  if ("pending_approval" %in% names(snapshot)) {
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

job_mark_recovery <- function(path, record, lock, reason) {
  record$cleanup <- record$cleanup %||%
    list(
      owner = "unknown",
      status = "unknown",
      required = TRUE,
      attempts = 0L
    )
  record$cleanup$status <- "unknown"
  record$cleanup$required <- TRUE
  record$cleanup$reason <- job_safe_string(reason)
  record <- job_release_reservation(record, release = FALSE, reason = reason)
  record <- job_transition(record, "indeterminate", reason)
  record$error <- list(
    class = "job_recovery",
    message = "The previous worker ended before durable settlement.",
    reason = job_safe_string(reason)
  )
  job_record_write(path, record, lock)
  try(job_control_write(path, record, "acknowledged", reason), silent = TRUE)
  record
}

#' AgentJob read-only durable inspection
#'
#' AgentJob values are returned by job_read and job_run. They contain portable
#' lifecycle and outcome data, never Agents, Chats, tools, callbacks,
#' credentials, connections, promises or cleanup closures.
#' @param path Committed job directory.
#' @param revision Immutable record revision.
#' @param id Stable job identifier.
#' @param status Durable lifecycle status.
#' @param task Submitted task text.
#' @param owner_id Host owner identifier.
#' @param definition_revision Host Agent-definition revision.
#' @param context_revision Host source-context revision.
#' @param usage_limits Reserved usage ceiling.
#' @param usage Observed usage.
#' @param associations Portable host associations.
#' @param manifest Portable Agent and graph manifest.
#' @param allocation Original allocation reservation.
#' @param reservations Durable reservation state.
#' @param pending_approval Persisted approval inspection, or NULL.
#' @param pending_decision Persisted decision receipt, or NULL.
#' @param transitions Bounded lifecycle transitions.
#' @param events Bounded runtime events.
#' @param result Portable terminal result summary, or NULL.
#' @param error Portable terminal error summary, or NULL.
#' @param cleanup Cleanup ownership and ledger state.
#' @param runtime Portable runtime snapshot.
#' @param graph Portable graph snapshot, or NULL.
#' @param source Portable correlation metadata.
#' @param control Portable independent cancellation state.
#'
#' @return A read-only S7 AgentJob value.
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

#' Create a durable host-owned Agent job
#'
#' The Agent is inspected into a portable manifest. It is never serialized;
#' the host supplies a binder again when [job_run()] consumes the job.
#'
#' @param directory Parent directory owned by the host.
#' @param agent Idle ordinary [Agent] whose exact manifest is retained.
#' @param task Non-empty task text.
#' @param owner_id Host owner or tenant identifier.
#' @param definition_revision Host revision for the Agent definition.
#' @param context_revision Host revision for source context.
#' @param usage_limits [UsageLimits] reserved for this job.
#' @param associations Portable host conversation associations.
#' @param max_bytes Maximum bytes for each immutable store.
#' @return The committed job directory.
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
  path <- approval_store_create(directory, record, max_bytes = max_bytes)
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

#' Read a durable Agent job without binding or executing it
#'
#' @param path Committed directory returned by [job_create()].
#' @return A read-only [AgentJob] inspection value.
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
  record <- job_merge_snapshot(worker$record, snapshot, event)
  worker$record <- record
  if (job_control_requested(worker$path, record)) {
    reason <- job_control_read(
      worker$path,
      record
    )$reason %||%
      "cancelled"
    executing <- job_record_has_executing_effect(record)
    status <- if (executing) "indeterminate" else "cancelled"
    if (identical(status, "indeterminate")) {
      record$cleanup$status <- "unknown"
      record$cleanup$required <- TRUE
      record$cleanup$reason <- "worker interrupted during an effect"
      record <- job_release_reservation(
        record,
        release = FALSE,
        reason = reason
      )
    } else {
      record <- job_release_reservation(record, release = TRUE, reason = reason)
    }
    record$error <- list(
      class = "job_cancelled",
      message = "The host requested cancellation.",
      reason = job_safe_string(reason)
    )
    record <- job_transition(record, status, reason)
    worker$record <- record
    job_record_write(worker$path, record, worker$lock)
    worker$terminal <- status
    try(
      job_control_write(worker$path, record, status, reason),
      silent = TRUE
    )
    job_abort(
      "The Agent job was cancelled.",
      class = "job_cancelled",
      reason = reason
    )
  }
  job_record_write(worker$path, record, worker$lock)
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

job_worker_cleanup <- function(worker) {
  record <- worker$record
  detach_error <- NULL
  if (!is.null(worker$detach)) {
    detach_error <- tryCatch(
      {
        worker$detach()
        NULL
      },
      error = identity
    )
    worker$detach <- NULL
    record$runtime$attached <- FALSE
    record$runtime$detached_at <- as.numeric(Sys.time())
    if (!is.null(detach_error)) {
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
        job_record_write(worker$path, record, worker$lock)
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
      record$cleanup$status <- "completed"
      record$cleanup$completed_at <- as.numeric(Sys.time())
    } else {
      record$cleanup$status <- "failed"
      record$cleanup$required <- TRUE
      record$cleanup$error <- job_error_record(cleanup_error)
    }
    if (is.null(cleanup_error)) {
      record$cleanup$status <- "completed"
      record$cleanup$completed_at <- as.numeric(Sys.time())
    }
    post_error <- tryCatch(
      {
        job_record_write(worker$path, record, worker$lock)
        NULL
      },
      error = identity
    )
    cleanup_error <- cleanup_error %||% ledger_error %||% post_error
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
    if (
      !identical(record$cleanup$status, "completed") &&
        !identical(record$cleanup$status, "failed")
    ) {
      record$cleanup$status <- "unknown"
      record$cleanup$required <- TRUE
    }
  } else {
    record <- job_release_reservation(record, release = TRUE, reason = reason)
  }
  worker$record <- record
  job_record_write(worker$path, record, worker$lock)
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

#' Consume one durable Agent job
#'
#' The host controls authorization, Agent reconstruction, and resource
#' cleanup. The execution lock is held from the durable running transition
#' through runtime detachment and terminal persistence.
#'
#' @param path Committed directory returned by [job_create()].
#' @param bind Function receiving an [AgentJob] and returning an Agent or a
#'   list with fields agent and cleanup.
#' @param authorize Function receiving an [AgentJob] and returning the exact
#'   identity receipt with job_id, owner_id, definition_revision, and
#'   context_revision.
#' @param decision Approval decision, approve or deny, for a pending job.
#' @param tool_input Optional edited raw input for a pending approval.
#' @return A read-only [AgentJob] inspection value.
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
  if (identical(record$status, "approval_pending") && is.null(decision)) {
    return(job_job(path, record, loaded$envelope, control))
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
    job_record_write(path, record, lock)
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
  record$runtime$attached <- FALSE
  job_record_write(path, record, lock)

  worker <- new.env(parent = emptyenv())
  worker$path <- path
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
      job_record_write(path, worker$record, lock)
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
    record <- worker$record
    if (!identical(record$status, "failed")) {
      record <- job_transition(record, "failed", "Agent job binding failed")
    }
    record$error <- job_error_record(bound_error)
    record <- job_release_reservation(
      record,
      release = TRUE,
      reason = "Agent job binding failed"
    )
    worker$record <- record
    job_record_write(path, record, lock)
    try(
      job_control_write(path, record, "acknowledged", "binding failed"),
      silent = TRUE
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
  if (!is.null(checkpoint_error) && is.null(run_error)) {
    run_error <- checkpoint_error
  }

  snapshot_error <- tryCatch(
    {
      snapshot <- job_runtime_snapshot(worker$agent)
      worker$record <- job_merge_snapshot(worker$record, snapshot)
      job_record_write(path, worker$record, lock)
      NULL
    },
    error = identity
  )
  if (!is.null(snapshot_error) && is.null(run_error)) {
    run_error <- snapshot_error
  }
  pending <- tryCatch(worker$agent$pending_approval(), error = function(error) {
    NULL
  })
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
  if (!is.null(cleanup_error) && is.null(run_error)) {
    run_error <- cleanup_error
  }
  worker$record$runtime$attached <- FALSE
  worker$record$runtime$detached_at <- as.numeric(Sys.time())
  if (!is.null(worker$terminal)) {
    job_record_write(path, worker$record, lock)
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
  persistence_failure <- !is.null(checkpoint_error) ||
    !is.null(snapshot_error) ||
    inherits(run_error, "deputy_job_persistence") ||
    inherits(cleanup_error, "deputy_job_persistence")
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
    reason <- control$reason %||%
      run_error$reason %||%
      "cancelled"
    worker$record <- record
    job_worker_finish(
      worker,
      status,
      result = result,
      error = run_error %||% simpleError("The Agent job was cancelled."),
      reason = reason
    )
  } else if (
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
    worker$record <- record
    job_record_write(path, record, lock)
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

#' Request durable cooperative cancellation of an Agent job
#'
#' The small control store is independent from the execution store, so a
#' cancellation request can be recorded while a worker owns the execution
#' lock. The worker observes it at runtime checkpoints and through its bounded
#' interrupt poller.
#'
#' @param path Committed directory returned by [job_create()].
#' @param authorize Function returning the exact job identity receipt.
#' @param reason Host cancellation reason.
#' @return A read-only [AgentJob] inspection value.
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
    job_record_write(path, record, execution_lock)
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
