#' @include value-properties.R callback-result.R run-usage.R
NULL

approval_abort <- function(
  message,
  class = NULL,
  ...,
  .envir = parent.frame()
) {
  abort_deputy(
    message,
    class = c(class, "approval_error"),
    ...,
    .envir = .envir
  )
}

#' Request a durable tool approval
#'
#' Return this from a [Permissions] `can_use_tool` callback to suspend before
#' execution. The Agent must have an `approval_dir`. Resumable tools must be
#' registered with `convert = FALSE`; their functions accept raw JSON arguments.
#' No approval is granted by constructing this value.
#' @param reason One non-missing string explaining the pending decision.
#' @return A read-only S7 permission result.
#' @seealso [approval_read()], [Agent]
#' @export
PermissionResultPending <- S7::new_class(
  "PermissionResultPending",
  parent = PermissionResult,
  package = "deputy",
  properties = list(
    decision = readonly_property("decision", S7::class_character),
    reason = readonly_property("reason", S7::class_character)
  ),
  constructor = function(reason = "Approval required") {
    value <- S7::new_object(
      S7::S7_object(),
      decision = "pending",
      reason = validate_callback_text(reason, "reason", optional = FALSE)
    )
    freeze_value(value)
  }
)

#' Inspect a durable approval continuation
#'
#' @description
#' Read an approval directory without loading a Chat or running any tools.
#' Snapshots are read-only S7 values; they are inspection records, not grants.
#' Use `agent$resume_approval(path, decision = "approve")` or `"deny"` to
#' consume a pending decision. Edited inputs are supplied through `tool_input`.
#'
#' Only `pending` records can resume. An `executing` record may have produced
#' effects; an interrupted `resuming` or `continuing` record also requires host
#' reconciliation. These records cannot automatically retry. OS locks prevent
#' concurrent consumers and are released when the owning process exits.
#'
#' Approval directories contain private conversation and tool data. The host
#' owns storage, access control, retention, and associations with its conversation
#' store. They never contain serialized tools, callbacks, or Chat clients.
#' @param path Path to an approval directory returned on the `approval` event.
#' @return An [ApprovalContinuation] inspection value.
#' @export
approval_read <- function(path) {
  record <- approval_store_read(path)
  validate_approval_record(record)
  record$source$path <- approval_store_path(path)
  approval_snapshot(record)
}

#' Durable approval inspection value
#'
#' @description
#' A read-only view of a durable approval. Normally obtained with [approval_read()].
#' Constructing a value does not persist it or authorize execution.
#' @param id Stable approval identifier.
#' @param status Pending, executing, or terminal state.
#' @param request Named record containing tool name, inputs, and reason.
#' @param decision Recorded host decision, or NULL.
#' @param context Canonical host run context.
#' @param usage Observed [AgentUsage], including work before suspension.
#' @param usage_limits Governing [UsageLimits].
#' @param budget_ceiling Original Agent budget ceiling for explicit escalation.
#' @param permissions Saved static permission ceiling and callback requirement.
#' @param effects Execution journal entries.
#' @param source Session, Agent, and source-run correlation.
#' @return An `ApprovalContinuation` S7 value.
#' @export
ApprovalContinuation <- S7::new_class(
  "ApprovalContinuation",
  package = "deputy",
  properties = list(
    id = readonly_property("id", S7::class_character),
    status = readonly_property("status", S7::class_character),
    request = readonly_property("request", S7::class_list),
    decision = readonly_property(
      "decision",
      S7::new_union(S7::class_list, NULL)
    ),
    context = readonly_property("context", S7::class_list),
    usage = readonly_property("usage", AgentUsage),
    usage_limits = readonly_property("usage_limits", UsageLimits),
    budget_ceiling = readonly_property("budget_ceiling", UsageLimits),
    permissions = readonly_property("permissions", S7::class_list),
    effects = readonly_property("effects", S7::class_list),
    source = readonly_property("source", S7::class_list)
  ),
  constructor = function(
    id,
    status,
    request,
    decision = NULL,
    context = list(),
    usage = AgentUsage(),
    usage_limits = UsageLimits(),
    budget_ceiling = UsageLimits(),
    permissions = list(),
    effects = list(),
    source = list()
  ) {
    if (!is_nonempty_string(id) || !is_nonempty_string(status)) {
      approval_abort("Approval id and status must be non-empty strings.")
    }
    for (value in list(request, decision, permissions, effects, source)) {
      approval_portable(value)
    }
    value <- S7::new_object(
      S7::S7_object(),
      id = id,
      status = status,
      request = request,
      decision = decision,
      context = normalize_run_context(context),
      usage = usage,
      usage_limits = usage_limits,
      budget_ceiling = budget_ceiling,
      permissions = permissions,
      effects = effects,
      source = source
    )
    freeze_value(value)
  }
)
local({
  S7::method(`$`, ApprovalContinuation) <- function(x, name) S7::prop(x, name)
})
S7::method(print, ApprovalContinuation) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<ApprovalContinuation: {x@id}>")
    cli::cli_text("status: {x@status}")
    cli::cli_text("tool: {x@request$name}")
    cli::cli_text("reason: {x@request$reason}")
  }))
  invisible(x)
}

# Reject process-local state before writing a portable control record.
approval_portable <- function(value, depth = 0L, path = "record") {
  if (depth > 100L) {
    approval_abort("Approval data exceeds the nesting limit.")
  }
  if (is.null(value)) {
    return(invisible(value))
  }
  if (
    inherits(value, "condition") ||
      is.function(value) ||
      is.environment(value) ||
      typeof(value) %in% c("externalptr", "weakref") ||
      S7::S7_inherits(value)
  ) {
    approval_abort(
      "Approval data must not contain runtime objects or conditions."
    )
  }
  if (is.list(value) && !is.object(value)) {
    for (i in seq_along(value)) {
      label <- names(value)[i] %||% as.character(i)
      approval_portable(value[[i]], depth + 1L, paste0(path, "$", label))
    }
  } else if (
    !is.atomic(value) ||
      (is.object(value) &&
        !inherits(value, c("json", "POSIXct")))
  ) {
    approval_abort(
      "Approval data at {.val {path}} must contain only portable values; found {.val {class(value)}}."
    )
  }
  invisible(value)
}

approval_record_content <- function(value) {
  if (
    inherits(value, "ellmer::ContentToolResult") &&
      inherits(value@error, "condition")
  ) {
    value@error <- conditionMessage(value@error)
  }
  record <- approval_content_record_values(ellmer::contents_record(value))
  approval_portable(record)
  record
}

approval_record_turns <- function(turns) {
  lapply(turns, function(turn) {
    # Conditions nested in a tool-result turn are converted to text before
    # recording; provider HTTP condition objects never enter the store.
    turn@contents <- lapply(turn@contents, function(content) {
      if (
        inherits(content, "ellmer::ContentToolResult") &&
          inherits(content@error, "condition")
      ) {
        content@error <- conditionMessage(content@error)
      }
      content
    })
    approval_record_content(turn)
  })
}

approval_replay_turns <- function(records, tools) {
  lapply(records, ellmer::contents_replay, tools = tools)
}

approval_result_content <- function(request, value = NULL, error = NULL) {
  if (inherits(error, "condition")) {
    error <- conditionMessage(error)
  }
  if (S7::S7_inherits(value)) {
    value <- approval_record_content(value)
  }
  if (
    is.list(value) &&
      length(value) &&
      all(vapply(value, S7::S7_inherits, logical(1)))
  ) {
    value <- lapply(value, approval_record_content)
  }
  if (is.atomic(value) && !is.character(value)) {
    value <- as.character(jsonlite::toJSON(value, auto_unbox = TRUE))
  }
  if (is.character(value)) {
    value <- paste(value, collapse = "\n")
  }
  approval_portable(value)
  ellmer::contents_replay(list(
    version = 1,
    class = "ellmer::ContentToolResult",
    props = list(
      value = value,
      error = error,
      extra = list(),
      request = approval_record_content(request)
    )
  ))
}

approval_tool_fingerprint <- function(tool) {
  source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
  if (!inherits(source, "ellmer::ToolDef")) {
    approval_abort("Approval requires a function tool.")
  }
  digest::digest(
    list(
      name = source@name,
      description = source@description,
      arguments = approval_type_record(source@arguments),
      convert = source@convert,
      formals = deparse(formals(source), width.cutoff = 500L),
      body = deparse(body(source), width.cutoff = 500L),
      metadata = tool_metadata(source)
    ),
    algo = "sha256"
  )
}

approval_policy_record <- function(policy) {
  record <- S7::props(policy)
  record$callback_required <- !is.null(record$can_use_tool)
  record$can_use_tool <- NULL
  record
}

approval_static_policy <- function(record) {
  record$callback_required <- NULL
  do.call(Permissions, record)
}

validate_approval_record <- function(record) {
  approval_portable(record)
  approval_store_record(record)
  required <- c(
    "schema_version",
    "id",
    "status",
    "pending",
    "effects",
    "source",
    "context",
    "permissions",
    "usage",
    "usage_limits",
    "budget_ceiling",
    "session",
    "tools",
    "working_dir"
  )
  if (
    !is.list(record) ||
      !all(required %in% names(record)) ||
      !identical(record$schema_version, 1L) ||
      !is_nonempty_string(record$id) ||
      !record$status %in%
        c(
          "pending",
          "resuming",
          "executing",
          "continuing",
          "completed",
          "stopped",
          "indeterminate"
        )
  ) {
    approval_abort("Invalid or unsupported approval record.")
  }
  if (
    !is.list(record$pending) ||
      !is.list(record$effects) ||
      !is.list(record$source) ||
      !is.list(record$session) ||
      !is.list(record$tools) ||
      !identical(record$pending$request$class, "ellmer::ContentToolRequest")
  ) {
    approval_abort("Approval record is missing its tool or conversation state.")
  }
  pending <- record$pending
  request <- pending$request$props
  if (
    !is_nonempty_string(request$id) ||
      !is_nonempty_string(request$name) ||
      !is_nonempty_string(pending$reason) ||
      !is_nonempty_string(pending$fingerprint) ||
      !identical(record$tools[[request$name]], pending$fingerprint) ||
      !pending$kind %in% c("tool", "budget")
  ) {
    approval_abort("Approval has invalid pending-operation identity.")
  }
  approval_validate_inputs(request$arguments)
  for (name in c("session_id", "agent_id", "run_id")) {
    if (!is_nonempty_string(record$source[[name]])) {
      approval_abort("Approval requires stable source correlation.")
    }
  }
  if (
    !identical(record$source$session_id, record$session$metadata$session_id) ||
      !identical(record$source$agent_id, record$session$metadata$agent_id) ||
      !identical(record$context, record$session$run_context)
  ) {
    approval_abort("Approval session and source correlation disagree.")
  }
  turns <- record$session$turns
  if (
    !is.list(turns) ||
      !length(turns) ||
      !identical(tail(turns, 1L)[[1L]]$class, "ellmer::AssistantTurn")
  ) {
    approval_abort("Approval requires its complete assistant request turn.")
  }
  requests <- Filter(
    function(item) identical(item$class, "ellmer::ContentToolRequest"),
    tail(turns, 1L)[[1L]]$props$contents
  )
  ids <- vapply(requests, function(item) item$props$id, character(1))
  if (
    anyNA(ids) ||
      !all(nzchar(ids)) ||
      anyDuplicated(ids) ||
      !request$id %in% ids ||
      !identical(requests[[match(request$id, ids)]], pending$request)
  ) {
    approval_abort("Approval pending request does not match its saved turn.")
  }
  normalize_run_context(record$context)
  approval_static_policy(record$permissions)
  if (!is.list(record$ceilings) || !length(record$ceilings)) {
    approval_abort("Approval requires its saved authority ceilings.")
  }
  invisible(lapply(record$ceilings, approval_static_policy))
  if (
    is.null(names(record$tools)) ||
      anyNA(names(record$tools)) ||
      !all(nzchar(names(record$tools))) ||
      anyDuplicated(names(record$tools)) ||
      !all(vapply(record$tools, is_nonempty_string, logical(1)))
  ) {
    approval_abort("Approval requires a uniquely named tool registry.")
  }
  for (entry in record$effects) {
    if (
      !is.list(entry) ||
        !is_nonempty_string(entry$signature) ||
        !is.logical(entry$executed) ||
        length(entry$executed) != 1L ||
        is.na(entry$executed) ||
        !is_nonempty_string(entry$status) ||
        !entry$status %in% c("executing", "completed", "failed")
    ) {
      approval_abort("Approval has an invalid effect journal.")
    }
    if (
      identical(record$status, "pending") &&
        identical(entry$status, "executing")
    ) {
      approval_abort("A pending approval contains an indeterminate effect.")
    }
  }
  approval_usage(record$usage)
  do.call(UsageLimits, record$usage_limits)
  do.call(UsageLimits, record$budget_ceiling)
  invisible(record)
}

approval_snapshot <- function(record) {
  ApprovalContinuation(
    record$id,
    record$status,
    request = list(
      tool_call_id = record$pending$request$props$id,
      name = record$pending$request$props$name,
      tool_input = record$pending$request$props$arguments,
      reason = record$pending$reason,
      kind = record$pending$kind
    ),
    decision = record$decision,
    context = record$context,
    usage = approval_usage(record$usage),
    usage_limits = do.call(UsageLimits, record$usage_limits),
    budget_ceiling = do.call(UsageLimits, record$budget_ceiling),
    permissions = record$permissions,
    effects = record$effects,
    source = record$source
  )
}

# Type properties are public S7 metadata, not part of ellmer content replay.
approval_type_record <- function(value) {
  if (S7::S7_inherits(value)) {
    return(list(
      class = class(value)[[1L]],
      properties = lapply(S7::props(value), approval_type_record)
    ))
  }
  if (is.list(value)) {
    return(lapply(value, approval_type_record))
  }
  value
}

intersect_usage_limits <- function(left, right) {
  fields <- S7::props(left)
  for (name in setdiff(names(fields), "on_exceed")) {
    values <- c(S7::prop(left, name), S7::prop(right, name))
    fields[name] <- list(if (length(values)) min(values) else NULL)
  }
  fields$on_exceed <- if ("error" %in% c(left$on_exceed, right$on_exceed)) {
    "error"
  } else {
    "stop"
  }
  do.call(UsageLimits, fields)
}

# ellmer records keep their display-only currency class on numeric costs.
approval_content_record_values <- function(value) {
  if (inherits(value, "ellmer_dollars")) {
    return(as.numeric(value))
  }
  if (is.list(value) && !is.object(value)) {
    return(lapply(value, approval_content_record_values))
  }
  value
}

approval_usage <- function(record) {
  record$total_tokens <- NULL
  do.call(AgentUsage, record)
}
