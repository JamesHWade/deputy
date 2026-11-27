# Shared lifecycle for model runs and host-driven delegation batches:
# run-state initialization, settlement, end hooks, and active-run teardown.

check_no_active_run <- function(private) {
  if (isTRUE(private$run_active)) {
    cli::cli_abort(
      "This agent already has an active run",
      class = c("deputy_run_active", "deputy_error")
    )
  }
  invisible(NULL)
}

# Reset per-run mutable fields on `private` at both run start and run finish so
# initialization and teardown stay aligned.
reset_run_private_state <- function(private) {
  private$should_stop <- FALSE
  private$stop_reason <- NULL
  private$stop_requested_by <- NULL
  private$current_tool_calls <- 0L
  private$current_tool_results <- 0L
  private$current_outer_requests <- 0L
  private$tool_started_at <- list()
  private$tool_event_overrides <- list()
  private$tool_call_records <- list()
  private$trusted_arguments <- list()
  private$pending_delegations <- list()
  private$held_hooks <- list()
  private$original_tool_results <- list()
  private$last_tool_cycle_signature <- NULL
  private$consecutive_tool_cycles <- 0L
  invisible(NULL)
}

# Capture whether a run has ended since an async hook was dispatched.
run_over_checker <- function(private) {
  hook_run_id <- private$current_run_id
  hook_in_run <- isTRUE(private$run_active)
  function() {
    hook_in_run &&
      (!isTRUE(private$run_active) ||
        !identical(private$current_run_id, hook_run_id))
  }
}

record_run_failure <- function(agent, phase, condition) {
  private <- agent$.__enclos_env__$private
  state <- private$current_run_state
  if (!is.null(state)) {
    state$run_error <- list(phase = phase, condition = condition)
  }
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
  runtime_chat <- private$.chat
  tracked_runtime <- isTRUE(attr(
    runtime_chat,
    "deputy_retained_runtime",
    exact = TRUE
  ))
  if (!is.null(attr(runtime_chat, "deputy_active_runtime", exact = TRUE))) {
    conversation_abort(
      "Wait for the active run before accessing this shared Chat."
    )
  }
  private$run_active <- TRUE
  private$current_run_id <- private$new_run_id()
  private$current_run_context <- run_context
  active_run_id <- private$current_run_id
  state$active_run_id <- active_run_id
  state$run_context <- run_context
  state$limits <- limits
  state$runtime_chat <- runtime_chat
  state$runtime_token <- active_run_id
  attr(runtime_chat, "deputy_active_runtime") <- active_run_id

  # Initialize lazily on first consumption. Merely constructing and
  # abandoning a stream must not reserve this Agent forever.
  reset_run_private_state(private)
  private$current_usage_limits <- limits
  private$current_usage_baseline <- agent_usage_snapshot(private$.chat)
  state$turns_before <- length(private$.chat$get_turns())
  background_reset(agent)
  private$current_external_usage <- if (is.null(private$.approval_resume)) {
    initial_usage
  } else {
    approval_usage(private$.approval_resume$record$usage)
  }
  private$.approval_requests <- list()
  private$.approval_journal <- if (is.null(private$.approval_resume)) {
    list()
  } else {
    private$.approval_resume$record$effects
  }
  private$current_stream_controller <-
    controller %||%
    tryCatch(
      ellmer::stream_controller(),
      error = function(e) NULL
    )
  private$current_run_state <- state
  private$release_unstarted_run(state)
  if (!is.null(state$interrupt_before_start)) {
    private$request_stream_stop(
      state$interrupt_before_start,
      by = state$interrupt_before_start_by %||% "caller"
    )
  }
  state$response_seen <- FALSE
  state$fallback_index <- private$.fallback_position
  state$request_number <- 0L
  state$task_requests <- 0L
  state$failure_phase <- NULL
  state$request_turns_before <- state$turns_before
  state$model_failure <- NULL
  state$dispatch_turns <- private$.chat$get_turns()
  state$trace_conversation_id <- private$.conversation_id %||%
    private$.inherited_conversation_id %||%
    private$.session_id
  state$trace_span <- start_run_trace(agent, state)
  # Retention rewires the Chat to its specialist. After release, whichever
  # wrapper dispatches next must supply its own adapters and governance.
  if (tracked_runtime && is.null(private$.conversation_owner)) {
    private$rewire_chat_runtime()
  }
  install_request_callbacks(agent)
  private$last_limit_status <- NULL
  private$last_run_usage <- AgentUsage()
  tree_run_started(agent)

  checkpoint_id <- NULL
  if (!is.null(private$.file_checkpoints)) {
    checkpoint_id <- private$.file_checkpoints$checkpoint(
      paste0("run ", active_run_id),
      metadata = list(
        run_id = active_run_id,
        message_count = length(messages)
      )
    )
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
      checkpoint_id = checkpoint_id
    )
  )
  if (!is.null(checkpoint_id)) {
    private$record_run_event(
      private$agent_event(
        "file_checkpoint",
        checkpoint_id = checkpoint_id,
        name = paste0("run ", active_run_id)
      )
    )
  }

  invisible(state)
}

# A stream that fails before its run has an ID leaves no result and nothing
# to finish. It is no longer waiting to start, and whoever holds the promise
# of its result is told why.
refuse_unstarted_run <- function(agent, state, error) {
  if (!is.null(state$active_run_id) || isTRUE(state$finished)) {
    return(invisible(NULL))
  }
  private <- agent$.__enclos_env__$private
  state$finished <- TRUE
  state$start_error <- error
  private$release_unstarted_run(state)
  if (is.function(state$reject_result)) {
    state$reject_result(error)
  }
  invisible(NULL)
}

# The hooks at a run's start: SessionStart, then UserPromptSubmit, then the
# check of limits the run has already reached. Returns a promise when a
# callback returned one, for the run to wait on.
run_start_hooks <- function(agent, state, messages) {
  private <- agent$.__enclos_env__$private
  stopped_before <- isTRUE(private$should_stop)
  started <- fire_session_start(agent, state)
  hook_then(started, function(value) {
    state$session_started <- TRUE
    # A stop that came while SessionStart was being asked takes effect now,
    # whether its promise was pending or its callback made the stop: the
    # prompt is not submitted, and no later hook can hold the stop.
    stopped_meanwhile <- !stopped_before && isTRUE(private$should_stop)
    submitted <- if (!stopped_meanwhile) {
      fire_prompt_submit(agent, state, messages)
    }
    hook_then(submitted, function(value) {
      check_initial_run_limits(agent, state)
      invisible(NULL)
    })
  })
}

# The SessionStart hook for a run. Returns what `fire_hook()` returned: a
# value, or a promise when a callback returned one.
fire_session_start <- function(agent, state) {
  private <- agent$.__enclos_env__$private
  private$fire_hook(
    "SessionStart",
    context = private$hook_context(
      permissions = agent$permissions,
      provider = agent$provider(),
      tools_count = length(private$.chat$get_tools()),
      run_id = state$active_run_id
    )
  )
}

# The UserPromptSubmit hook for a run's messages. Returns what `fire_hook()`
# returned: a value, or a promise when a callback returned one.
fire_prompt_submit <- function(agent, state, messages) {
  private <- agent$.__enclos_env__$private
  private$fire_hook(
    "UserPromptSubmit",
    prompt = if (length(messages) == 1L) messages[[1L]] else messages,
    context = private$hook_context(
      run_id = state$active_run_id
    )
  )
}

# Ends the run before its first request when its limits are already reached.
check_initial_run_limits <- function(agent, state) {
  private <- agent$.__enclos_env__$private
  initial_limit_status <- private$limit_status(require_followup = TRUE)
  if (!is.null(initial_limit_status)) {
    private$mark_usage_limit(initial_limit_status)
    state$reason <- initial_limit_status$reason
  }
  invisible(state)
}

# Internal R6 methods for run state, settlement, end hooks, and teardown.
# R6 binds these methods to the same self/private environments as the facade.
deputy_agent_run_state_methods <- function(self = NULL, private = NULL) {
  list(
    # `by` names who asked for the stop (see RunEnding). A stop with no `by`
    # clears any earlier one, so a limit's stop is not credited to a caller.
    request_stream_stop = function(reason, by = NULL) {
      private$should_stop <- TRUE
      private$stop_reason <- reason
      private$stop_requested_by <- by
      # The runs below are stopped by their caller, this run, unless the stop
      # is a parent's end coming down the tree.
      graph_cancel_descendants(
        self,
        reason,
        by = if (identical(by, "parent")) "parent" else "caller"
      )
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

    # Shared state for one governed run.
    # The stream body and its exit handler communicate through this env so a
    # consumer can read the terminal reason, usage, and cost after the stream
    # is exhausted and run-scoped private fields have been cleared.
    new_run_state = function() {
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
      state$finish_reason <- NULL
      state$wrap_up_active <- FALSE
      state$wrap_up_done <- FALSE
      state$wrap_up_answered <- FALSE
      state$wrap_up_requests <- 0L
      state$wrap_up_saved <- NULL
      state$run_error <- NULL
      state$cost_warned <- FALSE
      state$stop_hook_active <- FALSE
      state$stop_hook_fired <- FALSE
      state$session_end_fired <- FALSE
      state$ended <- FALSE
      state$result_promise <- NULL
      state$resolve_result <- NULL
      state$reject_result <- NULL
      state$interrupt_before_start <- NULL
      state
    },

    # Assemble the `AgentResult` for a finished run.
    run_result = function(state) {
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
        finish_reason = state$finish_reason,
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

    # Settles the run's reason, usage, cost and limit, the facts a Stop hook
    # reads. Called from the run's body before Stop and from finish_run();
    # each block checks what an earlier call set.
    settle_run = function(state) {
      # Once SessionEnd has been told how the run ended, that is how it
      # ended: a stop that arrives while that hook is pending has nothing
      # left to stop.
      if (isTRUE(state$ended)) {
        return(invisible(NULL))
      }
      # The last turn is read before the reason is settled, as the finishing
      # code always did: a Chat may deliver a pending tool result when its
      # last turn is read, and a hook's stop from that result counts.
      tryCatch(private$.chat$last_turn(), error = function(e) NULL)
      if (isTRUE(private$should_stop) && identical(state$reason, "complete")) {
        state$reason <- private$stop_reason %||% "hook_requested_stop"
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
        limit_status <- private$limit_status(
          require_followup = FALSE,
          usage = usage,
          limits = limits
        )
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
      # It reads the cost the limit is checked against.
      limited_cost <- if (!is.null(limits$max_cost_usd)) {
        usage_against_limits(usage, limits)$max_cost_usd
      }
      if (
        is.null(private$last_limit_status) &&
          !isTRUE(state$cost_warned) &&
          !is.null(limited_cost) &&
          is.finite(limited_cost) &&
          limited_cost >= limits$max_cost_usd * 0.9
      ) {
        state$cost_warned <- TRUE
        private$notify(
          paste0(
            "Approaching run cost limit: ",
            format_cost(limited_cost),
            " / ",
            format_cost(limits$max_cost_usd)
          ),
          level = "warning",
          code = "cost_limit_warning",
          usage = usage,
          max_cost_usd = limits$max_cost_usd
        )
        cli::cli_warn(
          "Approaching run cost limit: {format_cost(limited_cost)} / {format_cost(limits$max_cost_usd)}"
        )
      }
      invisible(NULL)
    },

    # The provider's finish reason for the run's final response, or NULL.
    run_finish_reason = function(state) {
      turns <- private$.chat$get_turns()
      added <- max(0L, length(turns) - state$turns_before)
      for (turn in rev(utils::tail(turns, added))) {
        if (inherits(turn, "ellmer::AssistantTurn")) {
          reason <- turn@finish_reason
          return(if (rlang::is_string(reason)) reason else NULL)
        }
      }
      NULL
    },

    # The run's RunEnding as it stands. Built from the same facts for the
    # hooks that read it and for the run's result.
    run_ending_now = function(state) {
      finish_reason <- private$run_finish_reason(state)
      run_ending_for(
        state$reason,
        # Who asked matters only when the run's reason is the one they gave.
        by = if (
          isTRUE(private$should_stop) &&
            identical(state$reason, private$stop_reason)
        ) {
          private$stop_requested_by
        },
        limit_status = private$last_limit_status,
        finish_reason = finish_reason,
        error = state$run_error$condition,
        phase = state$run_error$phase,
        wrapped_up = isTRUE(state$wrap_up_answered)
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

    # Stop, fired from the body of a run, where the run can wait for the
    # answer. Returns the hook's answer, or a promise of it.
    stop_in_body = function(state) {
      # Stop and SessionEnd fire only once the run has started a session, as
      # finish_run() has it for the other endings.
      if (!isTRUE(state$session_started)) {
        return(NULL)
      }
      private$settle_run(state)
      state$stop_hook_fired <- TRUE
      hook_then(private$fire_end_hook("Stop", state), function(answer) {
        # An interrupt that arrived while the hook was pending takes effect now.
        private$settle_run(state)
        answer
      })
    },

    # SessionEnd, fired from the body of a run once nothing can send it on.
    # Returns a promise when a callback returned one.
    session_end_in_body = function(state) {
      graph_cancel_descendants(self, "parent_completed", by = "parent")
      if (!isTRUE(state$session_started)) {
        return(NULL)
      }
      state$session_end_fired <- TRUE
      state$ended <- TRUE
      private$fire_end_hook("SessionEnd", state)
    },

    # Terminal accounting for a governed run: settles the stop reason, fires
    # Stop/SessionEnd, records run-scoped usage and cost on `state`, and
    # releases the active run.
    finish_run = function(state) {
      active_run_id <- state$active_run_id
      if (
        isTRUE(state$finished) ||
          is.null(active_run_id) ||
          !identical(private$current_run_id, active_run_id)
      ) {
        return(invisible(NULL))
      }
      state$finished <- TRUE
      graph_cancel_descendants(self, "parent_completed", by = "parent")
      # A run's body joins its background tasks before it gets here. A run
      # that never reached that point, such as a stream dropped unread, still
      # asks them to stop; they settle on their own.
      background_join(self, "parent_completed")
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

      # A stream dropped during the answer request still gives the tools back.
      cleanup_error <- limit_wrap_up_end(self, state)
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
          last_turn <- if (current_turn_count > state$turns_before) {
            observed_last_turn
          } else {
            NULL
          }
          if (!is.null(last_turn)) {
            private$record_run_event(private$agent_event(
              "turn",
              turn = last_turn,
              turn_number = max(1L, usage$requests)
            ))
          }
          state$finish_reason <- private$run_finish_reason(state)
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
          state$result <- private$run_result(state)
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
          cleanup_error <<- cleanup_error %||% error
        }
      )

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

    # A stream that was made waits to start until it is first read. The agent
    # holds the state of each one, so an interrupt reaches them all.
    hold_unstarted_run = function(state) {
      private$unstarted_runs <- c(private$unstarted_runs, list(state))
      invisible(NULL)
    },

    # The stream has started, was refused, or was dropped unread.
    release_unstarted_run = function(state) {
      private$unstarted_runs <- Filter(
        function(waiting) !identical(waiting, state),
        private$unstarted_runs
      )
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
      private$release_unstarted_run(private$current_run_state)
      checkpoint_error <- NULL
      tryCatch(
        private$finalize_pending_checkpoints(),
        error = function(error) {
          checkpoint_error <<- error
        }
      )
      reset_run_private_state(private)
      private$current_stream_controller <- NULL
      private$current_usage_limits <- NULL
      private$current_usage_baseline <- NULL
      private$current_external_usage <- NULL
      private$current_run_state <- NULL
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
