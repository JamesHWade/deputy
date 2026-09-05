# Shared lifecycle for model runs and host-driven delegation batches.
record_run_failure <- function(agent, phase, condition) {
  private <- agent$.__enclos_env__$private
  private$record_run_event(private$agent_event(
    "run_error",
    phase = phase,
    condition = condition
  ))
}

initialize_agent_run <- function(
  agent,
  state,
  messages,
  limits,
  run_context,
  controller = NULL,
  stream_mode = "content",
  initial_usage = AgentUsage()
) {
  private <- agent$.__enclos_env__$private
  private$run_active <- TRUE
  private$current_run_id <-
    private$new_run_id()
  private$current_run_context <-
    run_context
  active_run_id <- private$current_run_id
  state$active_run_id <- active_run_id
  state$run_context <- run_context
  state$limits <- limits

  # Initialize lazily on first consumption. Merely constructing and
  # abandoning a stream must not reserve this Agent forever.
  private$tool_call_count <- 0L
  private$tool_call_limit <-
    limits$max_tool_calls
  private$should_stop <- FALSE
  private$stop_reason_from_hook <- NULL
  private$current_usage_limits <- limits
  private$current_usage_baseline <-
    agent_usage_snapshot(private$.chat)
  state$turns_before <- length(
    private$.chat$get_turns()
  )
  private$current_tool_calls <- 0L
  private$current_tool_results <- 0L
  private$current_outer_requests <- 0L
  private$current_external_usage <- initial_usage
  private$current_stream_controller <-
    controller %||%
    tryCatch(
      ellmer::stream_controller(),
      error = function(e) NULL
    )
  private$current_stream_content <-
    identical(stream_mode, "content")
  private$current_run_state <- state
  state$response_seen <- FALSE
  state$fallback_index <- private$.fallback_position
  state$request_number <- 0L
  state$dispatch_turns <- private$.chat$get_turns()
  state$trace_span <- start_run_trace(agent, state)
  install_request_callbacks(agent)
  private$pending_events <- list()
  private$tool_started_at <- list()
  private$tool_event_overrides <- list()
  private$tool_call_records <- list()
  private$pending_delegations <- list()
  private$original_tool_results <- list()
  private$last_limit_status <- NULL
  private$last_tool_cycle_signature <- NULL
  private$consecutive_tool_cycles <- 0L
  private$last_run_usage <- AgentUsage()
  private$current_run_checkpoint_id <- NULL

  if (!is.null(private$.file_checkpoints)) {
    checkpoint_id <- private$.file_checkpoints$checkpoint(
      paste0("run ", active_run_id),
      metadata = list(
        run_id = active_run_id,
        message_count = length(messages)
      )
    )
    private$current_run_checkpoint_id <-
      checkpoint_id
  }

  task <- messages
  if (length(messages) == 1L) {
    task <- messages[[1L]]
  }
  private$record_run_event(
    private$agent_event(
      "start",
      task = task,
      usage_limits = limits,
      checkpoint_id = private$current_run_checkpoint_id
    )
  )
  if (
    !is.null(
      private$current_run_checkpoint_id
    )
  ) {
    private$record_run_event(
      private$agent_event(
        "file_checkpoint",
        checkpoint_id = private$current_run_checkpoint_id,
        name = paste0("run ", active_run_id)
      )
    )
  }

  private$fire_hook(
    "SessionStart",
    context = private$hook_context(
      permissions = agent$permissions,
      provider = agent$provider(),
      tools_count = length(private$.chat$get_tools()),
      run_id = active_run_id
    )
  )
  state$session_started <- TRUE
  private$fire_hook(
    "UserPromptSubmit",
    prompt = if (length(messages) == 1L) messages[[1L]] else messages,
    context = private$hook_context(
      run_id = active_run_id
    )
  )

  initial_limit_status <- usage_limit_status(
    private$current_run_usage(),
    private$current_usage_limits,
    require_followup = TRUE
  )
  if (!is.null(initial_limit_status)) {
    private$mark_usage_limit(initial_limit_status)
    state$reason <- initial_limit_status$reason
  }

  invisible(state)
}
