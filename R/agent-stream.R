# Internal R6 methods for agent stream.
# R6 binds these methods to the same self/private environments as the facade.
deputy_agent_stream_methods <- function(self = NULL, private = NULL) {
  list(
    start_async_stream = function(
      messages,
      tool_mode,
      stream,
      controller,
      structured = NULL,
      stream_type = NULL
    ) {
      if (!is.null(structured)) {
        return(governed_structured_request(self, messages, structured))
      }
      # Real ellmer streams count each model round through public callbacks.
      # Protocol test doubles without those callbacks retain dispatch counting.
      if (!is.function(private$.chat$on_request_start)) {
        begin_model_request(self)
      }
      stream_fun <- private$.chat$stream_async
      stream_formals <- names(formals(stream_fun))
      args <- messages
      if ("tool_mode" %in% stream_formals) {
        args$tool_mode <- tool_mode
      }
      if ("stream" %in% stream_formals) {
        args$stream <- stream
      }
      if (!is.null(controller) && "controller" %in% stream_formals) {
        args$controller <- controller
      }
      if (!is.null(stream_type)) {
        args$type <- stream_type
      }
      with_run_trace(private$current_run_state, do.call(stream_fun, args))
    },

    start_governed_stream = function(
      messages,
      limits,
      run_context,
      tool_mode = "concurrent",
      stream = "content",
      controller = NULL,
      structured = NULL,
      extraction = NULL,
      stream_type = NULL,
      conversation_token = NULL
    ) {
      check_conversation_lease(self, conversation_token)
      if (isTRUE(private$run_active)) {
        cli::cli_abort(
          "This agent already has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }
      if (
        !is.null(private$.pending_approval_path) &&
          is.null(private$.approval_resume)
      ) {
        approval_abort(
          "This Agent has a pending approval; resume or deny it before starting another run."
        )
      }
      if (!is.null(private$.approval_dir)) {
        tool_mode <- "sequential"
      }
      force(structured)
      force(extraction)
      limits <- normalize_usage_limits(limits)
      state <- private$new_callback_run_state()
      private$unstarted_run <- state
      governed <- private$callback_run_stream(
        messages = messages,
        limits = limits,
        run_context = run_context,
        tool_mode = tool_mode,
        stream_mode = stream,
        controller = controller,
        structured = structured,
        extraction = extraction,
        stream_type = stream_type,
        state = state,
        conversation_token = conversation_token
      )
      agent <- self
      reg.finalizer(
        environment(governed),
        function(environment) {
          # A stream dropped before it was read is no longer waiting to start,
          # so an interrupt has nothing of it to stop.
          waiting <- agent$.__enclos_env__$private
          if (
            is.null(state$active_run_id) &&
              identical(waiting$unstarted_run, state)
          ) {
            waiting$unstarted_run <- NULL
          }
          if (
            !isTRUE(state$finished) &&
              !is.null(state$active_run_id)
          ) {
            state$reason <- "abandoned"
            try(
              agent$.__enclos_env__$private$request_stream_stop(
                "abandoned",
                by = "abandoned"
              ),
              silent = TRUE
            )
            try(
              agent$.__enclos_env__$private$finish_callback_run(state),
              silent = TRUE
            )
          }
        },
        onexit = TRUE
      )
      list(stream = governed, state = state, limits = limits)
    },

    collect_governed_stream = function(governed_run) {
      collect_governed_stream_async(governed_run$stream, governed_run$state)
    },

    echo_chat_result = function(response, echo) {
      if (is.null(echo)) {
        echo <- getOption("ellmer_echo", "none")
      }
      if (isTRUE(echo)) {
        echo <- "output"
      } else if (isFALSE(echo)) {
        echo <- "none"
      } else if (identical(echo, "text")) {
        echo <- "output"
      }
      echo <- match.arg(echo, c("none", "output", "all"))
      if (!identical(echo, "none") && !is.null(response)) {
        cli::cli_text("{response}")
      }
      invisible(NULL)
    },

    resolve_promise = function(promise) {
      if (!promises::is.promising(promise)) {
        return(promise)
      }
      value <- NULL
      error <- NULL
      done <- FALSE
      promise |>
        promises::then(function(result) {
          value <<- result
          done <<- TRUE
        }) |>
        promises::catch(function(condition) {
          error <<- condition
          done <<- TRUE
        })
      while (!done) {
        run_now(0.1)
      }
      if (!is.null(error)) {
        rlang::cnd_signal(error)
      }
      value
    },

    sync_stream_generator = function(async_stream) {
      sync_stream_adapter(agent = self, async_stream = async_stream)
    },

    event_generator = function(
      governed_run,
      include_partial_messages
    ) {
      event_stream_generator(
        agent = self,
        async_stream = governed_run$stream,
        state = governed_run$state,
        include_partial_messages = include_partial_messages
      )
    },

    # `by` names who asked for the stop (see RunEnding). A stop with no `by`
    # clears any earlier one, so a limit's stop is not credited to a caller.
    request_stream_stop = function(reason, by = NULL) {
      private$should_stop <- TRUE
      private$stop_reason_from_hook <- reason
      private$stop_requested_by <- by
      graph_cancel_descendants(self, reason)
      cancel_active_mcp_tools(
        c(private$.chat$get_tools(), private$active_owned_tools),
        self,
        private$effective_run_context()
      )
      cancel_active_r_session_tools(
        c(private$.chat$get_tools(), private$active_owned_tools),
        self,
        private$effective_run_context()
      )
      controller <- private$current_stream_controller
      if (!is.null(controller)) {
        tryCatch(
          controller$cancel(reason = reason),
          error = function(e) controller$cancel()
        )
      }
      invisible(reason)
    },

    finalize_pending_checkpoints = function() {
      if (is.null(private$.file_checkpoints)) {
        return(invisible(0L))
      }
      private$.file_checkpoints$finalize_pending()
    },

    # Shared state for one governed callback-driven run.
    # The stream body and its exit handler communicate through this env so a
    # consumer can read the terminal reason, usage, and cost after the stream
    # is exhausted and run-scoped private fields have been cleared.
    new_callback_run_state = function() {
      state <- new.env(parent = emptyenv())
      state$reason <- "complete"
      state$active_run_id <- NULL
      state$session_started <- FALSE
      state$finished <- FALSE
      state$usage <- NULL
      state$cost <- NULL
      state$events <- list()
      state$response_parts <- character()
      state$structured_output <- NULL
      state$started_at <- Sys.time()
      state$run_context <- list()
      state$limits <- NULL
      state$result <- NULL
      state$turns_before <- 0L
      state$ending <- NULL
      state$run_error <- NULL
      state$cost_warned <- FALSE
      state$stop_hook_active <- FALSE
      state$stop_hook_fired <- FALSE
      state$session_end_fired <- FALSE
      state$result_promise <- NULL
      state$resolve_result <- NULL
      state$reject_result <- NULL
      state$interrupt_before_start <- NULL
      state
    },

    # Assemble the `AgentResult` for a finished `run_async()` run. Honors
    # `on_exceed = "error"` by signalling the structured limit error when the
    # run stopped because of the recorded limit.
    callback_run_result = function(state) {
      response <- if (length(state$response_parts) > 0L) {
        paste(state$response_parts, collapse = "")
      } else if (
        identical(state$reason, "complete") &&
          length(private$.chat$get_turns()) > state$turns_before
      ) {
        tryCatch(private$get_last_response(), error = function(e) NULL)
      } else {
        NULL
      }

      AgentResult(
        ending = state$ending,
        response = response,
        turns = private$.chat$get_turns(),
        cost = state$cost %||% self$cost(),
        events = state$events,
        duration = as.numeric(Sys.time() - state$started_at, units = "secs"),
        stop_reason = state$reason %||% "complete",
        structured_output = state$structured_output,
        session_id = private$.session_id,
        run_id = state$active_run_id,
        agent_id = self$agent_id,
        agent_name = self$agent_name,
        parent_agent_id = private$.parent_agent_id,
        parent_run_id = private$.parent_run_id,
        delegation_id = private$.delegation_id,
        run_context = state$run_context,
        usage = state$usage %||% AgentUsage()
      )
    },

    # The single run kernel. Every public run interface is an adapter
    # over this lazily-started governed stream.
    callback_run_stream = function(
      messages,
      limits,
      run_context,
      tool_mode,
      stream_mode,
      controller,
      structured,
      extraction,
      stream_type,
      state,
      conversation_token = NULL
    ) {
      governed_run_stream(
        agent = self,
        stream_state = state,
        messages = messages,
        run_limits = limits,
        effective_run_context = run_context,
        tool_mode = tool_mode,
        stream_mode = stream_mode,
        controller = controller,
        structured = structured,
        extraction = extraction,
        stream_type = stream_type,
        conversation_token = conversation_token
      )
    },

    # Settles the run's reason, usage, cost and limit, the facts a Stop hook
    # reads. Called from the run's body before Stop and from
    # finish_callback_run(); each block checks what an earlier call set.
    settle_run = function(state) {
      if (isTRUE(private$should_stop) && identical(state$reason, "complete")) {
        state$reason <- private$stop_reason_from_hook %||%
          "hook_requested_stop"
      }
      incomplete_tool_call <-
        private$current_tool_calls > private$current_tool_results
      private$finalize_pending_checkpoints()
      usage <- private$current_run_usage()
      state$usage <- usage
      state$cost <- tryCatch(self$cost(), error = function(e) NULL)
      if (!is.null(state$cost) && is.na(usage$cost_usd)) {
        state$cost$total <- NA_real_
        state$cost$complete <- FALSE
        state$cost$missing <- max(1L, state$cost$missing %||% 0L)
      }
      private$last_run_usage <- usage
      limits <- private$current_usage_limits
      if (
        identical(state$reason, "complete") &&
          isTRUE(incomplete_tool_call)
      ) {
        state$reason <- "provider_error"
        private$notify(
          "Provider stream ended before a tool result arrived.",
          level = "warning",
          code = "provider_error",
          usage = usage
        )
      }
      if (identical(state$reason, "complete") && !is.null(limits)) {
        limit_status <- tree_usage_status(
          self,
          require_followup = FALSE
        ) %||%
          usage_limit_status(usage, limits)
        if (!is.null(limit_status)) {
          private$last_limit_status <- limit_status
          state$reason <- limit_status$reason
          private$notify(
            usage_limit_message(limit_status),
            level = "warning",
            code = limit_status$reason,
            usage = usage,
            limit = limit_status$limit
          )
        }
      }
      # settle_run() runs again after a Stop hook, so the warning is guarded.
      if (
        is.null(private$last_limit_status) &&
          !isTRUE(state$cost_warned) &&
          !is.null(limits$max_cost_usd) &&
          is.finite(usage$cost_usd) &&
          usage$cost_usd >= limits$max_cost_usd * 0.9
      ) {
        state$cost_warned <- TRUE
        private$notify(
          paste0(
            "Approaching run cost limit: ",
            format_cost(usage$cost_usd),
            " / ",
            format_cost(limits$max_cost_usd)
          ),
          level = "warning",
          code = "cost_limit_warning",
          usage = usage,
          max_cost_usd = limits$max_cost_usd
        )
        cli::cli_warn(
          "Approaching run cost limit: {format_cost(usage$cost_usd)} / {format_cost(limits$max_cost_usd)}"
        )
      }
      invisible(NULL)
    },

    # The run's RunEnding as it stands. Built from the same facts for the
    # hooks that read it and for the run's result.
    run_ending_now = function(state) {
      turns <- private$.chat$get_turns()
      last_turn <- if (length(turns) > state$turns_before) {
        tryCatch(private$.chat$last_turn(), error = function(e) NULL)
      }
      finish_reason <- tryCatch(last_turn@finish_reason, error = function(e) {
        NULL
      })
      run_ending_for(
        state$reason,
        # Who asked matters only when the run's reason is the one they gave.
        by = if (
          isTRUE(private$should_stop) &&
            identical(state$reason, private$stop_reason_from_hook)
        ) {
          private$stop_requested_by
        },
        limit_status = private$last_limit_status,
        finish_reason = finish_reason,
        error = state$run_error$condition,
        phase = state$run_error$phase
      )
    },

    # Fires "Stop" or "SessionEnd" for the run and returns what fire_hook
    # returned.
    fire_end_hook = function(event, state) {
      context <- private$hook_context(
        cost = self$cost(),
        usage = state$usage,
        run_id = state$active_run_id,
        ending = private$run_ending_now(state)
      )
      if (identical(event, "Stop")) {
        context$stop_hook_active <- isTRUE(state$stop_hook_active)
      }
      private$fire_hook(event, reason = state$reason, context = context)
    },

    # Terminal accounting for a callback-driven run: settles the stop reason,
    # fires Stop/SessionEnd, records
    # run-scoped usage and cost on `state`, and releases the active run.
    finish_callback_run = function(state) {
      active_run_id <- state$active_run_id
      if (
        isTRUE(state$finished) ||
          is.null(active_run_id) ||
          !identical(private$current_run_id, active_run_id)
      ) {
        return(invisible(NULL))
      }
      state$finished <- TRUE
      graph_cancel_descendants(self, "parent_completed")
      on.exit(finish_run_trace(state), add = TRUE)
      on.exit(remove_request_callbacks(private$.chat), add = TRUE)
      on.exit(
        {
          if (
            !is.null(state$runtime_chat) &&
              identical(
                attr(state$runtime_chat, "deputy_active_runtime", exact = TRUE),
                state$runtime_token
              )
          ) {
            attr(state$runtime_chat, "deputy_active_runtime") <- NULL
          }
        },
        add = TRUE
      )

      cleanup_error <- NULL
      tryCatch(
        {
          observed_last_turn <- tryCatch(
            private$.chat$last_turn(),
            error = function(e) NULL
          )
          private$settle_run(state)
          usage <- state$usage
          limits <- private$current_usage_limits
          # A run that ends outside its body cannot wait for a promise, so a
          # hook the body did not fire is fired here and not waited for.
          if (isTRUE(state$session_started)) {
            if (!isTRUE(state$stop_hook_fired)) {
              state$stop_hook_fired <- TRUE
              hook_unawaited(private$fire_end_hook("Stop", state))
            }
            if (!isTRUE(state$session_end_fired)) {
              state$session_end_fired <- TRUE
              hook_unawaited(private$fire_end_hook("SessionEnd", state))
            }
          }

          if (length(state$response_parts) > 0L) {
            private$record_run_event(AgentEvent(
              "text_complete",
              run_id = active_run_id,
              text = paste(state$response_parts, collapse = "")
            ))
          }
          current_turn_count <- length(private$.chat$get_turns())
          if (current_turn_count > state$turns_before) {
            last_turn <- observed_last_turn
          } else {
            last_turn <- NULL
          }
          if (!is.null(last_turn)) {
            private$record_run_event(private$agent_event(
              "turn",
              turn = last_turn,
              turn_number = max(1L, usage$requests)
            ))
          }
          state$ending <- private$run_ending_now(state)
          private$record_run_event(private$agent_event(
            "usage",
            usage = usage,
            limits = limits
          ))
          private$record_run_event(private$agent_event(
            "stop",
            reason = state$reason,
            cost = state$cost,
            usage = usage,
            limit = private$last_limit_status,
            ending = state$ending
          ))
          private$commit_approval_state(
            if (identical(state$reason, "complete")) "completed" else "stopped",
            reason = state$reason
          )
          state$result <- private$callback_run_result(state)
          private$.last_run_result <- state$result

          limit_status <- private$last_limit_status
          if (
            !is.null(limit_status) &&
              identical(
                limit_status$on_exceed %||% state$limits$on_exceed,
                "error"
              ) &&
              identical(state$reason, limit_status$reason)
          ) {
            private$abort_usage_limit(limit_status)
          }
        },
        error = function(error) {
          cleanup_error <<- error
        }
      )

      private$tool_call_limit <- NULL
      private$tool_call_count <- 0L
      private$last_tool_cycle_signature <- NULL
      private$consecutive_tool_cycles <- 0L
      private$should_stop <- FALSE
      private$stop_reason_from_hook <- NULL
      private$stop_requested_by <- NULL
      tryCatch(
        private$finish_active_run(),
        error = function(error) {
          if (is.null(cleanup_error)) {
            cleanup_error <<- error
          }
        }
      )
      # Settled after the agent is free, so a caller's then() can start the next run.
      if (is.function(state$resolve_result)) {
        if (!is.null(state$result)) {
          state$resolve_result(state$result)
        } else {
          state$reject_result(
            cleanup_error %||% run_without_result_error()
          )
        }
      }
      if (!is.null(cleanup_error)) {
        stop(cleanup_error)
      }
      invisible(NULL)
    },

    # Promises of hooks that ellmer does not wait for. Taking them empties the list.
    take_held_hooks = function() {
      held <- private$held_hooks
      private$held_hooks <- list()
      held
    },

    finish_active_run = function() {
      tree_run_finished(self)
      if (identical(private$unstarted_run, private$current_run_state)) {
        private$unstarted_run <- NULL
      }
      checkpoint_error <- NULL
      tryCatch(
        private$finalize_pending_checkpoints(),
        error = function(error) {
          checkpoint_error <<- error
        }
      )
      private$current_stream_controller <- NULL
      private$current_stream_content <- FALSE
      private$current_usage_limits <- NULL
      private$current_usage_baseline <- NULL
      private$current_tool_calls <- 0L
      private$current_tool_results <- 0L
      private$current_outer_requests <- 0L
      private$current_external_usage <- NULL
      private$current_run_state <- NULL
      private$pending_events <- list()
      private$tool_started_at <- list()
      private$tool_event_overrides <- list()
      private$tool_call_records <- list()
      private$pending_delegations <- list()
      private$held_hooks <- list()
      private$original_tool_results <- list()
      private$last_tool_cycle_signature <- NULL
      private$consecutive_tool_cycles <- 0L
      if (!is.null(private$current_run_context)) {
        private$last_run_context <- clone_run_context(
          private$current_run_context
        )
      }
      private$current_run_context <- NULL
      private$run_active <- FALSE
      if (!is.null(checkpoint_error)) {
        stop(checkpoint_error)
      }
      invisible(NULL)
    }
  )
}

# coro caches each factory's state machine, so these factories are defined once
# and receive per-run values as arguments instead of closing over a method
# frame. Their bodies reference only arguments and namespace functions.

# A stream that ends at once: for a run that is stopped before it asks the
# model. Defined once, as the factories below are.
empty_run_stream <- coro::async_generator(function() {
  # jarl-ignore unreachable_code: the yield is never run; it makes this a generator
  if (FALSE) coro::yield("unreachable")
})

collect_governed_stream_async <- coro::async(function(stream, state) {
  repeat {
    chunk <- coro::await(stream())
    if (coro::is_exhausted(chunk)) {
      break
    }
  }
  result <- state$result
  if (is.null(result)) {
    cli_abort("The governed run ended without an AgentResult")
  }
  result
})

sync_stream_adapter <- coro::generator(function(agent, async_stream) {
  repeat {
    chunk <- agent$.__enclos_env__$private$resolve_promise(
      async_stream()
    )
    if (coro::is_exhausted(chunk)) {
      break
    }
    coro::yield(chunk)
  }
})

event_stream_generator <- coro::generator(function(
  agent,
  async_stream,
  state,
  include_partial_messages
) {
  next_event <- 1L
  exhausted <- FALSE
  repeat {
    while (next_event <= length(state$events)) {
      event <- state$events[[next_event]]
      next_event <- next_event + 1L
      if (
        isTRUE(include_partial_messages) ||
          !identical(event$type, "text")
      ) {
        coro::yield(event)
      }
    }
    if (isTRUE(exhausted)) {
      break
    }
    chunk <- agent$.__enclos_env__$private$resolve_promise(
      async_stream()
    )
    exhausted <- coro::is_exhausted(chunk)
  }
})

# The single run kernel. Every public run interface is an adapter over this
# lazily-started governed stream.
governed_run_stream <- coro::async_generator(function(
  agent,
  stream_state,
  messages,
  run_limits,
  effective_run_context,
  tool_mode,
  stream_mode,
  controller,
  structured,
  extraction,
  stream_type,
  conversation_token
) {
  check_conversation_lease(agent, conversation_token)
  if (isTRUE(agent$.__enclos_env__$private$run_active)) {
    cli::cli_abort(
      "This agent already has an active run",
      class = c("deputy_run_active", "deputy_error")
    )
  }

  on.exit(
    agent$.__enclos_env__$private$finish_callback_run(stream_state),
    add = TRUE
  )
  tryCatch(
    {
      initialize_agent_run(
        agent,
        stream_state,
        messages,
        run_limits,
        effective_run_context,
        controller,
        stream_mode,
        start_hooks = FALSE
      )
      started <- fire_session_start(agent, stream_state)
      if (promises::is.promising(started)) {
        coro::await(started)
      }
      stream_state$session_started <- TRUE
      submitted <- fire_prompt_submit(agent, stream_state, messages)
      if (promises::is.promising(submitted)) {
        coro::await(submitted)
      }
      check_initial_run_limits(agent, stream_state)
    },
    error = function(error) {
      stream_state$reason <- "error"
      record_run_failure(agent, "initialization", error)
      rlang::cnd_signal(error)
    }
  )
  if (
    !agent$.__enclos_env__$private$should_stop ||
      identical(
        agent$.__enclos_env__$private$.approval_resume$record$decision$decision,
        "deny"
      )
  ) {
    tryCatch(
      agent$.__enclos_env__$private$execute_approval_resume(),
      error = function(error) {
        stream_state$reason <- "error"
        record_run_failure(agent, "approval_resume", error)
        rlang::cnd_signal(error)
      }
    )
  }
  tryCatch(
    coro::await(agent$.__enclos_env__$private$maybe_auto_compact(
      messages
    )),
    error = function(error) {
      if (!agent$.__enclos_env__$private$should_stop) {
        stream_state$reason <- "error"
        record_run_failure(agent, "compaction", error)
        rlang::cnd_signal(error)
      }
    }
  )
  active_run_id <- stream_state$active_run_id

  if (agent$.__enclos_env__$private$should_stop) {
    stream <- empty_run_stream()
  } else {
    stream <- tryCatch(
      agent$.__enclos_env__$private$start_async_stream(
        messages = messages,
        tool_mode = tool_mode,
        stream = stream_mode,
        controller = agent$.__enclos_env__$private$current_stream_controller,
        structured = structured,
        stream_type = stream_type
      ),
      error = function(error) {
        promises::promise_reject(error)
      }
    )
  }
  is_generator <- inherits(stream, "coro_generator_instance")

  # One pass per iteration: a model stream, then the hooks at its stop.
  repeat {
    repeat {
      if (agent$.__enclos_env__$private$should_stop) {
        stream_state$reason <-
          agent$.__enclos_env__$private$stop_reason_from_hook %||%
          "interrupted"
        break
      }

      stream_error <- NULL
      chunk <- NULL
      if (isTRUE(is_generator)) {
        chunk <- tryCatch(
          with_run_trace(stream_state, stream()),
          error = function(error) {
            stream_error <<- error
            NULL
          }
        )
      } else {
        chunk <- stream
      }

      if (is.null(stream_error) && promises::is.promising(chunk)) {
        chunk <- tryCatch(
          coro::await(chunk),
          error = function(error) {
            stream_error <<- error
            NULL
          }
        )
      }

      if (!is.null(stream_error)) {
        if (agent$.__enclos_env__$private$should_stop) {
          stream_state$reason <-
            agent$.__enclos_env__$private$stop_reason_from_hook %||%
            "interrupted"
          break
        }
        stream_state$reason <- "error"
        # Structured requests record dispatch errors before applying
        # validation; a rejected value is a separate run outcome.
        if (is.null(structured) && is.null(stream_state$failure_phase)) {
          record_model_failure(agent, stream_error)
        }
        if (
          is.null(stream_state$failure_phase) &&
            try_chat_fallback(agent, stream_error)
        ) {
          stream <- tryCatch(
            agent$.__enclos_env__$private$start_async_stream(
              messages,
              tool_mode,
              stream_mode,
              agent$.__enclos_env__$private$current_stream_controller,
              structured,
              stream_type
            ),
            error = function(error) promises::promise_reject(error)
          )
          stream_state$reason <- "complete"
          is_generator <- inherits(stream, "coro_generator_instance")
          next
        }
        if (agent$.__enclos_env__$private$should_stop) {
          stream_state$reason <- agent$.__enclos_env__$private$stop_reason_from_hook
          break
        }
        stream_state$reason <- "error"
        record_run_failure(
          agent,
          stream_state$failure_phase %||%
            if (is.null(structured)) "stream" else "structured_output",
          stream_error
        )
        rlang::cnd_signal(stream_error)
      }

      if (agent$.__enclos_env__$private$should_stop) {
        stream_state$reason <-
          agent$.__enclos_env__$private$stop_reason_from_hook %||%
          "interrupted"
        break
      }

      if (coro::is_exhausted(chunk)) {
        break
      }

      stream_state$response_seen <- TRUE
      if (!is.null(structured)) {
        stream_state$structured_output <- chunk
      }

      if (inherits(chunk, "ellmer::ContentToolRequest")) {
        extracted <- agent$.__enclos_env__$private$extract_tool_request_data(
          chunk
        )
        agent$.__enclos_env__$private$record_run_event(
          agent$.__enclos_env__$private$tool_start_event(extracted)
        )
      } else if (inherits(chunk, "ellmer::ContentToolResult")) {
        stream_state$response_parts <- character()
      } else if (inherits(chunk, "ellmer::ContentText")) {
        stream_state$response_parts <- c(
          stream_state$response_parts,
          chunk@text
        )
        agent$.__enclos_env__$private$record_run_event(
          AgentEvent(
            "text",
            run_id = active_run_id,
            text = chunk@text,
            is_complete = FALSE
          )
        )
      } else if (is.character(chunk) && length(chunk) == 1L) {
        stream_state$response_parts <- c(
          stream_state$response_parts,
          chunk
        )
        agent$.__enclos_env__$private$record_run_event(
          AgentEvent(
            "text",
            run_id = active_run_id,
            text = chunk,
            is_complete = FALSE
          )
        )
      } else if (
        !inherits(chunk, "ellmer::ContentToolRequest") &&
          !inherits(chunk, "ellmer::ContentToolResult")
      ) {
        agent$.__enclos_env__$private$record_run_event(
          AgentEvent(
            "content",
            run_id = active_run_id,
            content = chunk,
            content_type = class(chunk)[[1L]] %||% "unknown"
          )
        )
      }

      coro::yield(chunk)
      if (!isTRUE(is_generator)) {
        break
      }
    }
    if (
      !is.null(extraction) &&
        !agent$.__enclos_env__$private$should_stop &&
        agent$.__enclos_env__$private$current_tool_calls <=
          agent$.__enclos_env__$private$current_tool_results
    ) {
      extracted_output <- tryCatch(
        coro::await(governed_structured_request(
          agent,
          list(
            "Extract the requested structured result from the completed task and conversation."
          ),
          extraction
        )),
        error = function(error) {
          if (!agent$.__enclos_env__$private$should_stop) {
            record_run_failure(agent, "extraction", error)
            stream_state$reason <- "error"
            rlang::cnd_signal(error)
          }
          NULL
        }
      )
      stream_state$structured_output <- extracted_output
    }
    held <- agent$.__enclos_env__$private$take_held_hooks()
    if (length(held)) {
      coro::await(promises::promise_all(.list = held))
    }
    # Stop and SessionEnd fire in the body only once the run has started a
    # session, as finish_callback_run() does for the other endings.
    stop_answer <- NULL
    if (isTRUE(stream_state$session_started)) {
      agent$.__enclos_env__$private$settle_run(stream_state)
      stream_state$stop_hook_fired <- TRUE
      stop_answer <- agent$.__enclos_env__$private$fire_end_hook(
        "Stop",
        stream_state
      )
      if (promises::is.promising(stop_answer)) {
        stop_answer <- coro::await(stop_answer)
      }
      # An interrupt that arrived while the hook was pending takes effect now.
      agent$.__enclos_env__$private$settle_run(stream_state)
    }
    # A Stop hook may send an answered run on. Nothing else is sent on: a run
    # that was stopped, hit a limit or failed ends as it stands.
    if (
      S7::S7_inherits(stop_answer, HookResultStop) &&
        # The ending, not the reason: an answer the provider cut short has
        # the reason "complete" too.
        S7::S7_inherits(
          agent$.__enclos_env__$private$run_ending_now(stream_state),
          RunEndingAnswered
        ) &&
        !agent$.__enclos_env__$private$should_stop &&
        is.null(structured)
    ) {
      stream_state$stop_hook_active <- TRUE
      stream_state$stop_hook_fired <- FALSE
      # The result's response is the last pass's text.
      stream_state$response_parts <- character()
      stream_state$structured_output <- NULL
      stream <- tryCatch(
        agent$.__enclos_env__$private$start_async_stream(
          messages = list(stop_answer@message),
          tool_mode = tool_mode,
          stream = stream_mode,
          controller = agent$.__enclos_env__$private$current_stream_controller,
          structured = NULL,
          stream_type = stream_type
        ),
        error = function(error) {
          # A limit can refuse the request as the stream is made. The loop
          # then ends the run on its first check and never reads the stream,
          # so a rejected promise here would have nobody to handle it.
          if (agent$.__enclos_env__$private$should_stop) {
            return(empty_run_stream())
          }
          promises::promise_reject(error)
        }
      )
      is_generator <- inherits(stream, "coro_generator_instance")
      next
    }
    break
  }
  graph_cancel_descendants(agent, "parent_completed")
  if (isTRUE(stream_state$session_started)) {
    stream_state$session_end_fired <- TRUE
    ended <- agent$.__enclos_env__$private$fire_end_hook(
      "SessionEnd",
      stream_state
    )
    if (promises::is.promising(ended)) {
      coro::await(ended)
    }
  }
})
