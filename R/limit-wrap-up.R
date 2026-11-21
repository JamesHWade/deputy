# The answer request a run limit leaves, for callers who ask for it with
# `UsageLimits(on_exceed = "wrap_up")`. When a request or tool-call limit
# ends such a run in the middle of its work, the model gets one more request, with
# no tools, to answer with what it has. Token and cost ceilings are the
# exception: a run that has reached one, or that has too little left of one
# for the request to fit, stops at once, because the extra request is exactly
# what those limits are there to prevent.

limit_wrap_up_reasons <- c("request_limit", "tool_call_limit")

limit_wrap_up_instruction <- paste(
  "A run limit was reached, so no more tools are available.",
  "Answer now with what you have gathered so far,",
  "and say what you could not check or finish."
)

# Whether the run that just ended on a limit should get its answer request,
# and the turns it would carry. Returns NULL when it should not.
limit_wrap_up_plan <- function(agent, state, structured, extraction) {
  private <- agent$.__enclos_env__$private
  status <- private$last_limit_status
  chat <- private$.chat
  if (
    isTRUE(state$wrap_up_done) ||
      !is.null(structured) ||
      !is.null(extraction) ||
      is.null(status) ||
      !isTRUE(private$should_stop) ||
      # The limit is why the run stopped, not an interrupt or a hook's stop
      # that arrived after it.
      !is.null(private$stop_requested_by) ||
      !identical(private$stop_reason_from_hook, status$reason) ||
      !status$reason %in% limit_wrap_up_reasons ||
      !identical(status$on_exceed %||% state$limits$on_exceed, "wrap_up") ||
      !is.null(private$.approval_dir) ||
      !is.null(private$.pending_approval_path) ||
      # Protocol test doubles have no request callbacks to carry the request.
      !is.function(chat$on_request_start) ||
      !is.function(chat$set_tools) ||
      !is.function(chat$set_turns)
  ) {
    return(NULL)
  }
  # A budget shared with other agents has no room for a request nobody
  # admitted.
  if (!is.null(tree_usage_status(agent))) {
    return(NULL)
  }
  turns <- chat$get_turns()
  if (length(turns) <= state$turns_before) {
    return(NULL)
  }
  last <- turns[[length(turns)]]
  pending_results <- inherits(last, "ellmer::UserTurn") &&
    any(vapply(
      last@contents,
      inherits,
      logical(1),
      what = "ellmer::ContentToolResult"
    ))
  dangling_calls <- inherits(last, "ellmer::AssistantTurn") &&
    any(vapply(
      last@contents,
      inherits,
      logical(1),
      what = "ellmer::ContentToolRequest"
    ))
  # A model that has answered has nothing left to say.
  if (!pending_results && !dangling_calls) {
    return(NULL)
  }
  if (!limit_wrap_up_fits(agent, state)) {
    return(NULL)
  }
  list(
    status = status,
    turns = turns,
    results = if (pending_results) last@contents else list()
  )
}

# Whether the token and cost ceilings leave room for one more request: none
# may be reached, and the input and total ceilings must leave more than the
# conversation is estimated to take.
limit_wrap_up_fits <- function(agent, state) {
  private <- agent$.__enclos_env__$private
  limits <- state$limits
  settings <- S7::props(limits)
  settings$max_requests <- NULL
  settings$max_tool_calls <- NULL
  ceilings <- do.call(UsageLimits, settings)
  usage <- private$current_run_usage()
  if (!is.null(usage_limit_status(usage, ceilings, require_followup = TRUE))) {
    return(FALSE)
  }
  remaining <- usage_limits_remaining(ceilings, usage)
  # Estimated here, from the Chat as it stands, whichever estimator the
  # context policy uses (a provider count would be a request of its own) and
  # without recording a frame snapshot for a request that is not made.
  needed <- tryCatch(
    local_context_estimate(
      system_prompt = private$.chat$get_system_prompt(),
      tools = list(),
      turns = private$.chat$get_turns(),
      messages = list(limit_wrap_up_instruction),
      use_usage = TRUE,
      usage_after = private$.usage_stale_turns,
      frame_snapshots = private$.frame_snapshots
    ),
    error = function(error) 0
  )
  for (field in c("max_input_tokens", "max_total_tokens")) {
    room <- remaining[[field]]
    if (!is.null(room) && room <= needed) {
      return(FALSE)
    }
  }
  TRUE
}

# Starts the answer pass. Returns the stream to read, or NULL if the run ends
# as it stands.
limit_wrap_up_start <- function(
  agent,
  state,
  tool_mode,
  stream_mode,
  stream_type,
  structured,
  extraction
) {
  plan <- limit_wrap_up_plan(agent, state, structured, extraction)
  if (is.null(plan)) {
    return(NULL)
  }
  private <- agent$.__enclos_env__$private
  chat <- private$.chat
  state$wrap_up_done <- TRUE
  state$wrap_up_active <- TRUE
  state$wrap_up_answered <- FALSE
  state$wrap_up_requests <- 0L
  state$wrap_up_saved <- list(
    tools = chat$get_tools(),
    turns = plan$turns,
    response_parts = state$response_parts
  )
  private$record_run_event(private$agent_event(
    "limit_wrap_up",
    reason = plan$status$reason,
    request_number = state$request_number
  ))
  tryCatch(
    {
      # The results of the calls that were not run travel with the question,
      # as ellmer sends the results of a call it never ran.
      if (length(plan$results)) {
        chat$set_turns(utils::head(plan$turns, -1L))
      }
      chat$set_tools(list())
      private$should_stop <- FALSE
      private$stop_reason_from_hook <- NULL
      private$stop_requested_by <- NULL
      reset_stream_controller(private$current_stream_controller)
      state$response_parts <- character()
      state$wrap_up_reason <- plan$status$reason
      private$start_async_stream(
        messages = c(plan$results, list(limit_wrap_up_instruction)),
        tool_mode = tool_mode,
        stream = stream_mode,
        controller = private$current_stream_controller,
        structured = NULL,
        stream_type = stream_type
      )
    },
    error = function(error) {
      limit_wrap_up_end(agent, state, plan$status$reason)
      NULL
    }
  )
}

# Ends the answer pass: the agent has its tools and, if the model never
# answered, its turns back, and the run ends on the limit that started it.
limit_wrap_up_end <- function(agent, state, reason = state$wrap_up_reason) {
  private <- agent$.__enclos_env__$private
  saved <- state$wrap_up_saved
  state$wrap_up_active <- FALSE
  if (is.null(saved)) {
    return(invisible(NULL))
  }
  state$wrap_up_saved <- NULL
  chat <- private$.chat
  try(chat$set_tools(saved$tools), silent = TRUE)
  if (!isTRUE(state$wrap_up_answered)) {
    try(chat$set_turns(saved$turns), silent = TRUE)
    state$response_parts <- saved$response_parts
  }
  private$should_stop <- TRUE
  private$stop_reason_from_hook <- reason
  private$stop_requested_by <- NULL
  state$reason <- reason
  invisible(NULL)
}
