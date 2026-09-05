# Internal R6 methods for agent tool callbacks.
# R6 binds these methods to the same self/private environments as the facade.
deputy_agent_tool_callbacks_methods <- function(self = NULL, private = NULL) {
  list(
    # Callback for tool requests (permission checking + hooks)
    handle_tool_request = function(request) {
      # Validate and extract request data safely
      extracted <- private$extract_tool_request_data(request)
      if (!is.null(extracted$tool_identity_error)) {
        ellmer::tool_reject(extracted$tool_identity_error)
      }
      tool_name <- extracted$tool_name
      tool_input <- extracted$tool_input
      tool_annotations <- extracted$tool_annotations
      provider_tool_call_id <- extracted$provider_tool_call_id

      private$current_tool_calls <- private$current_tool_calls + 1L
      record <- private$tool_call_record(extracted, "request")
      extracted$tool_call_id <- record$tool_call_id
      private$tool_call_records[[record$record_index]]$request_signature <-
        tool_request_signature(tool_name, tool_input)
      if (!isTRUE(record$start_seen)) {
        private$record_run_event(private$tool_start_event(extracted))
      }

      usage <- private$current_run_usage()
      limits <- private$current_usage_limits %||% self$usage_limits
      limit_status <- usage_limit_status(
        usage,
        limits,
        require_followup = TRUE
      )
      if (!is.null(limit_status)) {
        private$mark_usage_limit(limit_status)
        ellmer::tool_reject(usage_limit_message(limit_status))
      }

      # Retain the adapter-specific counter for callers that configure it
      # directly. The governed run limit above counts all requests.
      if (!is.null(private$tool_call_limit)) {
        private$tool_call_count <- private$tool_call_count + 1L
        if (private$tool_call_count > private$tool_call_limit) {
          private$request_stream_stop("tool_call_limit")
          message <- paste0(
            "Tool call limit reached. Please provide your final answer with ",
            "the information gathered so far."
          )
          private$notify(
            message,
            level = "warning",
            code = "tool_call_limit"
          )
          ellmer::tool_reject(message)
        }
      }

      context <- private$hook_context(
        tool_annotations = tool_annotations,
        tool_metadata = extracted$tool_metadata,
        tool_call_id = record$tool_call_id,
        permission_mode = self$permissions$mode,
        usage = usage,
        usage_limits = limits,
        delegation_id = record$delegation_id
      )

      # Deputy's session-local result reader is not part of the configured tool
      # surface. Its private marker exempts only the allowlist gate; ordinary
      # denylist, callback, mode, and capability checks still apply.
      permission_context <- context
      permission_context$.deputy_internal_tool <- extracted$internal_tool
      perm_result <- self$permissions$check(
        tool_name,
        tool_input,
        permission_context
      )

      if (inherits(perm_result, "PermissionResultDeny")) {
        request_result <- private$fire_hook(
          "PermissionRequest",
          tool_name = tool_name,
          tool_input = tool_input,
          permission_result = perm_result,
          context = context
        )

        if (inherits(request_result, "PermissionResultAllow")) {
          perm_result <- request_result
        } else if (inherits(request_result, "PermissionResultDeny")) {
          perm_result <- request_result
        } else if (
          inherits(request_result, "HookResultPreToolUse") &&
            identical(request_result$permission, "allow")
        ) {
          perm_result <- PermissionResultAllow()
        }
      }

      if (inherits(perm_result, "PermissionResultDeny")) {
        private$record_run_event(private$agent_event(
          "permission",
          tool_call_id = record$tool_call_id,
          decision = "deny"
        ))
        if (isTRUE(perm_result$interrupt)) {
          private$request_stream_stop("permission_denied")
        }
        private$notify(
          perm_result$reason,
          level = "warning",
          code = "permission_denied",
          tool_name = tool_name,
          tool_input = tool_input
        )
        ellmer::tool_reject(perm_result$reason)
      }

      # Fire PreToolUse hooks
      hook_result <- private$fire_hook(
        "PreToolUse",
        tool_name = tool_name,
        tool_input = tool_input,
        context = context
      )

      # Check hook result
      if (inherits(hook_result, "HookResultPreToolUse")) {
        if (!is.null(hook_result$additional_context)) {
          private$append_hook_context(hook_result$additional_context)
        }
        # Check continue field - signal to stop after this tool
        if (!is.null(hook_result$continue) && !hook_result$continue) {
          private$request_stream_stop(
            hook_result$stop_reason %||% "hook_requested_stop"
          )
        }
        if (hook_result$permission == "deny") {
          private$record_run_event(private$agent_event(
            "permission",
            tool_call_id = record$tool_call_id,
            decision = "deny"
          ))
          ellmer::tool_reject(hook_result$reason %||% "Denied by hook")
        }
      }

      if (
        !is.null(private$.file_checkpoints) &&
          !is_mcp_tool_context(context)
      ) {
        captured <- tryCatch(
          private$.file_checkpoints$before_tool(
            tool_name,
            tool_input,
            provider_tool_call_id %||% record$tool_call_id
          ),
          deputy_file_checkpoint_error = function(e) {
            private$notify(
              conditionMessage(e),
              level = "warning",
              code = "file_checkpoint_capture_failed",
              tool_name = tool_name,
              tool_call_id = record$tool_call_id
            )
            ellmer::tool_reject(conditionMessage(e))
          }
        )
        private$tool_call_records[[
          record$record_index
        ]]$file_checkpoint_captured <-
          isTRUE(captured)
      }

      # Emit authorization only after Deputy's policy and hook gates have
      # accepted the request. An intermediate allow can still be denied.
      private$record_run_event(private$agent_event(
        "permission",
        tool_call_id = record$tool_call_id,
        decision = "allow"
      ))

      # Queue delegated-run correlation only after every gate has allowed the
      # request. A denied request never invokes the tool closure and therefore
      # must not leave correlation for a later delegation to claim.
      private$queue_delegation(record)

      # Allow the tool to proceed
      invisible(NULL)
    },

    # Callback for tool results (hooks)
    handle_tool_result = function(result) {
      # Validate and extract tool result data safely
      # ContentToolResult (S7) has: value, error, extra, request
      # request is ContentToolRequest with: id, name, arguments, tool, extra
      extracted <- private$extract_tool_result_data(result)
      private$current_tool_results <- private$current_tool_results + 1L
      record <- private$tool_call_record(extracted, "result")
      extracted$tool_call_id <- record$tool_call_id
      hook_tool_result <- private$claim_original_tool_result(
        record$tool_call_id,
        extracted$tool_result
      )

      # Finalize only captures started by this request. Remote tools never
      # enter the local journal, even when their names resemble file tools.
      if (
        !is.null(private$.file_checkpoints) &&
          isTRUE(record$file_checkpoint_captured)
      ) {
        tryCatch(
          private$.file_checkpoints$after_tool(
            extracted$provider_tool_call_id %||% record$tool_call_id,
            is.null(extracted$tool_error)
          ),
          deputy_file_checkpoint_error = function(e) {
            private$should_stop <- TRUE
            private$stop_reason_from_hook <- "file_checkpoint_error"
            private$notify(
              conditionMessage(e),
              level = "warning",
              code = "file_checkpoint_commit_failed",
              tool_name = extracted$tool_name,
              tool_call_id = record$tool_call_id
            )
            stop(e)
          }
        )
        private$tool_call_records[[
          record$record_index
        ]]$file_checkpoint_captured <-
          FALSE
      }

      context <- private$hook_context(
        tool_call_id = record$tool_call_id,
        permission_mode = self$permissions$mode,
        usage = private$current_run_usage(),
        usage_limits = private$current_usage_limits,
        delegation_id = record$delegation_id
      )

      # Fire PostToolUse hooks
      hook_result <- private$fire_hook(
        "PostToolUse",
        tool_name = extracted$tool_name,
        tool_result = hook_tool_result,
        tool_error = extracted$tool_error,
        context = context
      )

      # Check continue field in PostToolUse result
      if (inherits(hook_result, "HookResultPostToolUse")) {
        private$tool_event_overrides[[record$tool_call_id]] <- list(
          suppress_output = hook_result$suppress_output,
          updated_tool_output = hook_result$updated_tool_output
        )
        if (!is.null(hook_result$additional_context)) {
          private$append_hook_context(hook_result$additional_context)
        }
        if (!is.null(hook_result$continue) && !hook_result$continue) {
          private$should_stop <- TRUE
          private$stop_reason_from_hook <- hook_result$stop_reason %||%
            "hook_requested_stop"
        }
      }

      if (!is.null(extracted$tool_error)) {
        private$fire_hook(
          "PostToolUseFailure",
          tool_name = extracted$tool_name,
          tool_result = hook_tool_result,
          tool_error = extracted$tool_error,
          context = context
        )
      }

      private$record_run_event(private$tool_end_event(extracted))

      record_state <- private$tool_call_records[[record$record_index]]
      request_signature <- record_state$request_signature
      cycle_signature <- if (is.null(request_signature)) {
        NULL
      } else {
        tool_cycle_signature(
          request_signature,
          hook_tool_result,
          extracted$tool_error
        )
      }
      if (is.null(cycle_signature)) {
        private$last_tool_cycle_signature <- NULL
        private$consecutive_tool_cycles <- 0L
      } else {
        loop <- advance_tool_loop(
          signature = cycle_signature,
          last_signature = private$last_tool_cycle_signature,
          consecutive_calls = private$consecutive_tool_cycles
        )
        private$last_tool_cycle_signature <- loop$signature
        private$consecutive_tool_cycles <- loop$consecutive_calls
        if (isTRUE(loop$stalled) && !isTRUE(private$should_stop)) {
          message <- paste0(
            "Tool request `",
            extracted$tool_name,
            "` completed with the same result ",
            loop$consecutive_calls,
            " times without progress."
          )
          private$request_stream_stop("tool_loop")
          private$notify(
            message,
            level = "warning",
            code = "tool_loop",
            tool_name = extracted$tool_name,
            repeated = loop$consecutive_calls
          )
        }
      }

      # ellmer may make another provider request after this tool result. Check
      # the complete context again while the run is between provider turns.
      if (!isTRUE(private$should_stop)) {
        private$maybe_auto_compact(messages = list())
      }

      invisible(NULL)
    },

    # Safely extract data from an ellmer tool request.
    extract_tool_request_data = function(request) {
      # Default values if extraction fails
      tool_name <- "unknown"
      tool_input <- list()
      tool_annotations <- NULL
      internal_tool <- NULL
      provider_tool_call_id <- NULL
      tool_identity_error <- NULL

      # Check if we have a valid request object
      if (is.null(request)) {
        cli_warn("Tool request callback received NULL request")
        return(list(
          tool_name = tool_name,
          tool_input = tool_input,
          tool_annotations = tool_annotations,
          internal_tool = internal_tool,
          provider_tool_call_id = provider_tool_call_id,
          tool_identity_error = tool_request_identity_error(request)
        ))
      }

      # Check if it's a ContentToolRequest (S7 class)
      if (!inherits(request, "ellmer::ContentToolRequest")) {
        cli_warn(c(
          "Tool request is not a ContentToolRequest",
          "i" = "Got class: {.cls {class(request)}}"
        ))

        return(list(
          tool_name = tool_name,
          tool_input = tool_input,
          tool_annotations = tool_annotations,
          internal_tool = internal_tool,
          provider_tool_call_id = provider_tool_call_id,
          tool_identity_error = tool_request_identity_error(request)
        ))
      }

      # Extract from S7 object with error handling
      # Tool name
      request_name <- read_tool_request_name(request)
      tool_name <- request_name$value
      tool_identity_error <- request_name$error

      # Tool arguments
      tool_input <- tryCatch(
        request@arguments %||% list(),
        error = function(e) {
          cli_warn("Failed to extract tool arguments from request: {e$message}")
          list()
        }
      )

      provider_tool_call_id <- read_provider_tool_call_id(
        function() request@id,
        source = "request",
        object = request
      )

      # Resolve annotations from the registered executable. Providers may omit
      # the tool object or attach a stale copy to the request.
      registered_tool <- private$.chat$get_tools()[[tool_name]]
      metadata <- if (is.null(registered_tool)) {
        NULL
      } else {
        tool_metadata(registered_tool)
      }
      tool_annotations <- tryCatch(
        {
          if (!is.null(registered_tool)) {
            registered_tool@annotations
          } else {
            NULL
          }
        },
        error = function(e) {
          # Annotations are optional, don't warn
          NULL
        }
      )
      internal_tool <- tryCatch(
        {
          if (is.null(registered_tool)) {
            NULL
          } else {
            attr(registered_tool, "deputy_internal_tool", exact = TRUE)
          }
        },
        error = function(e) NULL
      )

      list(
        tool_name = tool_name,
        tool_input = tool_input,
        tool_annotations = tool_annotations,
        tool_metadata = metadata,
        internal_tool = internal_tool,
        provider_tool_call_id = provider_tool_call_id,
        tool_identity_error = tool_identity_error
      )
    },

    # Safely extract data from an ellmer tool result.
    extract_tool_result_data = function(result) {
      # Default values if extraction fails
      tool_name <- "unknown"
      tool_result <- NULL
      tool_error <- NULL
      provider_tool_call_id <- NULL

      # Check if we have a valid result object
      if (is.null(result)) {
        cli_warn("Tool result callback received NULL result")
        return(list(
          tool_name = tool_name,
          tool_result = tool_result,
          tool_error = "NULL result received",
          provider_tool_call_id = provider_tool_call_id
        ))
      }

      # Check if it's a ContentToolResult (S7 class)
      if (!inherits(result, "ellmer::ContentToolResult")) {
        cli_warn(c(
          "Tool result is not a ContentToolResult",
          "i" = "Got class: {.cls {class(result)}}"
        ))

        return(list(
          tool_name = tool_name,
          tool_result = tool_result,
          tool_error = tool_error,
          provider_tool_call_id = provider_tool_call_id
        ))
      }

      # Extract from S7 object with error handling
      # Tool name from request
      tool_name <- tryCatch(
        {
          if (!is.null(result@request)) {
            result@request@name %||% "unknown"
          } else {
            "unknown"
          }
        },
        error = function(e) {
          cli_warn("Failed to extract tool name from result: {e$message}")
          "unknown"
        }
      )

      # Tool result value
      tool_result <- tryCatch(
        result@value,
        error = function(e) {
          cli_warn("Failed to extract tool result value: {e$message}")
          NULL
        }
      )

      # Tool error
      tool_error <- tryCatch(
        result@error,
        error = function(e) {
          cli_warn("Failed to extract tool error: {e$message}")
          NULL
        }
      )

      provider_tool_call_id <- read_provider_tool_call_id(
        function() {
          if (!is.null(result@request)) {
            result@request@id
          } else {
            NULL
          }
        },
        source = "result",
        object = result
      )

      list(
        tool_name = tool_name,
        tool_result = tool_result,
        tool_error = tool_error,
        provider_tool_call_id = provider_tool_call_id
      )
    }
  )
}
