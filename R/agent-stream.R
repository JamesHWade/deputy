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
      stream_type = NULL
    ) {
      if (isTRUE(private$run_active)) {
        cli::cli_abort(
          "This agent already has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }
      limits <- normalize_usage_limits(limits)
      state <- private$new_callback_run_state()
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
        state = state
      )
      agent <- self
      reg.finalizer(
        environment(governed),
        function(environment) {
          if (
            !isTRUE(state$finished) &&
              !is.null(state$active_run_id)
          ) {
            state$reason <- "abandoned"
            try(
              agent$.__enclos_env__$private$request_stream_stop("abandoned"),
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
      stream <- governed_run$stream
      state <- governed_run$state
      coro::async(function() {
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
      })()
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
      agent <- self
      coro::generator(function() {
        repeat {
          chunk <- agent$.__enclos_env__$private$resolve_promise(
            async_stream()
          )
          if (coro::is_exhausted(chunk)) {
            break
          }
          coro::yield(chunk)
        }
      })()
    },

    event_generator = function(
      governed_run,
      include_partial_messages
    ) {
      agent <- self
      async_stream <- governed_run$stream
      state <- governed_run$state
      coro::generator(function() {
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
      })()
    },

    request_stream_stop = function(reason) {
      private$should_stop <- TRUE
      private$stop_reason_from_hook <- reason
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

      AgentResult$new(
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
      state
    ) {
      agent <- self
      stream_state <- state
      effective_run_context <- run_context
      run_limits <- limits

      coro::async_generator(function() {
        if (isTRUE(agent$.__enclos_env__$private$run_active)) {
          cli::cli_abort(
            "This agent already has an active run",
            class = c("deputy_run_active", "deputy_error")
          )
        }

        compaction <- agent$.__enclos_env__$private$maybe_auto_compact(
          messages,
          limits = run_limits,
          usage = AgentUsage()
        )
        compaction_usage <- AgentUsage()
        if (!is.null(compaction)) {
          compaction_usage <- compaction$usage
        }

        on.exit(
          agent$.__enclos_env__$private$finish_callback_run(stream_state),
          add = TRUE
        )
        initialize_agent_run(
          agent,
          stream_state,
          messages,
          run_limits,
          effective_run_context,
          controller,
          stream_mode,
          compaction_usage
        )
        active_run_id <- stream_state$active_run_id

        if (agent$.__enclos_env__$private$should_stop) {
          stream <- coro::async_generator(function() {
            if (FALSE) coro::yield("unreachable")
          })()
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
            record_model_failure(agent, stream_error)
            if (try_chat_fallback(agent, stream_error)) {
              stream <- agent$.__enclos_env__$private$start_async_stream(
                messages,
                tool_mode,
                stream_mode,
                agent$.__enclos_env__$private$current_stream_controller,
                structured,
                stream_type
              )
              is_generator <- inherits(stream, "coro_generator_instance")
              next
            }
            if (agent$.__enclos_env__$private$should_stop) {
              stream_state$reason <- agent$.__enclos_env__$private$stop_reason_from_hook
              break
            }
            stream_state$reason <- "error"
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
          !is.null(extraction) && !agent$.__enclos_env__$private$should_stop
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
                stream_state$reason <- "error"
                rlang::cnd_signal(error)
              }
              NULL
            }
          )
          stream_state$structured_output <- extracted_output
        }
      })()
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
      on.exit(finish_run_trace(state), add = TRUE)
      on.exit(remove_request_callbacks(private$.chat), add = TRUE)

      cleanup_error <- NULL
      tryCatch(
        {
          observed_last_turn <- tryCatch(
            private$.chat$last_turn(),
            error = function(e) NULL
          )
          if (
            isTRUE(private$should_stop) && identical(state$reason, "complete")
          ) {
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
            limit_status <- usage_limit_status(usage, limits)
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
          if (
            is.null(private$last_limit_status) &&
              !is.null(limits$max_cost_usd) &&
              is.finite(usage$cost_usd) &&
              usage$cost_usd >= limits$max_cost_usd * 0.9
          ) {
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
          if (isTRUE(state$session_started)) {
            private$fire_hook(
              "Stop",
              reason = state$reason,
              context = private$hook_context(
                cost = self$cost(),
                usage = usage,
                run_id = active_run_id
              )
            )
            private$fire_hook(
              "SessionEnd",
              reason = state$reason,
              context = private$hook_context(
                cost = self$cost(),
                usage = usage,
                run_id = active_run_id
              )
            )
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
            limit = private$last_limit_status
          ))
          state$result <- private$callback_run_result(state)
          private$.last_run_result <- state$result

          limit_status <- private$last_limit_status
          if (
            !is.null(limit_status) &&
              identical(state$limits$on_exceed, "error") &&
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
      tryCatch(
        private$finish_active_run(),
        error = function(error) {
          if (is.null(cleanup_error)) {
            cleanup_error <<- error
          }
        }
      )
      if (!is.null(cleanup_error)) {
        stop(cleanup_error)
      }
      invisible(NULL)
    },

    finish_active_run = function() {
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
