# Internal R6 methods for agent streaming and governed stream generators.
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
      check_no_active_run(private)
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
      state <- private$new_run_state()
      private$hold_unstarted_run(state)
      governed <- private$run_stream(
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
          agent$.__enclos_env__$private$release_unstarted_run(state)
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
              agent$.__enclos_env__$private$finish_run(state),
              silent = TRUE
            )
          }
        },
        onexit = TRUE
      )
      list(stream = governed, state = state, limits = limits)
    },

    # Shared preamble for Agent$run() and Agent$run_async().
    start_task_run = function(
      task,
      usage_limits = NULL,
      run_context = list(),
      type = NULL,
      validate = NULL,
      max_corrections = 0L
    ) {
      structured <- structured_run_spec(type, validate, max_corrections)
      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )
      limits <- private$run_usage_limits(usage_limits)
      private$start_governed_stream(
        messages = list(task),
        limits = limits,
        run_context = effective_run_context,
        stream = "content",
        extraction = structured
      )
    },

    # Shared preamble for Agent$stream() and Agent$stream_async().
    start_chat_stream = function(
      messages,
      tool_mode = "concurrent",
      stream = "text",
      controller = NULL,
      run_context = list(),
      type = NULL,
      usage_limits = NULL
    ) {
      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )
      limits <- private$run_usage_limits(usage_limits)
      governed_run <- private$start_governed_stream(
        messages = messages,
        limits = limits,
        run_context = effective_run_context,
        tool_mode = tool_mode,
        stream = stream,
        controller = controller,
        stream_type = type
      )
      reset_stream_controller(controller)
      governed_run
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

    # The single run kernel. Every public run interface is an adapter
    # over this lazily-started governed stream.
    run_stream = function(
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

governed_stream_start_pass <- function(
  private,
  messages,
  tool_mode,
  stream_mode,
  structured,
  stream_type,
  empty_on_stop = FALSE
) {
  tryCatch(
    private$start_async_stream(
      messages = messages,
      tool_mode = tool_mode,
      stream = stream_mode,
      controller = private$current_stream_controller,
      structured = structured,
      stream_type = stream_type
    ),
    error = function(error) {
      # A limit can refuse the request as the stream is made. The loop
      # then ends the run on its first check and never reads the stream,
      # so a rejected promise here would have nobody to handle it.
      if (isTRUE(empty_on_stop) && isTRUE(private$should_stop)) {
        return(empty_run_stream())
      }
      promises::promise_reject(error)
    }
  )
}

governed_stream_record_chunk <- function(
  private,
  stream_state,
  active_run_id,
  structured,
  chunk
) {
  stream_state$response_seen <- TRUE
  if (!is.null(structured)) {
    stream_state$structured_output <- chunk
  }
  if (inherits(chunk, "ellmer::ContentToolRequest")) {
    extracted <- private$extract_tool_request_data(chunk)
    private$record_run_event(private$tool_start_event(extracted))
  } else if (inherits(chunk, "ellmer::ContentToolResult")) {
    stream_state$response_parts <- character()
  } else if (inherits(chunk, "ellmer::ContentText")) {
    stream_state$response_parts <- c(stream_state$response_parts, chunk@text)
    private$record_run_event(AgentEvent(
      "text",
      run_id = active_run_id,
      text = chunk@text,
      is_complete = FALSE
    ))
  } else if (is.character(chunk) && length(chunk) == 1L) {
    stream_state$response_parts <- c(stream_state$response_parts, chunk)
    private$record_run_event(AgentEvent(
      "text",
      run_id = active_run_id,
      text = chunk,
      is_complete = FALSE
    ))
  } else {
    private$record_run_event(AgentEvent(
      "content",
      run_id = active_run_id,
      content = chunk,
      content_type = class(chunk)[[1L]] %||% "unknown"
    ))
  }
  invisible(NULL)
}

# A Stop hook may send an answered run on. Nothing else is sent on: a run
# that was stopped, hit a limit or failed ends as it stands.
governed_stream_should_continue <- function(
  private,
  stream_state,
  stop_answer,
  structured
) {
  S7::S7_inherits(stop_answer, HookResultStop) &&
    # The ending, not the reason: an answer the provider cut short has
    # the reason "complete" too.
    S7::S7_inherits(
      private$run_ending_now(stream_state),
      RunEndingAnswered
    ) &&
    !private$should_stop &&
    is.null(structured)
}

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
  private <- agent$.__enclos_env__$private
  tryCatch(
    {
      check_conversation_lease(agent, conversation_token)
      check_no_active_run(private)
    },
    error = function(error) {
      refuse_unstarted_run(agent, stream_state, error)
      rlang::cnd_signal(error)
    }
  )

  on.exit(private$finish_run(stream_state), add = TRUE)
  tryCatch(
    {
      initialize_agent_run(
        agent,
        stream_state,
        messages,
        run_limits,
        effective_run_context,
        controller,
        stream_mode
      )
      started <- run_start_hooks(agent, stream_state, messages)
      if (promises::is.promising(started)) {
        coro::await(started)
      }
    },
    error = function(error) {
      stream_state$reason <- "error"
      # A Chat another Agent holds refuses the run before it has an ID.
      refuse_unstarted_run(agent, stream_state, error)
      record_run_failure(agent, "initialization", error)
      rlang::cnd_signal(error)
    }
  )
  if (
    !private$should_stop ||
      identical(
        private$.approval_resume$record$decision$decision,
        "deny"
      )
  ) {
    tryCatch(
      private$execute_approval_resume(),
      error = function(error) {
        stream_state$reason <- "error"
        record_run_failure(agent, "approval_resume", error)
        rlang::cnd_signal(error)
      }
    )
  }
  tryCatch(
    coro::await(private$maybe_auto_compact(messages)),
    error = function(error) {
      if (!private$should_stop) {
        stream_state$reason <- "error"
        record_run_failure(agent, "compaction", error)
        rlang::cnd_signal(error)
      }
    }
  )
  active_run_id <- stream_state$active_run_id

  if (private$should_stop) {
    stream <- empty_run_stream()
  } else {
    stream <- governed_stream_start_pass(
      private,
      messages,
      tool_mode,
      stream_mode,
      structured,
      stream_type
    )
  }
  is_generator <- inherits(stream, "coro_generator_instance")

  # One pass per iteration: a model stream, then the hooks at its stop.
  repeat {
    repeat {
      if (private$should_stop) {
        stream_state$reason <- private$stop_reason %||% "interrupted"
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
        # A failed answer request leaves the run on the limit that asked it.
        if (isTRUE(stream_state$wrap_up_active)) {
          break
        }
        if (private$should_stop) {
          stream_state$reason <- private$stop_reason %||% "interrupted"
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
          stream <- governed_stream_start_pass(
            private,
            messages,
            tool_mode,
            stream_mode,
            structured,
            stream_type
          )
          stream_state$reason <- "complete"
          is_generator <- inherits(stream, "coro_generator_instance")
          next
        }
        if (private$should_stop) {
          stream_state$reason <- private$stop_reason %||% "interrupted"
          break
        }
        stream_state$reason <- "error"
        record_run_failure(
          agent,
          stream_state$failure_phase %||%
            if (is.null(structured)) "stream" else "structured_output",
          stream_error
        )
        # Background tasks end with the run that started them.
        joined <- background_join(agent, "parent_failed")
        if (promises::is.promising(joined)) {
          coro::await(joined)
        }
        rlang::cnd_signal(stream_error)
      }

      if (private$should_stop) {
        stream_state$reason <- private$stop_reason %||% "interrupted"
        break
      }

      if (coro::is_exhausted(chunk)) {
        break
      }

      governed_stream_record_chunk(
        private,
        stream_state,
        active_run_id,
        structured,
        chunk
      )

      coro::yield(chunk)
      if (!isTRUE(is_generator)) {
        break
      }
    }
    if (isTRUE(stream_state$wrap_up_active)) {
      restore_error <- limit_wrap_up_end(agent, stream_state)
      if (!is.null(restore_error)) {
        rlang::cnd_signal(restore_error)
      }
    }
    # The pass is over, so nothing can collect a background task now: they
    # are stopped and settle before the run does, and its usage has theirs.
    joined <- background_join(
      agent,
      if (private$should_stop) {
        private$stop_reason %||% "interrupted"
      } else {
        "parent_completed"
      }
    )
    if (promises::is.promising(joined)) {
      coro::await(joined)
    }
    if (
      !is.null(extraction) &&
        !private$should_stop &&
        private$current_tool_calls <= private$current_tool_results
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
          if (!private$should_stop) {
            record_run_failure(agent, "extraction", error)
            stream_state$reason <- "error"
            rlang::cnd_signal(error)
          }
          NULL
        }
      )
      stream_state$structured_output <- extracted_output
    }
    # A request or tool-call limit that ended the run in the middle of its
    # work leaves the model one request, without tools, to answer.
    answer <- limit_wrap_up_start(
      agent,
      stream_state,
      tool_mode,
      stream_mode,
      stream_type,
      structured,
      extraction
    )
    if (!is.null(answer)) {
      stream <- answer
      is_generator <- inherits(stream, "coro_generator_instance")
      next
    }
    held <- private$take_held_hooks()
    if (length(held)) {
      coro::await(promises::promise_all(.list = held))
    }
    stop_answer <- private$stop_in_body(stream_state)
    if (promises::is.promising(stop_answer)) {
      stop_answer <- coro::await(stop_answer)
    }
    if (
      governed_stream_should_continue(
        private,
        stream_state,
        stop_answer,
        structured
      )
    ) {
      stream_state$stop_hook_active <- TRUE
      stream_state$stop_hook_fired <- FALSE
      # The result's response is the last pass's text.
      stream_state$response_parts <- character()
      stream_state$structured_output <- NULL
      stream <- governed_stream_start_pass(
        private,
        messages = list(stop_answer@message),
        tool_mode = tool_mode,
        stream_mode = stream_mode,
        structured = NULL,
        stream_type = stream_type,
        empty_on_stop = TRUE
      )
      is_generator <- inherits(stream, "coro_generator_instance")
      next
    }
    break
  }
  ended <- private$session_end_in_body(stream_state)
  if (promises::is.promising(ended)) {
    coro::await(ended)
  }
})
