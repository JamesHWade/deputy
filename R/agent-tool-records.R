# Internal R6 methods for agent tool records.
# R6 binds these methods to the same self/private environments as the facade.
deputy_agent_tool_records_methods <- function(self = NULL, private = NULL) {
  list(
    tool_call_record = function(extracted, phase) {
      phase <- match.arg(phase, c("start", "request", "result", "end"))
      tool_name <- extracted$tool_name %||% "unknown"
      tool_name <- as.character(tool_name[[1L]])
      provider_tool_call_id <- extracted$provider_tool_call_id
      if (
        is.null(provider_tool_call_id) ||
          length(provider_tool_call_id) != 1L ||
          is.na(provider_tool_call_id) ||
          !nzchar(as.character(provider_tool_call_id))
      ) {
        provider_tool_call_id <- NULL
      } else {
        provider_tool_call_id <- as.character(provider_tool_call_id)
      }

      records <- private$tool_call_records
      index <- NULL
      if (!is.null(provider_tool_call_id)) {
        matches <- which(vapply(
          records,
          function(record) {
            identical(record$provider_tool_call_id, provider_tool_call_id)
          },
          logical(1)
        ))
        if (length(matches) > 0L) {
          index <- matches[[1L]]
        }
      } else if (length(records) > 0L) {
        phase_field <- paste0(phase, "_seen")
        matches <- which(vapply(
          records,
          function(record) {
            is.null(record$provider_tool_call_id) &&
              identical(record$tool_name, tool_name) &&
              !isTRUE(record[[phase_field]])
          },
          logical(1)
        ))
        if (length(matches) > 0L) {
          index <- matches[[1L]]
        }
      }

      if (is.null(index)) {
        if (is.null(provider_tool_call_id)) {
          ambiguous <- any(vapply(
            records,
            function(record) {
              is.null(record$provider_tool_call_id) &&
                identical(record$tool_name, tool_name) &&
                !isTRUE(record$end_seen)
            },
            logical(1)
          ))
          if (isTRUE(ambiguous)) {
            cli_abort(
              c(
                "Cannot correlate concurrent tool calls without provider IDs.",
                "i" = paste0(
                  "The provider must supply a non-empty tool request ID for ",
                  "concurrent calls to the same tool."
                )
              ),
              class = c(
                "deputy_tool_correlation_error",
                "deputy_error"
              )
            )
          }
        }
        index <- length(records) + 1L
        records[[index]] <- list(
          tool_call_id = provider_tool_call_id %||%
            new_deputy_id("tool_"),
          provider_tool_call_id = provider_tool_call_id,
          tool_name = tool_name,
          delegation_id = if (identical(tool_name, "delegate_to_agent")) {
            new_deputy_id("delegation_")
          } else {
            NULL
          },
          delegation_queued = FALSE,
          execution_started = FALSE,
          start_seen = FALSE,
          request_seen = FALSE,
          result_seen = FALSE,
          end_seen = FALSE
        )
      }

      record <- records[[index]]
      record[[paste0(phase, "_seen")]] <- TRUE
      records[[index]] <- record
      private$tool_call_records <- records
      record$record_index <- index
      record
    },

    begin_tool_execution = function(tool_name) {
      records <- private$tool_call_records
      matches <- which(vapply(
        records,
        function(record) {
          identical(record$tool_name, tool_name) &&
            isTRUE(record$request_seen) &&
            !isTRUE(record$result_seen) &&
            !isTRUE(record$execution_started)
        },
        logical(1)
      ))
      if (length(matches) == 0L) {
        return(NULL)
      }

      index <- matches[[1L]]
      records[[index]]$execution_started <- TRUE
      private$tool_call_records <- records
      records[[index]]$tool_call_id
    },

    claim_original_tool_result = function(tool_call_id, fallback) {
      if (
        !is_nonempty_string(tool_call_id) ||
          !tool_call_id %in% names(private$original_tool_results)
      ) {
        return(fallback)
      }
      value <- private$original_tool_results[[tool_call_id]]
      private$original_tool_results[[tool_call_id]] <- NULL
      value
    },

    queue_delegation = function(record) {
      if (
        is.null(record$delegation_id) ||
          isTRUE(record$delegation_queued)
      ) {
        return(invisible(record))
      }
      private$pending_delegations <- c(
        private$pending_delegations,
        list(list(
          tool_call_id = record$tool_call_id,
          delegation_id = record$delegation_id,
          parent_agent_id = private$.agent_id,
          parent_run_id = private$active_run_id(),
          run_context = private$effective_run_context()
        ))
      )
      index <- record$record_index
      private$tool_call_records[[index]]$delegation_queued <- TRUE
      record$delegation_queued <- TRUE
      invisible(record)
    },

    claim_delegation = function() {
      if (length(private$pending_delegations) > 0L) {
        correlation <- private$pending_delegations[[1L]]
        private$pending_delegations <- private$pending_delegations[-1L]
        return(correlation)
      }
      list(
        tool_call_id = NULL,
        delegation_id = new_deputy_id("delegation_"),
        parent_agent_id = private$.agent_id,
        parent_run_id = private$active_run_id(),
        run_context = private$effective_run_context()
      )
    },

    tool_start_event = function(extracted) {
      record <- private$tool_call_record(extracted, "start")
      private$tool_started_at[[record$tool_call_id]] <- Sys.time()
      private$agent_event(
        "tool_start",
        delegation_id = record$delegation_id,
        tool_call_id = record$tool_call_id,
        tool_name = extracted$tool_name,
        tool_input = extracted$tool_input
      )
    },

    tool_end_event = function(extracted) {
      record <- private$tool_call_record(extracted, "end")
      key <- record$tool_call_id
      started_at <- private$tool_started_at[[key]]
      duration <- if (is.null(started_at)) {
        NA_real_
      } else {
        as.numeric(difftime(Sys.time(), started_at, units = "secs"))
      }
      private$tool_started_at[[key]] <- NULL

      override <- private$tool_event_overrides[[key]]
      private$tool_event_overrides[[key]] <- NULL
      suppressed <- isTRUE(override$suppress_output)
      event_result <- if (suppressed) {
        NULL
      } else {
        override$updated_tool_output %||% extracted$tool_result
      }

      private$agent_event(
        "tool_end",
        delegation_id = record$delegation_id,
        tool_call_id = record$tool_call_id,
        tool_name = extracted$tool_name,
        tool_result = event_result,
        tool_error = extracted$tool_error,
        suppressed = suppressed,
        duration = duration
      )
    }
  )
}
