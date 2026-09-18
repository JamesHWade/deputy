# Keep rejected input inspectable without retaining arbitrary objects or unbounded
# task text in lifecycle events. Validation follows admission, before dispatch.
delegation_task_label <- function(task, max_bytes) {
  tryCatch(
    {
      text <- if (S7::S7_inherits(task, DelegationInput)) task$task else task
      text <- delegation_text(text, "task")
      if (nchar(text, type = "bytes") > max_bytes) {
        return("<oversized delegation input>")
      }
      text
    },
    error = function(error) {
      if (
        inherits(error, "deputy_delegation_input_error") &&
          identical(error$reason, "oversized")
      ) {
        "<oversized delegation input>"
      } else {
        "<invalid delegation input>"
      }
    }
  )
}

# One admitted record per delegation, independent of child completion order.
lead_admit_delegation <- function(lead, definition, task, correlation) {
  private <- lead$.__enclos_env__$private
  id <- correlation$delegation_id
  private$subagent_runs[[id]] <- list(
    agent_name = definition$name,
    agent_id = NULL,
    parent_agent_id = correlation$parent_agent_id,
    task = delegation_task_label(task, private$delegation_max_bytes),
    session_id = NULL,
    run_id = NULL,
    parent_run_id = correlation$parent_run_id,
    delegation_id = id,
    tool_call_id = correlation$tool_call_id,
    run_context = correlation$run_context,
    admitted_at = Sys.time(),
    started_at = as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC"),
    completed_at = as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC"),
    status = "queued",
    stop_reason = NULL,
    error = NULL,
    hook_error = NULL,
    result = NULL,
    usage = NULL,
    agent_result = NULL,
    turns = list(),
    manifest = NULL,
    working_context = NULL
  )
  lead_observe_status(lead, id, "admitted")
  id
}

lead_bind_delegation <- function(lead, id, child, manifest = NULL) {
  private <- lead$.__enclos_env__$private
  record <- private$subagent_runs[[id]]
  record$manifest <- manifest
  record$agent_id <- child$agent_id
  record$session_id <- child$session_id()
  record$run_context <- child$run_context
  private$subagent_runs[[id]] <- record
  lead_observe_status(lead, id, "prepared")
  invisible(NULL)
}

lead_delegation_records <- function(lead, messages = FALSE, usage = FALSE) {
  private <- lead$.__enclos_env__$private
  unname(lapply(private$subagent_runs, function(record) {
    child <- private$active_subagents[[record$delegation_id]]
    if (!is.null(child)) {
      record$run_id <- child$.__enclos_env__$private$current_run_id
      record$artifacts <- child$.__enclos_env__$private$delegation_artifacts
      record$references <- lapply(record$artifacts, function(ref) {
        ref$scope <- private$delegation_scope
        ref
      })
      if (messages) {
        record$turns <- child$turns()
      }
      if (usage) {
        record$usage <- child$.__enclos_env__$private$current_run_usage()
      }
    }
    record
  }))
}

delegation_status <- function(result, error = NULL) {
  if (!is.null(error)) {
    return("failed")
  }
  if (is.null(result)) {
    return("not_started")
  }
  switch(
    result$stop_reason,
    complete = "completed",
    error = "failed",
    provider_error = "failed",
    approval_pending = "suspended",
    "stopped"
  )
}

lead_settle_delegation <- function(
  lead,
  id,
  child = NULL,
  result = NULL,
  error = NULL,
  stop_reason = NULL,
  observe = TRUE
) {
  private <- lead$.__enclos_env__$private
  record <- private$subagent_runs[[id]]
  if (!is.na(record$completed_at)) {
    return(invisible(record))
  }
  child_private <- if (!is.null(child)) child$.__enclos_env__$private
  last_result <- if (!is.null(child)) child$last_run()
  record$run_id <- result$run_id %||% child_private$current_run_id
  record$status <- delegation_status(result, error)
  record$stop_reason <- result$stop_reason %||%
    last_result$stop_reason %||%
    record$cancel_reason %||%
    stop_reason %||%
    if (!is.null(error)) "error" else "not_started"
  record$error <- if (!is.null(error)) conditionMessage(error)
  record$input_error <- if (inherits(error, "deputy_delegation_input_error")) {
    error$reason
  }
  record$result <- result$response %||% last_result$response
  record$usage <- result$usage %||% child_private$last_run_usage
  record$agent_result <- result
  record$artifacts <- child_private$delegation_artifacts %||% list()
  record$turns <- if (!is.null(child)) {
    tryCatch(child$turns(), error = function(e) list())
  } else {
    list()
  }
  record$working_context <- if (!is.null(child)) {
    list(
      system_prompt = child$get_system_prompt(),
      turns = child$get_context_turns()
    )
  }
  record$completed_at <- Sys.time()
  private$subagent_runs[[id]] <- record
  lead_prepare_outcome(lead, id)
  if (observe) {
    lead_observe_status(lead, id, "settled")
  }
  invisible(private$subagent_runs[[id]])
}

lead_delegation_hook <- function(lead, id, event, definition = NULL) {
  private <- lead$.__enclos_env__$private
  record <- private$subagent_runs[[id]]
  previous_errors <- length(lead$hooks$last_errors())
  on.exit(
    {
      errors <- lead$hooks$last_errors()
      if (length(errors) > previous_errors) {
        messages <- vapply(
          errors[seq.int(previous_errors + 1L, length(errors))],
          function(error) paste0(error$event, ": ", error$error),
          character(1)
        )
        current <- private$subagent_runs[[id]]
        current$hook_error <- paste(
          c(current$hook_error, messages),
          collapse = "\n"
        )
        private$subagent_runs[[id]] <- current
      }
    },
    add = TRUE
  )
  args <- list(
    event = event,
    agent_name = record$agent_name,
    task = record$task,
    context = private$hook_context(
      agent_definition = definition,
      status = record$status,
      stop_reason = record$stop_reason,
      error = record$error,
      tool_call_id = record$tool_call_id,
      parent_agent_id = record$parent_agent_id,
      parent_run_id = record$parent_run_id,
      child_agent_id = record$agent_id,
      child_agent_name = record$agent_name,
      child_run_id = record$run_id,
      child_run_context = record$run_context,
      delegation_id = id
    )
  )
  if (identical(event, "SubagentStop")) {
    args["result"] <- list(record$result)
  }
  do.call(private$fire_hook, args)
}

# Both callers reserve usage before starting this promise. Always release it,
# including when a start observer cancels before the child's first request.
lead_run_delegation <- function(
  lead,
  id,
  child,
  definition,
  task,
  limits = NULL
) {
  private <- lead$.__enclos_env__$private
  coro::async(function() {
    on.exit(
      {
        private$release_delegation_usage(id)
        private$active_subagents[[id]] <- NULL
        release_delegation_binding(lead, id)
      },
      add = TRUE
    )
    result <- NULL
    error <- NULL
    started <- FALSE
    tryCatch(
      {
        if (
          !isTRUE(private$should_stop) &&
            is.null(private$subagent_runs[[id]]$cancel_reason)
        ) {
          record <- private$subagent_runs[[id]]
          record$status <- "running"
          record$started_at <- Sys.time()
          private$subagent_runs[[id]] <- record
          private$active_subagents[[id]] <- child
          lead_observe_status(lead, id, "running")
          started <- TRUE
          lead_delegation_hook(lead, id, "SubagentStart", definition)
          if (
            !isTRUE(private$should_stop) &&
              is.null(private$subagent_runs[[id]]$cancel_reason)
          ) {
            result <- coro::await(child$run_async(task, usage_limits = limits))
          }
        }
      },
      error = function(condition) {
        error <<- condition
      }
    )
    record <- lead_settle_delegation(
      lead,
      id,
      child,
      result,
      error,
      stop_reason = private$subagent_runs[[id]]$cancel_reason %||%
        private$stop_reason_from_hook,
      observe = FALSE
    )
    private$release_delegation_usage(id)
    private$current_external_usage <- agent_usage_add(
      private$current_external_usage %||% AgentUsage(),
      record$usage %||% AgentUsage()
    )
    if (started) {
      tryCatch(
        lead_delegation_hook(lead, id, "SubagentStop"),
        error = function(condition) {
          error <<- condition
          record <- private$subagent_runs[[id]]
          record$hook_error <- paste(
            c(record$hook_error, conditionMessage(condition)),
            collapse = "\n"
          )
          record$status <- "failed"
          record$error <- conditionMessage(condition)
          private$subagent_runs[[id]] <- record
        }
      )
    }
    lead_observe_status(lead, id, "settled")
    list(
      result = result,
      error = error,
      status = private$subagent_runs[[id]]$status
    )
  })()
}
