# Deputy records governance; ellmer records model, HTTP, and tool execution.
start_run_trace <- function(agent, state) {
  if (!requireNamespace("otel", quietly = TRUE)) {
    return(NULL)
  }
  private <- agent$.__enclos_env__$private
  attributes <- Filter(
    Negate(is.null),
    list(
      "deputy.run.id" = state$active_run_id,
      "deputy.agent.id" = agent$agent_id,
      "deputy.parent.run.id" = private$.parent_run_id,
      "deputy.delegation.id" = private$.delegation_id,
      "gen_ai.conversation.id" = private$.session_id
    )
  )
  otel::start_span(
    "deputy.run",
    attributes = attributes,
    tracer = otel::get_tracer("co.posit.r-package.deputy")
  )
}

with_run_trace <- function(state, expr) {
  span <- state$trace_span
  if (!is.null(span)) {
    promises::local_otel_promise_domain()
    otel::local_active_span(span)
  }
  force(expr)
}

trace_governance_event <- function(span, event) {
  if (
    is.null(span) ||
      !event$type %in%
        c(
          "file_checkpoint",
          "warning",
          "stop",
          "permission",
          "fallback",
          "structured_attempt",
          "hook",
          "compaction",
          "delegation"
        )
  ) {
    return(invisible(NULL))
  }
  # Deliberate allowlist: no prompt, tool arguments, result, run_context,
  # condition messages, filesystem paths, or validation feedback is exported.
  fields <- intersect(
    names(event),
    c(
      "run_id",
      "tool_call_id",
      "delegation_id",
      "checkpoint_id",
      "code",
      "decision",
      "hook",
      "attempt",
      "valid",
      "fallback_index"
    )
  )
  attributes <- Filter(
    function(value) is.atomic(value) && length(value) == 1L && !is.na(value),
    event[fields]
  )
  span$add_event(paste0("deputy.", event$type), attributes = attributes)
  invisible(NULL)
}

finish_run_trace <- function(state) {
  span <- state$trace_span
  if (is.null(span)) {
    return(invisible(NULL))
  }
  span$set_attribute("deputy.stop_reason", trace_stop_reason(state$reason))
  span$set_status(if (identical(state$reason, "complete")) "ok" else "error")
  otel::end_span(span)
  invisible(NULL)
}

trace_stop_reason <- function(reason) {
  known <- c(
    "complete",
    "error",
    "provider_error",
    "interrupted",
    "abandoned",
    "request_limit",
    "tool_call_limit",
    "input_token_limit",
    "output_token_limit",
    "total_token_limit",
    "cost_limit",
    "cost_unavailable",
    "permission_denied",
    "tool_loop",
    "hook_requested_stop",
    "delegation_error",
    "file_checkpoint_error"
  )
  if (reason %in% known) reason else "custom"
}
