# Durable approval lifecycle composed into the existing Agent run kernel.
deputy_agent_approval_methods <- function(self = NULL, private = NULL) {
  list(
    pause_for_approval = function(request, reason, kind = "tool") {
      if (is.null(private$.approval_dir)) {
        approval_abort(
          "Configure an approval_dir before requesting durable approval."
        )
      }
      if (is.null(request@tool) || isTRUE(request@tool@convert)) {
        approval_abort(c(
          "Durable approval requires a tool registered with convert = FALSE.",
          "i" = "The tool function must accept raw JSON arguments; existing tools are not converted implicitly."
        ))
      }
      approval_validate_inputs(request@arguments)
      turns <- private$.chat$get_turns()
      if (
        !length(turns) ||
          !inherits(tail(turns, 1L)[[1L]], "ellmer::AssistantTurn")
      ) {
        approval_abort(
          "A durable approval requires a complete assistant tool-request turn."
        )
      }
      batch <- Filter(
        function(content) inherits(content, "ellmer::ContentToolRequest"),
        tail(turns, 1L)[[1L]]@contents
      )
      ids <- vapply(batch, function(content) content@id, character(1))
      if (
        anyNA(ids) ||
          !all(nzchar(ids)) ||
          anyDuplicated(ids) ||
          !request@id %in% ids
      ) {
        approval_abort(
          "Approval tool requests require unique non-empty IDs within the batch."
        )
      }
      session <- private$build_session_payload()
      session$turns <- approval_record_turns(session$turns)
      session$metadata$saved_at <- as.numeric(session$metadata$saved_at)
      policy <- approval_policy_record(self$permissions)
      record <- list(
        schema_version = 1L,
        id = gsub("-", "", new_deputy_id("approval_"), fixed = TRUE),
        status = "pending",
        pending = list(
          request = approval_record_content(request),
          reason = reason,
          kind = kind,
          fingerprint = approval_tool_fingerprint(request@tool)
        ),
        effects = private$.approval_journal,
        denied_signatures = private$.approval_resume$record$denied_signatures %||%
          character(),
        source = list(
          session_id = self$session_id(),
          agent_id = self$agent_id,
          run_id = private$current_run_id,
          parent_agent_id = private$.parent_agent_id,
          parent_run_id = private$.parent_run_id,
          delegation_id = private$.delegation_id
        ),
        context = private$snapshot_run_context(),
        permissions = policy,
        ceilings = c(private$.approval_ceilings, list(policy)),
        usage = S7::props(private$current_run_usage()),
        usage_limits = S7::props(private$current_usage_limits),
        budget_ceiling = if (is.null(private$.approval_resume)) {
          S7::props(self$usage_limits)
        } else {
          private$.approval_resume$record$budget_ceiling
        },
        session = session,
        tools = private$.approval_tools %||%
          lapply(private$.chat$get_tools(), approval_tool_fingerprint),
        working_dir = private$.working_dir,
        decision = NULL
      )
      validate_approval_record(record)
      path <- approval_store_create(private$.approval_dir, record)
      private$.pending_approval_path <- path
      private$record_run_event(private$agent_event(
        "approval",
        approval_id = record$id,
        path = path,
        status = "pending",
        tool_call_id = request@id,
        tool_name = request@name,
        tool_input = request@arguments,
        reason = reason
      ))
      private$request_stream_stop("approval_pending")
      approval_abort(
        "Run suspended for approval.",
        class = "approval_pending",
        path = path
      )
    },

    approval_request_check = function(request) {
      if (is.null(private$.approval_dir)) {
        return(invisible(NULL))
      }
      if (!is.null(private$.approval_journal[[request@id]])) {
        approval_abort("A tool-call ID was reused within this continuation.")
      }
      private$.approval_requests[[request@id]] <- request
      if (is.null(private$.approval_resume)) {
        return(invisible(NULL))
      }
      signature <- tool_request_signature(request@name, request@arguments)
      executed <- vapply(
        private$.approval_journal,
        function(entry) {
          isTRUE(entry$executed) && identical(entry$signature, signature)
        },
        logical(1)
      )
      denied <- private$.approval_resume$record$denied_signatures %||%
        character()
      if (any(executed) || signature %in% denied) {
        ellmer::tool_reject(
          "This operation was already executed or denied in the continuation; it will not be replayed."
        )
      }
      expected <- private$.approval_tools[[request@name]]
      if (
        is.null(expected) ||
          is.null(request@tool) ||
          !identical(expected, approval_tool_fingerprint(request@tool))
      ) {
        ellmer::tool_reject(
          "Tool is outside the saved continuation registry or its definition changed."
        )
      }
      invisible(NULL)
    },

    approval_permission_check = function(tool_name, tool_input, context) {
      if (is.null(private$.approval_resume)) {
        return(invisible(NULL))
      }
      # Every saved ceiling is checked independently: mode, paths, allow/deny
      # lists, and capabilities cannot disappear through a later callback.
      policies <- c(
        private$.approval_ceilings,
        list(approval_policy_record(self$permissions))
      )
      for (policy in policies) {
        result <- permissions_check(
          approval_static_policy(policy),
          tool_name,
          tool_input,
          context
        )
        if (!S7::S7_inherits(result, PermissionResultAllow)) {
          ellmer::tool_reject(
            result$reason %||% "Outside the continuation authority ceiling."
          )
        }
      }
      invisible(NULL)
    },

    approval_execution_start = function(tool_name, tool_call_id) {
      if (is.null(private$.approval_dir)) {
        return(invisible(NULL))
      }
      request <- private$.approval_requests[[tool_call_id]]
      if (is.null(request)) {
        approval_abort(
          "Cannot journal an uncorrelated approval-enabled tool execution."
        )
      }
      private$.approval_journal[[tool_call_id]] <- list(
        request = approval_record_content(request),
        result = NULL,
        signature = tool_request_signature(request@name, request@arguments),
        executed = TRUE,
        status = "executing"
      )
      if (!is.null(private$.approval_resume)) {
        private$commit_approval_state("executing")
      }
      invisible(NULL)
    },

    approval_execution_result = function(result, record) {
      if (is.null(private$.approval_dir)) {
        return(invisible(NULL))
      }
      request <- result@request
      if (is.null(request)) {
        return(invisible(NULL))
      }
      entry <- private$.approval_journal[[record$tool_call_id]] %||%
        list(
          request = approval_record_content(request),
          signature = tool_request_signature(request@name, request@arguments),
          executed = FALSE
        )
      entry$result <- approval_record_content(result)
      entry$status <- if (is.null(result@error)) "completed" else "failed"
      private$.approval_journal[[record$tool_call_id]] <- entry
      if (!is.null(private$.approval_resume)) {
        private$commit_approval_state("continuing")
      }
      invisible(NULL)
    },

    commit_approval_state = function(status, reason = NULL) {
      resume <- private$.approval_resume
      if (is.null(resume)) {
        return(invisible(NULL))
      }
      record <- resume$record
      if (
        status %in%
          c("completed", "stopped") &&
          any(vapply(
            private$.approval_journal,
            function(entry) identical(entry$status, "executing"),
            logical(1)
          ))
      ) {
        status <- "indeterminate"
      }
      record$status <- status
      record$effects <- private$.approval_journal
      record$usage <- S7::props(private$current_run_usage())
      record$outcome <- list(
        reason = reason,
        run_id = private$current_run_id,
        next_approval = private$.pending_approval_path
      )
      approval_store_write(resume$path, record, resume$lock)
      private$.approval_resume$record <- record
      invisible(NULL)
    },

    execute_approval_resume = function() {
      resume <- private$.approval_resume
      if (is.null(resume) || isTRUE(resume$executed)) {
        return(invisible(NULL))
      }
      record <- resume$record
      private$.approval_resume$executed <- TRUE
      pending <- record$pending$request
      pending$props$arguments <- record$decision$tool_input
      # Replay a complete turn so ellmer resolves the request's tool by name.
      turn_record <- list(
        version = 1,
        class = "ellmer::AssistantTurn",
        props = list(contents = list(pending))
      )
      request <- ellmer::contents_replay(
        turn_record,
        tools = private$.chat$get_tools()
      )@contents[[1L]]
      private$.approval_grant <- tool_request_signature(
        request@name,
        request@arguments
      )
      on.exit(
        {
          private$.approval_grant <- NULL
        },
        add = TRUE
      )
      if (identical(record$decision$decision, "deny")) {
        value <- approval_result_content(
          request,
          error = "The host denied this pending operation."
        )
        signature <- tool_request_signature(request@name, request@arguments)
        private$.approval_resume$record$denied_signatures <- unique(c(
          record$denied_signatures %||% character(),
          signature
        ))
        extracted <- private$extract_tool_request_data(request)
        call_record <- private$tool_call_record(extracted, "request")
        private$.approval_requests[[call_record$tool_call_id]] <- request
        private$record_run_event(private$agent_event(
          "permission",
          tool_call_id = request@id,
          decision = "deny"
        ))
      } else {
        error <- NULL
        # Normal admission, current hooks, argument resolution, and execution
        # wrappers remain in force for the restored operation.
        output <- tryCatch(
          {
            private$handle_tool_request(request)
            if (isTRUE(private$should_stop)) {
              ellmer::tool_reject(
                "The continuation was stopped before execution."
              )
            }
            ellmer::with_tool_context(
              list(request = request, turns = private$.chat$get_turns()),
              private$resolve_promise(do.call(request@tool, request@arguments))
            )
          },
          error = function(condition) {
            error <<- condition
            NULL
          }
        )
        value <- approval_result_content(request, output, error)
      }
      private$handle_tool_result(value)

      # A single result turn accounts for the whole requested batch. Completed
      # siblings retain their results; later siblings are explicitly unexecuted.
      turns <- private$.chat$get_turns()
      last <- tail(turns, 1L)[[1L]]
      results <- lapply(
        Filter(
          function(content) inherits(content, "ellmer::ContentToolRequest"),
          last@contents
        ),
        function(sibling) {
          if (identical(sibling@id, request@id)) {
            return(value)
          }
          entry <- private$.approval_journal[[sibling@id]]
          if (!is.null(entry$result)) {
            return(ellmer::contents_replay(entry$result))
          }
          approval_result_content(
            sibling,
            error = "Not executed: another operation in this batch required approval."
          )
        }
      )
      result_turn <- ellmer::contents_replay(list(
        version = 1,
        class = "ellmer::UserTurn",
        props = list(contents = lapply(results, approval_record_content))
      ))
      # Record edited arguments in the assistant request so the result and its
      # originating request remain consistent after host edits.
      last@contents <- lapply(last@contents, function(content) {
        if (
          inherits(content, "ellmer::ContentToolRequest") &&
            identical(content@id, request@id)
        ) {
          request
        } else {
          content
        }
      })
      turns[[length(turns)]] <- last
      private$.chat$set_turns(c(turns, list(result_turn)))
      private$commit_approval_state("continuing")
      invisible(NULL)
    }
  )
}

approval_resume <- function(
  agent,
  path,
  decision,
  tool_input = NULL,
  usage_limits = NULL
) {
  private <- agent$.__enclos_env__$private
  if (isTRUE(private$run_active)) {
    approval_abort("Cannot resume approval during an active run.")
  }
  path <- approval_store_path(path)
  if (
    is.null(private$.approval_dir) ||
      !identical(dirname(path), private$.approval_dir)
  ) {
    approval_abort(
      "Approval path must belong to this Agent's configured approval_dir."
    )
  }
  lock <- approval_store_lock(path)
  on.exit(approval_store_unlock(lock), add = TRUE)
  record <- approval_store_read(path)
  validate_approval_record(record)
  if (!identical(record$status, "pending")) {
    approval_abort(
      c(
        "This approval is no longer pending and cannot be replayed.",
        "i" = "Inspect its execution journal and reconcile any indeterminate effects externally."
      ),
      class = "approval_consumed",
      status = record$status
    )
  }
  if (
    !identical(record$source$session_id, agent$session_id()) ||
      !identical(record$source$agent_id, agent$agent_id) ||
      !identical(record$working_dir, private$.working_dir)
  ) {
    approval_abort(
      "Approval session, Agent, and working directory must match the receiving Agent."
    )
  }
  for (field in c("parent_agent_id", "parent_run_id", "delegation_id")) {
    if (!identical(record$source[[field]], private[[paste0(".", field)]])) {
      approval_abort(
        "Approval delegation correlation must match the receiving Agent."
      )
    }
  }
  merge_run_context(private$.run_context, record$context)
  if (
    isTRUE(record$permissions$callback_required) &&
      is.null(agent$permissions$can_use_tool)
  ) {
    approval_abort(
      "Reattach a permission callback before resuming this approval."
    )
  }
  tool <- private$.chat$get_tools()[[record$pending$request$props$name]]
  if (
    is.null(tool) ||
      isTRUE(tool@convert) ||
      !identical(approval_tool_fingerprint(tool), record$pending$fingerprint)
  ) {
    approval_abort(
      "Reattach the same raw-argument tool definition before resuming approval."
    )
  }
  decision <- match.arg(decision, c("approve", "deny"))
  tool_input <- tool_input %||% record$pending$request$props$arguments
  approval_validate_inputs(tool_input)
  if (
    identical(decision, "deny") &&
      !identical(tool_input, record$pending$request$props$arguments)
  ) {
    approval_abort("A denied request cannot also edit tool inputs.")
  }
  record$decision <- list(decision = decision, tool_input = tool_input)
  if (!is.null(usage_limits) && !S7::S7_inherits(usage_limits, UsageLimits)) {
    approval_abort("usage_limits must be a UsageLimits value or NULL.")
  }
  limits <- intersect_usage_limits(
    usage_limits %||% do.call(UsageLimits, record$usage_limits),
    intersect_usage_limits(
      do.call(UsageLimits, record$budget_ceiling),
      agent$usage_limits
    )
  )
  if (identical(decision, "approve")) {
    limit_status <- usage_limit_status(
      approval_usage(record$usage),
      limits,
      require_followup = TRUE
    )
    if (!is.null(limit_status)) {
      approval_abort(
        c(
          "The continuation has no remaining allowance for this operation.",
          "i" = "Supply explicit usage_limits within the saved and current Agent ceiling, or deny the operation."
        ),
        class = "approval_budget_exhausted"
      )
    }
  }
  record$usage_limits <- S7::props(limits)
  session <- record$session
  session$turns <- approval_replay_turns(
    session$turns,
    private$.chat$get_tools()
  )
  private$restore_session_payload(session, source = path)
  record$status <- "resuming"
  approval_store_write(path, record, lock)
  private$.pending_approval_path <- NULL
  private$.approval_resume <- list(
    path = path,
    record = record,
    lock = lock,
    executed = FALSE
  )
  private$.approval_ceilings <- record$ceilings %||% list(record$permissions)
  private$.approval_tools <- record$tools
  on.exit(
    {
      private$.approval_resume <- NULL
      private$.approval_ceilings <- list()
      private$.approval_tools <- NULL
      private$.approval_grant <- NULL
    },
    add = TRUE
  )
  agent$run_sync(
    "Continue from the recorded tool result. Do not repeat completed or denied operations.",
    usage_limits = limits,
    run_context = record$context
  )
}

approval_validate_inputs <- function(inputs) {
  approval_portable(inputs)
  approval_json_inputs(inputs)
  approval_no_replay_tags(inputs)
  if (
    !is.list(inputs) ||
      (length(inputs) &&
        (is.null(names(inputs)) ||
          anyNA(names(inputs)) ||
          !all(nzchar(names(inputs))) ||
          anyDuplicated(names(inputs))))
  ) {
    approval_abort(
      "Tool inputs must be a uniquely named list of portable JSON values."
    )
  }
  invisible(inputs)
}

# Raw ellmer tools retain responsibility for their domain and schema validation.
# The durable boundary accepts only JSON-representable values, never NA/NaN/Inf.
approval_json_inputs <- function(value) {
  if (is.null(value)) {
    return(invisible(NULL))
  }
  if (is.list(value)) {
    if (
      !is.null(names(value)) &&
        (anyNA(names(value)) ||
          !all(nzchar(names(value))) ||
          anyDuplicated(names(value)))
    ) {
      approval_abort("JSON object names must be unique non-empty strings.")
    }
    for (item in value) {
      approval_json_inputs(item)
    }
  } else if (
    !is.atomic(value) ||
      is.raw(value) ||
      is.complex(value) ||
      anyNA(value) ||
      (is.numeric(value) && !all(is.finite(value)))
  ) {
    approval_abort("Tool inputs must contain only finite JSON values.")
  }
  invisible(value)
}
