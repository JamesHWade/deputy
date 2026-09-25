# Automatic context transitions share the run lifecycle and budget. Summary
# requests stay on isolated Chats; ellmer owns their IO, retries and cancellation.
governed_compaction <- function(agent, messages) {
  private <- agent$.__enclos_env__$private
  state <- private$current_run_state
  # The operation records artifacts here so cleanup runs however it settles.
  holder <- new.env(parent = emptyenv())
  holder$artifacts <- NULL
  operation <- governed_compaction_async(agent, private, messages, holder)
  operation <- promises::finally(operation, function() {
    artifacts <- holder$artifacts
    if (!is.null(artifacts)) private$finish_compaction_artifacts(artifacts)
  })
  promises::catch(operation, function(error) {
    state$failure_phase <- "compaction"
    rlang::cnd_signal(error)
  })
}

# coro caches each factory's state machine, so compaction factories are
# defined once and receive per-call values as arguments.
governed_compaction_async <- coro::async(function(
  agent,
  private,
  messages,
  holder
) {
  policy <- private$.context_policy
  if (
    is.null(policy$max_tokens) ||
      !length(private$.chat$get_turns()) ||
      !compaction_can_continue(agent)
  ) {
    return(NULL)
  }
  estimate <- private$context_estimate(messages)
  estimated <- estimate$tokens
  if (is.null(estimated) || estimated <= policy$max_tokens) {
    return(NULL)
  }
  keep_last <- private$compaction_keep_last(
    messages,
    floor(policy$max_tokens * policy$compact_to),
    # Subsets use the same source as the full estimate, so a provider count
    # is never compared with a character estimate.
    estimate = identical(estimate$source, "estimate")
  )
  plan <- private$prepare_compaction(
    keep_last,
    NULL,
    policy$fallback,
    TRUE,
    estimated
  )
  if (!is.null(plan$result)) {
    return(plan$result)
  }
  if (!compaction_can_continue(agent)) {
    return(NULL)
  }
  private$record_run_event(private$agent_event(
    "compaction_start",
    estimated_tokens = estimated,
    estimate_source = estimate$source,
    turns_compacted = length(plan$turns_to_compact),
    turns_kept = length(plan$turns_to_keep)
  ))
  holder$artifacts <- private$begin_compaction_artifacts()
  if (is.null(plan$summary)) {
    generated <- coro::await(compaction_summary_requests(
      agent,
      plan$turns_to_compact
    ))
  } else {
    generated <- list(
      summary = plan$summary,
      method = plan$method,
      usage = AgentUsage(),
      attempts = list()
    )
  }
  # Cancellation never installs a partial or deterministic recovery summary.
  # A completed summary may be accepted even if it used the final request.
  if (is.null(generated) || isTRUE(private$should_stop)) {
    return(NULL)
  }
  result <- private$install_compaction(
    plan,
    generated$summary,
    generated$method,
    generated$usage,
    generated$attempts
  )
  compaction_can_continue(agent)
  result
})

compaction_can_continue <- function(agent) {
  private <- agent$.__enclos_env__$private
  if (
    isTRUE(private$current_stream_controller$cancelled) &&
      !isTRUE(private$should_stop)
  ) {
    private$request_stream_stop("interrupted")
  }
  if (isTRUE(private$should_stop)) {
    return(FALSE)
  }
  status <- tree_usage_status(agent) %||%
    usage_limit_status(
      private$current_run_usage(),
      private$current_usage_limits,
      require_followup = TRUE
    )
  if (!is.null(status)) {
    private$mark_usage_limit(status)
    return(FALSE)
  }
  TRUE
}

compaction_summary_requests <- function(agent, turns) {
  private <- agent$.__enclos_env__$private
  compaction_summary_requests_async(agent, private, turns)
}

compaction_summary_requests_async <- coro::async(function(
  agent,
  private,
  turns
) {
  prompt <- private$compaction_summary_prompt(turns)
  templates <- c(
    list(private$.chat),
    private$.context_policy$summary_fallback_chats
  )
  attempts <- list()
  usage <- AgentUsage()
  for (index in seq_along(templates)) {
    if (!compaction_can_continue(agent)) {
      return(NULL)
    }
    attempt <- coro::await(compaction_summary_attempt(
      agent,
      templates[[index]],
      prompt,
      index - 1L
    ))
    usage <- agent_usage_add(usage, attempt$usage)
    attempts[[index]] <- attempt[c(
      "fallback_index",
      "provider",
      "model",
      "usage",
      "condition"
    )]
    if (
      isTRUE(private$current_stream_controller$cancelled) ||
        isTRUE(private$should_stop)
    ) {
      private$request_stream_stop(
        private$stop_reason_from_hook %||% "interrupted"
      )
      return(NULL)
    }
    if (is.null(attempt$condition)) {
      return(list(
        summary = attempt$summary,
        method = "llm",
        usage = usage,
        attempts = attempts
      ))
    }
    if (!attempt$recoverable || index == length(templates)) {
      break
    }
    if (!compaction_can_continue(agent)) {
      return(NULL)
    }
    private$record_run_event(private$agent_event(
      "fallback",
      phase = "compaction",
      fallback_index = index,
      condition = attempt$condition,
      usage = private$current_run_usage()
    ))
  }
  if (!compaction_can_continue(agent)) {
    return(NULL)
  }
  if (identical(private$.context_policy$fallback, "error")) {
    abort_deputy(
      c(
        "Conversation compaction failed.",
        "x" = conditionMessage(attempt$condition),
        "i" = "Set ContextPolicy(fallback = 'text') to permit degraded compaction."
      ),
      class = "compaction_error",
      parent = attempt$condition
    )
  }
  private$notify(
    "Compaction used the configured deterministic text fallback.",
    level = "warning",
    code = "compact_fallback",
    error = conditionMessage(attempt$condition)
  )
  list(
    summary = private$generate_fallback_summary(turns),
    method = "text",
    usage = usage,
    attempts = attempts
  )
})

compaction_summary_attempt <- function(
  agent,
  template,
  prompt,
  fallback_index
) {
  private <- agent$.__enclos_env__$private
  state <- private$current_run_state
  compaction_summary_attempt_async(
    agent,
    private,
    state,
    template,
    prompt,
    fallback_index
  )
}

compaction_summary_attempt_async <- coro::async(function(
  agent,
  private,
  state,
  template,
  prompt,
  fallback_index
) {
  chat <- NULL
  dispatched <- 0L
  provider <- template$get_provider()@name
  model <- template$get_model()
  condition <- NULL
  summary <- NULL
  tryCatch(
    {
      chat <- clone_compaction_chat(template)
      chat$conversation_id <- private$.session_id
      chat$on_request_start(function(turns) {
        if (!compaction_can_continue(agent)) {
          abort_deputy(
            "The governed run has stopped",
            class = "run_stopped"
          )
        }
        dispatched <<- dispatched + 1L
        state$request_number <- state$request_number + 1L
        # Charge the dispatch now. Tokens and cost settle after the attempt;
        # reaching the request limit must not cancel this in-flight response.
        private$current_external_usage <- agent_usage_add(
          private$current_external_usage,
          AgentUsage(requests = 1L)
        )
        private$record_run_event(private$agent_event(
          "request_start",
          phase = "compaction",
          request_number = state$request_number,
          fallback_index = fallback_index,
          provider = provider,
          model = model
        ))
      })
      chat$on_request_end(function(turn) {
        private$record_run_event(private$agent_event(
          "request_end",
          phase = "compaction",
          request_number = state$request_number,
          provider = provider,
          model = model,
          outcome = "response"
        ))
      })
      stream <- chat$stream_async(
        prompt,
        controller = private$current_stream_controller
      )
      repeat {
        chunk <- coro::await(with_run_trace(state, stream()))
        if (coro::is_exhausted(chunk)) {
          break
        }
      }
      summary <- chat$last_turn()@text
      if (
        !is.character(summary) ||
          length(summary) != 1L ||
          is.na(summary) ||
          !nzchar(trimws(summary))
      ) {
        abort_deputy("Compaction did not produce a non-empty summary")
      }
    },
    error = function(error) {
      condition <<- error
    }
  )

  if (dispatched > 0L) {
    usage <- agent_usage_difference(
      agent_usage_snapshot(chat),
      AgentUsage(),
      requests = dispatched
    )
  } else {
    usage <- AgentUsage()
  }
  # Dispatch already counted requests; settlement adds the reported resources.
  settled <- AgentUsage(
    requests = 0L,
    tool_calls = usage@tool_calls,
    input_tokens = usage@input_tokens,
    output_tokens = usage@output_tokens,
    cached_tokens = usage@cached_tokens,
    cost_usd = usage@cost_usd
  )
  private$current_external_usage <- agent_usage_add(
    private$current_external_usage,
    settled
  )
  last_turn <- NULL
  if (!is.null(chat)) {
    last_turn <- tryCatch(chat$last_turn(), error = function(e) NULL)
  }
  model_error <- inherits(condition, c("httr2_failure", "httr2_http")) &&
    inherits(last_turn, "ellmer::AssistantPartialTurn") &&
    dispatched > 0L
  if (!is.null(condition)) {
    private$record_run_event(private$agent_event(
      if (model_error) "request_error" else "compaction_error",
      phase = "compaction",
      request_number = state$request_number,
      fallback_index = fallback_index,
      provider = provider,
      model = model,
      condition = condition,
      usage = usage
    ))
  }
  list(
    summary = summary,
    usage = usage,
    condition = condition,
    recoverable = model_error && fallback_transport_error(condition),
    provider = provider,
    model = model,
    fallback_index = fallback_index
  )
})
