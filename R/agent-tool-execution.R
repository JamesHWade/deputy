# Internal R6 methods for agent tool adaptation, execution, trusted result
# delivery, offloading, and runtime rewiring.
# R6 binds these methods to the same self/private environments as the facade.
deputy_agent_tool_execution_methods <- function(self = NULL, private = NULL) {
  list(
    rewire_chat_runtime = function() {
      clear_chat_tool_callbacks(private$.chat)

      tools <- private$.chat$get_tools()
      had_result_reader <- "deputy_read_tool_result" %in% names(tools)
      tools[["deputy_read_tool_result"]] <- NULL
      tools <- validate_tool_batch(tools)
      private$check_trusted_tools(tools)
      private$.chat$set_tools(lapply(tools, private$prepare_cloned_tool))
      private$.tool_result_reader_registered <- FALSE
      if (isTRUE(had_result_reader)) {
        private$ensure_tool_result_reader()
      }
      private$.chat$on_tool_request(private$handle_tool_request)
      private$.chat$on_tool_result(private$handle_tool_result)
      rebind_tool_observers(self)
      invisible(NULL)
    },

    prepare_cloned_tool = function(tool) {
      private$adapt_tool(tool)
    },

    discard_stale_mcp_tools = function() {
      tools <- private$.chat$get_tools()
      current <- vapply(tools, mcp_tool_is_current, logical(1))
      if (all(current)) {
        return(invisible(NULL))
      }
      removed <- names(tools)[!current]
      # These are already adapted tools; only remove invalidated handles.
      private$.chat$set_tools(tools[current])
      private$loaded_mcp_tools <- setdiff(private$loaded_mcp_tools, removed)
      invisible(NULL)
    },

    resolve_tool_arguments = function(tool_name, arguments) {
      resolve_runtime_tool_arguments(
        tool_name,
        arguments,
        private$.working_dir
      )
    },

    adapt_provider_builtin_tool = function(tool) {
      if (!is.null(private$.approval_dir)) {
        approval_abort(
          "Durable approvals require function tools; provider-native effects cannot be journaled."
        )
      }
      tool_name <- tryCatch(tool@name, error = function(error) NULL)
      tool_id <- normalize_native_tool_id(tool_name %||% "")
      if (!tool_id %in% c("web_search", "web_fetch")) {
        cli_abort(c(
          "Unsupported provider-native tool: {.val {tool_name %||% '<unknown>'}}",
          "x" = paste0(
            "Deputy cannot interpose on provider-side execution for this ",
            "tool."
          )
        ))
      }
      if (!isTRUE(self$permissions$web)) {
        cli_abort(c(
          "Provider-native web tool {.val {tool_name}} is not authorized.",
          "i" = "Set {.code web = TRUE} and explicitly allow the tool."
        ))
      }
      allowlist <- self$permissions$tool_allowlist %||% character()
      allowlist_ids <- unique(vapply(
        allowlist,
        normalize_native_tool_id,
        character(1)
      ))
      if (!tool_id %in% allowlist_ids) {
        cli_abort(c(
          "Provider-native web tool {.val {tool_name}} is not explicitly allowed.",
          "i" = "Add the tool name to {.arg tool_allowlist}."
        ))
      }
      if (!is.null(self$permissions$can_use_tool)) {
        cli_abort(c(
          "Provider-native tool {.val {tool_name}} cannot use a custom permission callback.",
          "x" = paste0(
            "Provider-side requests cannot be checked against request ",
            "arguments or run context."
          ),
          "i" = paste0(
            "Remove {.arg can_use_tool} or use Deputy's universal ",
            "function tool."
          )
        ))
      }
      permission <- permissions_check(
        self$permissions,
        tool_name,
        list(),
        list(
          working_dir = private$.working_dir,
          tool_annotations = tool@annotations
        )
      )
      if (S7::S7_inherits(permission, PermissionResultDeny)) {
        cli_abort(c(
          "Provider-native tool {.val {tool_name}} was denied at registration.",
          "x" = permission$reason,
          "i" = paste0(
            "Provider-native tools are authorized before a request because ",
            "they execute inside the provider."
          )
        ))
      }
      tool
    },

    adapt_tool = function(tool) {
      validate_composition_tool_owner(tool, self)
      validate_mcp_tool_owner(tool, self)
      validate_r_session_tool_owner(tool, self)
      if (inherits(tool, "ellmer::ToolBuiltIn")) {
        return(private$adapt_provider_builtin_tool(tool))
      }
      runtime_wrap_tool(
        tool,
        resolve_arguments = if (
          identical(tool_metadata(tool)$source$type, "mcp")
        ) {
          function(tool_name, arguments) arguments
        } else {
          private$resolve_tool_arguments
        },
        process_result = private$process_tool_result,
        begin_execution = private$begin_tool_execution,
        execute = private$execute_tool,
        invocation_id = private$tool_invocation_id
      )
    },

    # Trusted tools run only as the tool of ellmer's active request, so host
    # code or another tool cannot claim a pending governed call or publish.
    tool_invocation_id = function(tool, arguments) {
      if (is.null(trusted_result_type(private$.trusted_results, tool@name))) {
        return(composition_invocation_id(tool, arguments))
      }
      trusted_invocation_id(tool)
    },

    execute_tool = function(tool, arguments, execution_id = NULL) {
      validate_composition_tool_owner(tool, self)
      if (!is.null(trusted_result_type(private$.trusted_results, tool@name))) {
        # The producer must still be the tool the policy or tree pinned.
        pinned <- private$.trusted_sources[[tool@name]] %||%
          trusted_policy_sources(private$.trusted_results)[[tool@name]]
        if (
          !is_nonempty_string(execution_id) ||
            (!is.null(pinned) && !identical(pinned, tool))
        ) {
          trusted_invocation_abort(tool@name)
        }
        private$trusted_arguments[[execution_id]] <- arguments
      }
      if (!is.null(composition_tool_owner(tool))) {
        if (!isTRUE(private$run_active) || !is_nonempty_string(execution_id)) {
          conversation_abort(
            "Delegation tools require their owner's active governed run."
          )
        }
        control <- attr(tool, "deputy_background_control", exact = TRUE)
        if (is.function(control)) {
          return(control(arguments))
        }
        correlation <- private$claim_delegation(
          tool_name = tool@name,
          tool_call_id = execution_id,
          required = TRUE
        )
        background <- attr(tool, "deputy_background_invoke", exact = TRUE)
        if (is.function(background)) {
          return(background(arguments, correlation))
        }
        invoke <- attr(tool, "deputy_composition_invoke", exact = TRUE)
        return(invoke(arguments[["task"]], correlation))
      }
      validate_mcp_tool_owner(tool, self, private$effective_run_context())
      validate_r_session_tool_owner(
        tool,
        self,
        private$effective_run_context()
      )
      workspace_runner <- attr(
        tool,
        "deputy_workspace_runner",
        exact = TRUE
      )
      if (is.function(workspace_runner)) {
        return(workspace_runner(arguments, private$.working_dir))
      }
      write_root <- private$execution_write_root(execution_id)
      if (!is.null(write_root)) {
        # A file or link changed since the permission check must not move
        # the write outside the directory the policy checked.
        return(tryCatch(
          validate_path_at_operation(
            arguments$path,
            write_root,
            function(path) do.call(tool, arguments)
          ),
          deputy_unsafe_path = function(error) {
            ellmer::tool_reject(paste(
              "The path no longer resolves inside the allowed directory;",
              "a file or link in it changed after the permission check:",
              arguments$path
            ))
          }
        ))
      }
      source <- runtime_source_tool(tool)
      cancel <- attr(source, "deputy_mcp_cancel_active", exact = TRUE) %||%
        attr(source, "deputy_r_session_cancel_active", exact = TRUE)
      if (!is.function(cancel)) {
        return(do.call(tool, arguments))
      }
      id <- new_deputy_id("owned_call_")
      private$active_owned_tools[[id]] <- source
      pending <- FALSE
      on.exit({
        if (!pending) {
          private$active_owned_tools[[id]] <- NULL
        }
      })
      invoke <- attr(source, "deputy_r_session_invoke", exact = TRUE)
      value <- if (is.function(invoke)) {
        invoke(arguments$code, execution_id)
      } else {
        do.call(tool, arguments)
      }
      if (!promises::is.promising(value)) {
        return(value)
      }
      result <- promises::finally(value, function() {
        private$active_owned_tools[[id]] <- NULL
      })
      pending <- TRUE
      result
    },

    check_trusted_tools = function(tools) {
      policy <- private$.trusted_results
      check_trusted_registry(
        policy,
        tools,
        available = if (isTRUE(private$.trusted_tree_member)) {
          policy@results
        } else {
          names(tools)
        },
        sources = private$.trusted_sources,
        require_source = isTRUE(private$.trusted_tree_member),
        admit_route = trusted_route_admission(self, tools)
      )
      # Names a retained agent's own policy designates stay that tool here:
      # those this agent retained, and for a retained agent or graph
      # member, those its policy root retained too, siblings included.
      entries <- private$owned_conversations
      root <- trusted_policy_root(self)
      if (!is.null(root) && !identical(root, self)) {
        entries <- c(
          entries,
          root$.__enclos_env__$private$owned_conversations
        )
      }
      for (entry in entries) {
        if (!is.null(entry$trusted)) {
          trusted_check_names(
            trusted_policy_sources(entry$trusted$policy),
            list(tools)
          )
        }
      }
    },

    process_tool_result = function(tool_name, value, execution_id = NULL) {
      type <- trusted_result_type(private$.trusted_results, tool_name)
      if (!is.null(type)) {
        value <- private$deliver_trusted_result(
          type,
          tool_name,
          value,
          execution_id
        )
      }
      private$offload_tool_result(tool_name, value, execution_id)
    },

    # The trusted tool's return value reaches the host before any model
    # output, independently of offloading and PostToolUse event rewrites.
    deliver_trusted_result = function(type, tool_name, value, execution_id) {
      arguments <- NULL
      if (is_nonempty_string(execution_id)) {
        arguments <- private$trusted_arguments[[execution_id]]
        private$trusted_arguments[[execution_id]] <- NULL
      }
      if (
        inherits(value, "ellmer::ContentToolResult") && !is.null(value@error)
      ) {
        return(value)
      }
      policy <- private$.trusted_results
      result_id <- new_deputy_id("result_")
      producer <- private$.trusted_sources[[tool_name]] %||%
        trusted_policy_sources(policy)[[tool_name]] %||%
        runtime_source_tool(private$.chat$get_tools()[[tool_name]])
      event <- private$agent_event(
        "trusted_result",
        result_id = result_id,
        result_type = type,
        tool_name = tool_name,
        tool_fingerprint = trusted_producer_fingerprint(producer),
        tool_call_id = execution_id,
        arguments = arguments,
        value = value
      )
      private$record_run_event(event)
      if (is.function(policy@on_result)) {
        delivered <- tryCatch(
          {
            policy@on_result(event)
            TRUE
          },
          error = function(error) error
        )
        if (!isTRUE(delivered)) {
          private$notify(
            paste0(
              "Trusted result ",
              result_id,
              " was produced but the host callback failed: ",
              conditionMessage(delivered)
            ),
            level = "warning",
            code = "trusted_result_delivery_failed",
            tool_name = tool_name,
            result_id = result_id,
            result_type = type
          )
          abort_tool_execution(
            "Trusted result {result_id} was produced but could not be delivered to the user.",
            tool_name = tool_name
          )
        }
      }
      if (isTRUE(policy@model_receipt)) {
        return(trusted_result_receipt(result_id, type))
      }
      value
    },

    offload_tool_result = function(tool_name, value, execution_id = NULL) {
      if (identical(tool_name, "deputy_read_tool_result")) {
        return(value)
      }
      rich <- bound_rich_tool_result(
        value,
        tool_name,
        private$.context_policy,
        private$.session_id,
        private$.agent_id
      )
      record <- if (!is.null(rich)) {
        rich$record
      } else {
        offload_tool_result(
          value = value,
          tool_name = tool_name,
          policy = private$.context_policy,
          session_id = private$.session_id,
          agent_id = private$.agent_id
        )
      }
      if (is.null(record)) {
        return(value)
      }
      # Returning a result to the caller claims it independently of any
      # concurrent compaction that first created these content-addressed bytes.
      private$.compaction_catalog_registry$provisional[[record$id]] <- NULL
      private$ensure_tool_result_reader()
      if (!is.null(private$.delegation_id)) {
        private$delegation_artifacts[[
          length(private$delegation_artifacts) + 1L
        ]] <- list(
          reference = record$uri,
          source = "tool_result",
          bytes = record$bytes,
          sha256 = record$sha256,
          agent_id = private$.agent_id,
          run_id = private$current_run_id,
          delegation_id = private$.delegation_id,
          tool_call_id = execution_id,
          tool_name = tool_name,
          storage_session_id = private$.session_id,
          verification = "not_assessed",
          approval = "not_granted"
        )
      }
      private$notify(
        paste0("Offloaded large result from ", tool_name, "."),
        level = "info",
        code = "tool_result_offloaded",
        tool_name = tool_name,
        result_reference = record$uri,
        result_bytes = record$bytes,
        result_sha256 = record$sha256
      )
      if (is_nonempty_string(execution_id)) {
        native <- inherits(value, "ellmer::ContentToolResult")
        private$original_tool_results[[execution_id]] <- list(
          value = if (native) value@value else value,
          error = if (native) value@error else NULL
        )
      }
      if (!is.null(rich)) rich$result else tool_result_reference_text(record)
    },

    ensure_tool_result_reader = function() {
      if (isTRUE(private$.tool_result_reader_registered)) {
        return(invisible(NULL))
      }
      private$.chat$register_tool(
        private$adapt_tool(tool_result_reader_tool(
          private$read_tool_result_chunk
        ))
      )
      private$.tool_result_reader_registered <- TRUE
      invisible(NULL)
    },

    read_tool_result_chunk = function(reference, offset, max_chars) {
      read_tool_result_chunk(
        reference = reference,
        offset = offset,
        max_chars = max_chars,
        policy = private$.context_policy,
        session_id = private$.session_id
      )
    }
  )
}
