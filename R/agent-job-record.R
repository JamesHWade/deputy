#' @include value-properties.R approval-store.R approval-record.R run-usage.R agent-result.R
NULL

# Durable host-owned Agent job records, bounded evidence sanitization, state
# transitions, and the read-only AgentJob snapshot contract.

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

job_fits_bound <- function(value, max_bytes) {
  isTRUE(tryCatch(
    {
      approval_portable(value)
      if (!observation_payload_fits(value, max_bytes)) {
        FALSE
      } else {
        length(serialize(value, NULL, version = 3)) <= max_bytes
      }
    },
    error = function(error) FALSE
  ))
}

job_bound_value <- function(value, max_bytes) {
  if (job_fits_bound(value, max_bytes)) {
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
    if (!job_fits_bound(value, max_bytes)) {
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

job_ring_append <- function(items, item, dropped, max_len) {
  items <- c(items %||% list(), list(item))
  dropped <- dropped %||% 0L
  if (length(items) > max_len) {
    dropped <- dropped + length(items) - max_len
    items <- tail(items, max_len)
  }
  list(items = items, dropped = as.integer(dropped))
}

job_event_append <- function(record, event) {
  ring <- job_ring_append(
    record$events,
    job_safe_event(event),
    record$event_dropped,
    job_max_events
  )
  record$events <- ring$items
  record$event_dropped <- ring$dropped
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
  ring <- job_ring_append(
    record$transitions,
    transition,
    record$transition_dropped,
    job_max_transitions
  )
  record$status <- status
  record$transitions <- ring$items
  record$transition_dropped <- ring$dropped
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

register_dollar_prop(AgentJob)

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

job_snapshot <- function(path, record, missing_control_ok = FALSE) {
  job_job(
    path,
    record,
    approval_store_envelope(path),
    job_control_read(path, record, missing_ok = missing_control_ok)
  )
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
