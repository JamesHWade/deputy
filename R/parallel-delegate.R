# Tier-1 fan-out uses the same governed asynchronous runs as ordinary Agents.

validate_parallel_tasks <- function(lead, tasks, max_active, mode) {
  if (!identical(mode, "stateless")) {
    cli_abort(
      "Only {.code mode = 'stateless'} is supported for parallel delegation."
    )
  }
  max_active <- context_policy_whole_number(max_active, "max_active")
  if (is.null(max_active)) {
    cli_abort("{.arg max_active} must be a positive whole number")
  }
  if (
    !is.character(tasks) ||
      length(tasks) == 0L ||
      anyNA(tasks) ||
      !all(nzchar(trimws(tasks))) ||
      is.null(names(tasks))
  ) {
    cli_abort("{.arg tasks} must be a non-empty named character vector")
  }
  keys <- vapply(names(tasks), normalize_agent_definition_name, character(1))
  if (anyDuplicated(keys)) {
    cli_abort("{.arg tasks} must select each AgentDefinition at most once")
  }
  definitions <- lead$.__enclos_env__$private$.sub_agent_defs
  unknown <- setdiff(keys, names(definitions))
  if (length(unknown) > 0L) {
    cli_abort("Unknown AgentDefinitions: {.val {unknown}}")
  }
  for (key in keys) {
    definition <- definitions[[key]]
    if (
      length(definition$tools) > 0L ||
        length(definition$skills) > 0L ||
        length(definition$mcp_servers) > 0L
    ) {
      cli_abort(c(
        "AgentDefinition {.val {key}} is not stateless.",
        "i" = "Stateless fan-out requires no tools, skills, or MCP servers."
      ))
    }
  }
  list(
    tasks = stats::setNames(unname(tasks), keys),
    definitions = definitions[keys],
    max_active = max_active
  )
}

parallel_child_limits <- function(remaining, definition, count, index) {
  allocation <- remaining
  fields <- c(
    "max_input_tokens",
    "max_output_tokens",
    "max_total_tokens",
    "max_cost_usd"
  )
  for (field in fields) {
    available <- remaining[[field]]
    if (is.null(available)) {
      next
    }
    allocation[[field]] <- if (identical(field, "max_cost_usd")) {
      available / count
    } else {
      floor(available / count) + as.integer(index <= available %% count)
    }
  }
  allocation$max_requests <- min(1L, definition$max_requests %||% 1L)
  allocation$max_tool_calls <- 0L
  allocation$on_exceed <- "stop"
  allocation
}

parallel_responder <- function(
  lead,
  child,
  definition,
  task,
  correlation,
  limits,
  state
) {
  private <- lead$.__enclos_env__$private
  coro::async(function() {
    on.exit(
      {
        private$release_delegation_usage(correlation$delegation_id)
        state$active[[definition$name]] <- NULL
      },
      add = TRUE
    )
    error <- NULL
    started_at <- Sys.time()
    result <- tryCatch(
      {
        if (isTRUE(private$should_stop)) {
          return(list(result = NULL, error = NULL, status = "not_started"))
        }
        lead$hooks$fire(
          "SubagentStart",
          agent_name = definition$name,
          task = task,
          context = private$hook_context(
            agent_definition = definition,
            child_agent_id = child$agent_id,
            child_agent_name = child$agent_name,
            child_run_context = child$run_context,
            delegation_id = correlation$delegation_id
          )
        )
        if (isTRUE(private$should_stop)) {
          return(list(result = NULL, error = NULL, status = "not_started"))
        }
        task_to_run <- task
        if (!is.null(definition$initial_prompt)) {
          task_to_run <- paste(definition$initial_prompt, task, sep = "\n\n")
        }
        coro::await(child$run_async(task_to_run, usage_limits = limits))
      },
      error = function(condition) {
        error <<- condition
        NULL
      }
    )
    usage <- result$usage %||%
      child$.__enclos_env__$private$last_run_usage %||%
      AgentUsage()
    private$current_external_usage <- agent_usage_add(
      private$current_external_usage,
      usage
    )
    if (!is.null(error)) {
      status <- "failed"
    } else if (identical(result$stop_reason, "complete")) {
      status <- "completed"
    } else if (result$stop_reason %in% c("error", "provider_error")) {
      status <- "failed"
    } else {
      status <- "stopped"
    }
    child_run_id <- result$run_id %||%
      child$.__enclos_env__$private$current_run_id
    tryCatch(
      lead$hooks$fire(
        "SubagentStop",
        agent_name = definition$name,
        task = task,
        result = result$response,
        context = private$hook_context(
          status = status,
          error = if (!is.null(error)) conditionMessage(error),
          child_agent_id = child$agent_id,
          child_agent_name = child$agent_name,
          child_run_id = child_run_id,
          child_run_context = child$run_context,
          delegation_id = correlation$delegation_id
        )
      ),
      error = function(condition) {
        error <<- condition
        status <<- "failed"
      }
    )
    private$subagent_runs <- c(
      private$subagent_runs,
      list(list(
        agent_name = definition$name,
        agent_id = child$agent_id,
        parent_agent_id = lead$agent_id,
        task = task,
        session_id = child$session_id(),
        run_id = child_run_id,
        parent_run_id = correlation$parent_run_id,
        delegation_id = correlation$delegation_id,
        tool_call_id = NULL,
        run_context = child$run_context,
        started_at = started_at,
        completed_at = Sys.time(),
        status = status,
        result = result$response,
        error = if (!is.null(error)) conditionMessage(error),
        usage = usage,
        agent_result = result,
        turns = child$turns()
      ))
    )
    limit <- usage_limit_status(private$current_run_usage(), state$limits)
    if (!is.null(limit)) {
      private$mark_usage_limit(limit)
    }
    list(result = result, error = error, status = status)
  })()
}

lead_parallel_delegate <- function(
  lead,
  tasks,
  max_active,
  mode,
  usage_limits,
  run_context
) {
  selected <- validate_parallel_tasks(lead, tasks, max_active, mode)
  private <- lead$.__enclos_env__$private
  limits <- if (is.null(usage_limits)) {
    lead$usage_limits
  } else {
    merge_usage_limits(usage_limits, lead$usage_limits)
  }
  context <- merge_run_context(lead$run_context, run_context)
  coro::async(function() {
    if (isTRUE(private$run_active)) {
      cli::cli_abort(
        "This agent already has an active run",
        class = c("deputy_run_active", "deputy_error")
      )
    }
    state <- private$new_callback_run_state()
    state$active <- list()
    controller <- list(cancel = function(reason = "interrupted") {
      for (child in state$active) {
        child$interrupt(reason)
      }
    })
    completed <- FALSE
    on.exit(
      {
        if (!completed) {
          state$reason <- "error"
        }
        private$finish_callback_run(state)
      },
      add = TRUE
    )
    initialize_agent_run(
      lead,
      state,
      as.list(selected$tasks),
      limits,
      context,
      controller
    )
    count <- length(selected$tasks)
    # Prepare the complete batch before any provider request. Fresh Chat
    # objects are cheap; max_active bounds network activity.
    prepared <- lapply(seq_len(count), function(index) {
      definition <- selected$definitions[[index]]
      correlation <- list(
        parent_agent_id = lead$agent_id,
        parent_run_id = state$active_run_id,
        delegation_id = new_deputy_id("delegation_"),
        run_context = context,
        tool_call_id = NULL
      )
      child <- private$create_sub_agent(
        definition,
        correlation,
        UsageLimits(
          max_requests = min(1L, definition$max_requests %||% 1L),
          max_tool_calls = 0L
        ),
        stateless = TRUE
      )
      list(
        child = child,
        definition = definition,
        correlation = correlation,
        task = selected$tasks[[index]]
      )
    })
    outcomes <- rep(
      list(list(
        result = NULL,
        error = NULL,
        status = "not_started"
      )),
      count
    )
    names(outcomes) <- names(selected$tasks)
    next_index <- 1L
    while (next_index <= count && !isTRUE(private$should_stop)) {
      limit <- usage_limit_status(
        private$current_run_usage(),
        limits,
        require_followup = TRUE
      )
      if (!is.null(limit)) {
        private$mark_usage_limit(limit)
        break
      }
      remaining <- private$derive_subagent_usage_limits(
        agent_definition("batch", "Batch allocation", "Respond once.")
      )
      wave_size <- min(
        selected$max_active,
        count - next_index + 1L,
        remaining$max_requests %||% Inf
      )
      indices <- seq.int(next_index, length.out = wave_size)
      wave <- lapply(seq_along(indices), function(position) {
        index <- indices[[position]]
        item <- prepared[[index]]
        item$limits <- parallel_child_limits(
          remaining,
          item$definition,
          wave_size,
          position
        )
        item
      })
      promises <- lapply(wave, function(item) {
        private$reserve_delegation_usage(
          item$correlation$delegation_id,
          item$limits
        )
        state$active[[item$definition$name]] <- item$child
        parallel_responder(
          lead,
          item$child,
          item$definition,
          item$task,
          item$correlation,
          item$limits,
          state
        )
      })
      wave_outcomes <- coro::await(promises::promise_all(.list = promises))
      outcomes[indices] <- wave_outcomes
      next_index <- next_index + wave_size
    }
    statuses <- vapply(outcomes, `[[`, character(1), "status")
    if (isTRUE(private$should_stop)) {
      state$reason <- private$stop_reason_from_hook %||% "interrupted"
    } else if (any(statuses == "failed")) {
      state$reason <- "delegation_error"
    } else if (any(statuses != "completed")) {
      state$reason <- "delegation_stopped"
    } else {
      state$reason <- "complete"
    }
    completed <- TRUE
    private$finish_callback_run(state)
    list(
      mode = "stateless",
      results = lapply(outcomes, `[[`, "result"),
      errors = lapply(outcomes, `[[`, "error"),
      status = statuses,
      run = state$result
    )
  })()
}
