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
    (!is.character(tasks) && !is.list(tasks)) ||
      !length(tasks) ||
      is.null(names(tasks)) ||
      anyNA(names(tasks))
  ) {
    cli_abort("{.arg tasks} must be a non-empty named character vector or list")
  }
  tasks <- as.list(tasks)
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
  allocation <- S7::props(remaining)
  fields <- c(
    "max_input_tokens",
    "max_output_tokens",
    "max_total_tokens",
    "max_cost_usd"
  )
  for (field in fields) {
    available <- S7::prop(remaining, field)
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
  do.call(UsageLimits, allocation)
}

parallel_responder <- function(lead, item, state) {
  private <- lead$.__enclos_env__$private
  lead_run_delegation(
    lead,
    item$correlation$delegation_id,
    item$child,
    item$definition,
    item$manifest$message,
    item$limits
  ) |>
    promises::then(function(outcome) {
      limit <- usage_limit_status(private$current_run_usage(), state$limits)
      if (!is.null(limit)) {
        private$mark_usage_limit(limit)
      }
      outcome
    })
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
    controller <- list(cancel = function(reason = "interrupted") {
      for (child in private$active_subagents) {
        child$interrupt(reason)
      }
    })
    completed <- FALSE
    admitted <- character()
    on.exit(
      {
        if (!completed) {
          state$reason <- "error"
        }
        for (id in admitted) {
          lead_settle_delegation(
            lead,
            id,
            stop_reason = private$stop_reason_from_hook %||%
              if (completed) "not_started" else "batch_error"
          )
          release_delegation_binding(lead, id)
        }
        private$finish_callback_run(state)
      },
      add = TRUE
    )
    initialize_agent_run(
      lead,
      state,
      lapply(
        selected$tasks,
        delegation_task_label,
        max_bytes = private$delegation_max_bytes
      ),
      limits,
      context,
      controller
    )
    count <- length(selected$tasks)
    # Admit every selected task before preparing children. Failed preparation
    # must retain the failing record and unstarted siblings without paid work.
    prepared <- lapply(seq_len(count), function(index) {
      definition <- selected$definitions[[index]]
      correlation <- list(
        parent_agent_id = lead$agent_id,
        parent_run_id = state$active_run_id,
        delegation_id = new_deputy_id("delegation_"),
        run_context = context,
        tool_call_id = NULL
      )
      task <- selected$tasks[[index]]
      id <- lead_admit_delegation(lead, definition, task, correlation)
      admitted <<- c(admitted, id)
      list(definition = definition, correlation = correlation, task = task)
    })
    # Resolve every reference before constructing any Subagent.
    prepared <- lapply(prepared, function(item) {
      item$prepared <- tryCatch(
        resolve_delegation_input(lead, item$definition, item$task),
        error = function(condition) {
          lead_settle_delegation(
            lead,
            item$correlation$delegation_id,
            error = condition,
            stop_reason = "setup_error"
          )
          rlang::cnd_signal(condition)
        }
      )
      item
    })
    # Prepare the complete batch before any provider request.
    prepared <- lapply(prepared, function(item) {
      id <- item$correlation$delegation_id
      item$child <- tryCatch(
        private$create_sub_agent(
          item$definition,
          item$correlation,
          UsageLimits(
            max_requests = min(1L, item$definition$max_requests %||% 1L),
            max_tool_calls = 0L
          ),
          stateless = TRUE
        ),
        error = function(condition) {
          lead_settle_delegation(
            lead,
            id,
            error = condition,
            stop_reason = "setup_error"
          )
          stop(condition)
        }
      )
      item$manifest <- tryCatch(
        prepare_delegation_manifest(
          lead,
          item$definition,
          item$prepared,
          item$child
        ),
        error = function(condition) {
          lead_settle_delegation(
            lead,
            id,
            item$child,
            error = condition,
            stop_reason = "setup_error"
          )
          rlang::cnd_signal(condition)
        }
      )
      lead_bind_delegation(lead, id, item$child, item$manifest)
      item
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
        parallel_responder(lead, item, state)
      })
      wave_outcomes <- coro::await(promises::promise_all(.list = promises))
      outcomes[indices] <- wave_outcomes
      next_index <- next_index + wave_size
    }
    for (id in admitted) {
      lead_settle_delegation(
        lead,
        id,
        stop_reason = private$stop_reason_from_hook %||% "not_started"
      )
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
      outcomes = stats::setNames(
        lapply(admitted, function(id) {
          delegation_outcome(private$subagent_runs[[id]])
        }),
        names(selected$tasks)
      ),
      errors = lapply(outcomes, `[[`, "error"),
      status = statuses,
      run = state$result
    )
  })()
}
