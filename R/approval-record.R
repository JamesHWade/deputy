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

#' Pause a tool call for approval
#'
#' Return this from a `can_use_tool` callback (see [Permissions]) to stop the
#' run before the tool executes and save the pending call to disk. Approve or
#' deny it later, possibly from another R process, with
#' `agent$resume_approval()`; [approval_read()] shows what is waiting.
#'
#' The agent needs an `approval_dir`, and the tool must be registered with
#' `convert = FALSE`, so its function receives the raw JSON arguments. Tool
#' results should be strings, JSON from `jsonlite::toJSON()`, or ellmer content
#' objects. Inputs or results shaped like a list with `version`, `class` and
#' `props` fields are rejected, because ellmer would read them back as
#' serialized objects.
#' @param reason Why the call needs approval, as one non-empty string.
#' @return A `PermissionResultPending` object.
#' @seealso `vignette("approvals")`, [approval_read()], [Agent]
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
    if (!is_nonempty_string(reason)) {
      approval_abort("{.arg reason} must be one non-empty string.")
    }
    value <- S7::new_object(
      S7::S7_object(),
      decision = "pending",
      reason = reason
    )
    freeze_value(value)
  }
)

#' Read a pending approval
#'
#' @description
#' Reads an approval directory and returns the paused tool call, its status
#' and the usage so far, without loading a chat or running tools. To act on a
#' pending approval, call `agent$resume_approval(path, "approve")` or
#' `"deny"`, passing any edited inputs as `tool_input`.
#'
#' Only a `"pending"` approval can be resumed, and only once. A record
#' interrupted while `"resuming"`, `"executing"` or `"continuing"` can't be
#' resumed or retried: its tool may already have run, so check the effects
#' yourself. File locks stop two processes resuming the same approval at
#' once, but nothing guarantees that a tool runs exactly once.
#'
#' Approval directories hold the conversation and tool inputs, so keep them
#' private; access control and clean-up are up to you. They never contain
#' tools, callbacks or chat clients.
#' @param path Path to an approval directory, as given in the `approval` event.
#' @return An [ApprovalContinuation].
#' @export
approval_read <- function(path) {
  record <- approval_store_read(path)
  validate_approval_record(record)
  record$source$path <- approval_store_path(path)
  approval_snapshot(record)
}

#' Pending approval record
#'
#' @description
#' A read-only snapshot of a saved approval, returned by [approval_read()] and
#' `agent$pending_approval()`. Read fields with `$`. You rarely need to create
#' one yourself; doing so doesn't save it or approve anything.
#' @param id Approval ID.
#' @param status One of `"pending"`, `"resuming"`, `"executing"`,
#'   `"continuing"`, `"completed"`, `"stopped"` or `"indeterminate"`.
#' @param request List describing the paused call: `tool_call_id`, `name`,
#'   `tool_input`, `reason`, and `kind` (`"tool"`, or `"budget"` when a usage
#'   limit caused the pause).
#' @param decision The recorded decision (`decision` and `tool_input`), or
#'   `NULL` if there is none yet.
#' @param context The run's `run_context`.
#' @param usage [AgentUsage] so far, including work before the pause.
#' @param usage_limits [UsageLimits] of the paused run. Resuming reuses them
#'   unless you pass others.
#' @param budget_ceiling The agent's [UsageLimits] from the original run.
#'   Limits passed to `resume_approval()` can't go beyond these or the agent's
#'   current limits.
#' @param permissions The saved permission policy, as a list. Resumed tool
#'   calls must be allowed by both it and the agent's current policy.
#'   `callback_required` says whether `can_use_tool` must be set again before
#'   resuming.
#' @param effects Log of tool calls the run has executed, with their status.
#' @param source IDs of the session, agent and run that paused. [approval_read()]
#'   adds `path`, the approval directory.
#' @return An `ApprovalContinuation` object.
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
approval_portable <- function(
  value,
  depth = 0L,
  path = "record",
  allow_classed = FALSE
) {
  if (depth > 100L) {
    approval_abort("Approval data exceeds the nesting limit.")
  }
  if (is.null(value)) {
    return(invisible(value))
  }
  if (
    inherits(value, c("condition", "connection")) ||
      is.function(value) ||
      is.environment(value) ||
      typeof(value) %in% c("externalptr", "weakref") ||
      S7::S7_inherits(value) ||
      isS4(value)
  ) {
    approval_abort(
      "Approval data must not contain runtime objects or conditions."
    )
  }
  if (is.list(value) && (!is.object(value) || allow_classed)) {
    elements <- if (is.object(value)) unclass(value) else value
    for (i in seq_along(elements)) {
      label <- names(elements)[i] %||% as.character(i)
      approval_portable(
        elements[[i]],
        depth + 1L,
        paste0(path, "$", label),
        allow_classed
      )
    }
  } else if (
    !is.atomic(value) ||
      (is.object(value) &&
        !allow_classed &&
        !inherits(value, c("json", "POSIXct")))
  ) {
    approval_abort(
      "Approval data at {.val {path}} must contain only portable values; found {.val {class(value)}}."
    )
  }
  # Classed session data retain their RDS representation, including attributes.
  # Inspect attributes too so an otherwise plain value cannot hide a callback
  # or runtime environment in metadata.
  for (attribute in attributes(value)) {
    approval_portable(
      attribute,
      depth + 1L,
      paste0(path, " attributes"),
      allow_classed
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
  approval_check_content_value(value)
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
  approval_check_content_value(value)
  if (inherits(error, "condition")) {
    error <- conditionMessage(error)
  }
  if (is.null(error) && inherits(value, "ellmer::ContentToolResult")) {
    value@request <- request
    return(ellmer::contents_replay(approval_record_content(value)))
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
    value <- jsonlite::toJSON(
      value,
      auto_unbox = TRUE,
      null = "null",
      na = "null"
    )
  }
  if (is.character(value) && !inherits(value, "json")) {
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
  if (is.list(record) && !is.object(record)) {
    control <- record
    control$session <- NULL
    approval_portable(control)
    approval_portable(record$session, path = "session", allow_classed = TRUE)
  } else {
    approval_portable(record)
  }
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

# ellmer replay treats record-shaped lists as constructors. Ordinary JSON data
# must not accidentally become an S7 object while restoring a tool request.
approval_no_replay_tags <- function(value) {
  if (!is.list(value) || S7::S7_inherits(value)) {
    return(invisible(NULL))
  }
  if (all(c("version", "class", "props") %in% names(value))) {
    approval_abort(c(
      "Approval JSON data resembles serialized content.",
      "i" = "Record-shaped raw inputs cannot be resumed. Encode structured tool outputs with jsonlite::toJSON()."
    ))
  }
  for (item in value) {
    approval_no_replay_tags(item)
  }
  invisible(NULL)
}

approval_check_content_value <- function(value) {
  if (S7::S7_inherits(value)) {
    properties <- S7::props(value)
    if (inherits(value, "ellmer::ContentToolRequest")) {
      properties$tool <- NULL
    }
    for (property in properties) {
      approval_check_content_value(property)
    }
  } else if (
    is.list(value) &&
      length(value) &&
      all(vapply(value, S7::S7_inherits, logical(1)))
  ) {
    for (item in value) {
      approval_check_content_value(item)
    }
  } else {
    approval_no_replay_tags(value)
  }
  invisible(NULL)
}
