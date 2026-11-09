# Background tasks: delegations to retained agents whose tool call returns
# before the delegation settles (ADR-0038). A task is an ordinary retained
# continuation; this file only keeps the owner's task registry, decides when
# each tool call resolves, and joins the tasks when the owner's pass ends.

background_abort <- function(message, ...) {
  abort_deputy(message, class = c("background_task", "conversation"), ...)
}

#' Create tools for running retained agents in the background
#'
#' Lets `owner`'s model start tasks on retained agents and keep working while
#' they run. The model gets five tools:
#'
#' * `task_start(agent, task)` starts a task and returns a task ID at once.
#' * `task_status(task_ids)` reports each task's state and progress.
#' * `task_wait(task_ids, until)` waits until a task finishes and returns the
#'   finished tasks' outcomes. It makes no model request while it waits.
#' * `task_follow_up(task_id, task)` sends another task to the same agent,
#'   which keeps its conversation.
#' * `task_cancel(task_id, reason)` asks a task to stop.
#'
#' Each task is a call to a retained agent, like `owner$continue_agent()`: the
#' agent keeps its own permissions, each of its tool calls is also checked
#' against the owner's current permissions and tool hooks, and its work can be
#' followed with `owner$observe_subagents()` and `owner$inspect_subagents()`.
#' An agent runs one task at a time, so a task for a busy agent waits its turn.
#'
#' Tasks belong to the run that started them. When the owner's model stops,
#' tasks that are still waiting or running are cancelled and the run waits for
#' them to stop, so its usage includes theirs. Use `owner$background_tasks()`
#' to see every task of the latest run, including ones the model never
#' collected.
#'
#' Use [delegation_tool()] instead when the model should simply wait for the
#' agent's answer, and a [LeadAgent]'s `$parallel_delegate()` for one reply
#' each from several subagents with no tools. See
#' `vignette("background-tasks")`.
#'
#' @section Budgets:
#' Each task's `usage_limits` are set aside from the owner's run when the task
#' starts and returned, less what the task used, when it finishes. The owner's
#' own requests and tool calls can't use what is set aside, so together they
#' stay within the run's request and tool-call limits. A task that would leave
#' the owner nothing under one of its run's limits is refused, so give
#' `usage_limits` a value for each limit the owner's run has. Token and cost
#' limits are checked after each response, so the owner and each running task
#' can each overshoot them by one response.
#'
#' @param owner The [Agent] whose model gets the tools. Register them on this
#'   agent only. It can't be a member of, or the owner of, a delegation graph,
#'   and can't have a [TrustedResults] policy.
#' @param agents A named character vector or list of handles from
#'   [adopt_chat()] or `owner$retain_agent()`. The names are what the model
#'   calls the agents.
#' @param usage_limits [UsageLimits] for each task. A task also can't exceed
#'   the agent's remaining budget or the owner run's.
#' @param descriptions Optional named character vector telling the model what
#'   each agent is for.
#' @param max_active Maximum number of tasks waiting or running at once.
#'   Further starts are refused until one finishes.
#' @param max_tasks Maximum number of tasks in one run of `owner`.
#' @return A named list of ellmer tools for `owner$register_tools()`.
#' @examples
#' \dontrun{
#' lead <- Agent$new(ellmer::chat("anthropic/claude-sonnet-5"))
#' analyst <- adopt_chat(
#'   ellmer::chat("openai/gpt-6-luna"),
#'   owner = lead,
#'   permissions = permissions_readonly(),
#'   usage_limits = UsageLimits(max_requests = 20),
#'   history = "fresh",
#'   callbacks = "replace",
#'   name = "analyst"
#' )
#' lead$register_tools(background_tools(
#'   lead,
#'   agents = c(analyst = analyst),
#'   usage_limits = UsageLimits(max_requests = 5)
#' ))
#' }
#' @export
background_tools <- function(
  owner,
  agents,
  usage_limits,
  descriptions = NULL,
  max_active = 4L,
  max_tasks = 16L
) {
  if (!inherits(owner, "Agent")) {
    background_abort("owner must be an Agent.")
  }
  private <- owner$.__enclos_env__$private
  background_check_owner(owner)
  agents <- unlist(as.list(agents))
  names <- names(agents)
  if (
    !is.character(agents) ||
      !length(agents) ||
      is.null(names) ||
      anyNA(names) ||
      any(!nzchar(trimws(names))) ||
      anyDuplicated(names) ||
      anyDuplicated(unname(agents))
  ) {
    background_abort(
      "agents must name each retained agent's handle once, with unique names."
    )
  }
  for (handle in agents) {
    conversation_entry(owner, handle)
  }
  if (!is.null(descriptions)) {
    if (
      !is.character(descriptions) ||
        anyNA(descriptions) ||
        is.null(names(descriptions)) ||
        !all(names(descriptions) %in% names)
    ) {
      background_abort(
        "descriptions must be a character vector named after agents."
      )
    }
  }
  if (!S7::S7_inherits(usage_limits, UsageLimits)) {
    background_abort("usage_limits must be created with UsageLimits().")
  }
  max_active <- context_policy_whole_number(max_active, "max_active")
  max_tasks <- context_policy_whole_number(max_tasks, "max_tasks")
  if (
    is.null(max_active) ||
      is.null(max_tasks) ||
      max_active < 1L ||
      max_tasks < 1L
  ) {
    background_abort("max_active and max_tasks must be finite and positive.")
  }
  current <- private$.background
  if (!is.null(current) && background_unsettled(current)) {
    background_abort(
      "Wait for this agent's background tasks before replacing its tools."
    )
  }
  state <- new.env(parent = emptyenv())
  state$agents <- agents
  state$limits <- usage_limits
  state$max_active <- max_active
  state$max_tasks <- max_tasks
  state$tasks <- list()
  state$waiters <- list()
  state$settled <- 0L
  private$.background <- state

  roster <- vapply(
    names,
    function(name) {
      text <- if (name %in% names(descriptions)) descriptions[[name]] else NULL
      if (is.null(text)) name else paste0(name, ": ", text)
    },
    character(1)
  )
  tools <- list(
    background_tool(
      owner,
      "task_start",
      paste0(
        "Start a task for a specialist and return at once with a task_id; the ",
        "specialist works in the background while you continue. A specialist ",
        "keeps its conversation between tasks and runs one task at a time, so ",
        "a task for a busy specialist waits its turn. Collect results with ",
        "task_wait. Tasks still running when you finish are cancelled. ",
        "Specialists: ",
        paste(roster, collapse = "; "),
        "."
      ),
      list(
        agent = ellmer::type_enum(
          unname(names),
          "Name of the specialist"
        ),
        task = ellmer::type_string("The brief for this task")
      ),
      invoke = function(arguments, correlation) {
        background_start(owner, arguments$agent, arguments$task, correlation)
      }
    ),
    background_tool(
      owner,
      "task_follow_up",
      paste0(
        "Send another task to the specialist that ran task_id. It continues ",
        "the same conversation, so it remembers that task. Returns a new ",
        "task_id at once. If the specialist is busy the new task waits its ",
        "turn."
      ),
      list(
        task_id = ellmer::type_string("A task_id from task_start"),
        task = ellmer::type_string("The follow-up brief")
      ),
      invoke = function(arguments, correlation) {
        task <- background_lookup(owner, arguments$task_id)
        background_start(
          owner,
          task$agent,
          arguments$task,
          correlation,
          previous = task$task_id
        )
      }
    ),
    background_tool(
      owner,
      "task_status",
      paste0(
        "Report the state and progress of background tasks without waiting. ",
        "To wait for a result use task_wait rather than calling this again."
      ),
      list(
        task_ids = ellmer::type_array(
          ellmer::type_string(),
          "Tasks to report; omit for all tasks of this run",
          required = FALSE
        )
      ),
      control = function(arguments) {
        background_status(owner, arguments$task_ids)
      },
      read_only = TRUE
    ),
    background_tool(
      owner,
      "task_wait",
      paste0(
        "Wait for background tasks and return the outcomes of those that ",
        "have finished. With until = 'any' (the default) it returns as soon ",
        "as one of the tasks has finished; with 'all', once all have. ",
        "Returns at once if nothing is pending."
      ),
      list(
        task_ids = ellmer::type_array(
          ellmer::type_string(),
          "Tasks to wait for; omit for every task not yet collected",
          required = FALSE
        ),
        until = ellmer::type_enum(
          c("any", "all"),
          "Return after any task or all tasks finish",
          required = FALSE
        )
      ),
      control = function(arguments) {
        background_wait(owner, arguments$task_ids, arguments$until)
      },
      read_only = TRUE
    ),
    background_tool(
      owner,
      "task_cancel",
      paste0(
        "Ask a background task to stop. It stops at its next safe point and ",
        "keeps the work done so far; a task that already finished is left as ",
        "it is."
      ),
      list(
        task_id = ellmer::type_string("The task to cancel"),
        reason = ellmer::type_string(
          "Why the task is no longer needed",
          required = FALSE
        )
      ),
      control = function(arguments) {
        background_cancel(owner, arguments$task_id, arguments$reason)
      }
    )
  )
  stats::setNames(tools, vapply(tools, function(tool) tool@name, character(1)))
}

background_check_owner <- function(owner) {
  private <- owner$.__enclos_env__$private
  if (!is.null(private$.delegation_tree)) {
    background_abort(
      "Background tasks are not available to an agent in a delegation graph."
    )
  }
  if (!is.null(private$.conversation_owner)) {
    background_abort("A retained agent cannot start background tasks.")
  }
  invisible(NULL)
}

# All five tools are composition tools of `owner`: they run only as the
# owner's governed tool call and are refused on any other agent. Only the two
# that start a delegation claim a delegation ID (`invoke`); the others are
# controls on the owner's task registry.
background_tool <- function(
  owner,
  name,
  description,
  arguments,
  invoke = NULL,
  control = NULL,
  read_only = FALSE
) {
  # Called directly, outside the owner's governed tool call, the tool refuses.
  formals <- rep(list(NULL), length(arguments))
  names(formals) <- names(arguments)
  for (argument in names(arguments)) {
    if (isTRUE(arguments[[argument]]@required)) {
      formals[argument] <- list(rlang::missing_arg())
    }
  }
  tool <- ellmer::tool(
    rlang::new_function(
      formals,
      quote(background_abort(
        "Background task tools require their owner's active governed run."
      )),
      environment()
    ),
    name = name,
    description = description,
    arguments = arguments,
    annotations = ellmer::tool_annotations(
      read_only_hint = read_only,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = FALSE
    )
  )
  attr(tool, "deputy_composition_owner") <- owner
  attr(tool, "deputy_internal_tool") <- deputy_composition_tool_marker
  if (is.function(invoke)) {
    attr(tool, "deputy_background_invoke") <- invoke
  } else {
    attr(tool, "deputy_background_control") <- control
  }
  tool
}

# Whether a composition tool starts a delegation, and so needs an ID for one.
composition_tool_delegates <- function(tool) {
  if (is.null(tool)) {
    return(FALSE)
  }
  source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
  !is.null(attr(source, "deputy_composition_owner", exact = TRUE)) &&
    is.null(attr(source, "deputy_background_control", exact = TRUE))
}

background_state <- function(owner) {
  state <- owner$.__enclos_env__$private$.background
  if (is.null(state)) {
    background_abort("This agent has no background task tools.")
  }
  state
}

background_unsettled <- function(state) {
  any(vapply(state$tasks, function(task) !task$settled, logical(1)))
}

# Tasks of the owner's current run. The model can name no others.
background_run_tasks <- function(owner) {
  private <- owner$.__enclos_env__$private
  state <- background_state(owner)
  if (!isTRUE(private$run_active)) {
    return(list())
  }
  Filter(
    function(task) identical(task$run_id, private$current_run_id),
    state$tasks
  )
}

background_lookup <- function(owner, task_id) {
  if (!is_nonempty_string(task_id)) {
    ellmer::tool_reject("task_id must be one task ID from task_start.")
  }
  for (task in background_run_tasks(owner)) {
    if (identical(task$task_id, task_id)) {
      return(task)
    }
  }
  ellmer::tool_reject(paste0(
    "Unknown task: ",
    inspection_text(task_id, 128L),
    ". Only tasks started in this run can be used."
  ))
}

background_ids <- function(owner, task_ids) {
  ids <- unlist(task_ids, use.names = FALSE)
  if (is.null(ids) || !length(ids)) {
    return(NULL)
  }
  if (!is.character(ids) || anyNA(ids)) {
    ellmer::tool_reject("task_ids must be task IDs from task_start.")
  }
  lapply(unique(ids), function(id) background_lookup(owner, id))
}

# Refuse a reservation that would leave the owner nothing under a limit of its
# run: the owner could neither collect the task nor answer.
background_admission <- function(owner) {
  function(limits) {
    private <- owner$.__enclos_env__$private
    run_limits <- private$current_usage_limits %||% owner$usage_limits
    remaining <- usage_limits_remaining(
      run_limits,
      private$current_run_usage(),
      private$reserved_delegation_usage()
    )
    for (field in usage_limit_fields()) {
      left <- remaining[[field]]
      if (is.null(left) || is.na(left)) {
        next
      }
      asked <- S7::prop(limits, field) %||% left
      if (left - asked <= 0) {
        background_abort(paste0(
          "This task would set aside all that is left of the run's ",
          field,
          " (",
          format(left),
          "), leaving the lead none. Give background tasks a smaller ",
          field,
          " or wait for a task to finish."
        ))
      }
    }
    invisible(NULL)
  }
}

background_start <- function(
  owner,
  agent,
  brief,
  correlation,
  previous = NULL
) {
  private <- owner$.__enclos_env__$private
  state <- background_state(owner)
  reject <- function(error) {
    ellmer::tool_reject(paste0(
      "The task was not started: ",
      inspection_text(conditionMessage(error), 1024L)
    ))
  }
  tryCatch(background_check_owner(owner), deputy_error = reject)
  if (!is_nonempty_string(agent) || !agent %in% names(state$agents)) {
    ellmer::tool_reject(paste0(
      "Unknown specialist. Available: ",
      paste(names(state$agents), collapse = ", "),
      "."
    ))
  }
  tasks <- background_run_tasks(owner)
  if (length(tasks) >= state$max_tasks) {
    ellmer::tool_reject(paste0(
      "This run has reached its limit of ",
      state$max_tasks,
      " background tasks."
    ))
  }
  unsettled <- sum(vapply(tasks, function(task) !task$settled, logical(1)))
  if (unsettled >= state$max_active) {
    ellmer::tool_reject(paste0(
      "There are already ",
      unsettled,
      " background tasks waiting or running, the most allowed at once. ",
      "Wait for one with task_wait, or cancel one."
    ))
  }
  handle <- state$agents[[agent]]
  task <- new.env(parent = emptyenv())
  task$task_id <- new_deputy_id("task_")
  task$agent <- agent
  task$handle <- handle
  task$delegation_id <- correlation$delegation_id
  task$tool_call_id <- correlation$tool_call_id
  task$run_id <- private$current_run_id
  task$previous_task_id <- previous
  task$created_at <- Sys.time()
  task$settled <- FALSE
  task$settled_at <- as.POSIXct(NA_real_, origin = "1970-01-01", tz = "UTC")
  task$collected <- FALSE
  task$cancel_reason <- NULL
  task$error <- NULL
  task$final_state <- NULL
  task$order <- NA_integer_
  # A background task is one level below the run that started it.
  correlation$depth <- 1L
  correlation$root_agent_id <- owner$agent_id
  # Counted against the owner's own limits from now until it settles, whether
  # it is reserved at once or when its turn comes.
  private$background_reservations <- c(
    private$background_reservations,
    task$delegation_id
  )
  promise <- tryCatch(
    continue_conversation_queued(
      owner,
      handle,
      brief,
      state$limits,
      correlation,
      owner,
      admission = background_admission(owner),
      admit = function() is.null(task$cancel_reason)
    ),
    error = function(error) {
      private$background_reservations <- setdiff(
        private$background_reservations,
        task$delegation_id
      )
      # A refusal after admission leaves a settled record; the model gets the
      # reason either way and no task exists.
      reject(error)
    }
  )
  state$tasks[[task$task_id]] <- task
  promises::then(
    promise,
    function(result) background_settle(owner, task),
    function(error) background_settle(owner, task, error)
  )
  delegation_json(list(
    task_id = task$task_id,
    agent = agent,
    state = background_task_state(owner, task),
    follows = previous
  ))
}

background_record <- function(owner, task) {
  owner$.__enclos_env__$private$subagent_runs[[task$delegation_id]]
}

background_task_state <- function(owner, task) {
  record <- background_record(owner, task)
  if (!task$settled) {
    if (!is.null(task$cancel_reason)) {
      return("cancelling")
    }
    if (is.null(record) || identical(record$status, "queued")) {
      return("queued")
    }
    return("running")
  }
  if (!is.null(task$final_state)) {
    return(task$final_state)
  }
  status <- record$status %||% "failed"
  if (identical(status, "completed")) {
    return("completed")
  }
  if (!is.null(record$cancel_reason) || !is.null(task$cancel_reason)) {
    return("cancelled")
  }
  if (identical(status, "failed")) "failed" else "stopped"
}

background_settle <- function(owner, task, error = NULL) {
  if (task$settled) {
    return(invisible(NULL))
  }
  private <- owner$.__enclos_env__$private
  state <- private$.background
  record <- background_record(owner, task)
  if (is.null(record) && is.null(task$final_state)) {
    # Refused when its turn came: no delegation was admitted.
    task$final_state <- if (is.null(task$cancel_reason)) {
      "rejected"
    } else {
      "cancelled"
    }
    task$error <- if (!is.null(error)) {
      inspection_text(conditionMessage(error), 1024L)
    }
  }
  task$settled <- TRUE
  task$settled_at <- Sys.time()
  state$settled <- state$settled + 1L
  task$order <- state$settled
  private$background_reservations <- setdiff(
    private$background_reservations,
    task$delegation_id
  )
  # The task's usage is now part of the owner's run: recheck its limits.
  if (
    isTRUE(private$run_active) &&
      identical(private$current_run_id, task$run_id) &&
      !is.null(private$current_usage_limits)
  ) {
    status <- private$limit_status(require_followup = TRUE)
    if (!is.null(status)) {
      private$mark_usage_limit(status)
    }
  }
  background_wake(state)
  invisible(NULL)
}

# Waiters run on the next tick, so tasks that settle together are collected
# together.
background_wake <- function(state) {
  if (!length(state$waiters) || isTRUE(state$waking)) {
    return(invisible(NULL))
  }
  state$waking <- TRUE
  later::later(function() {
    state$waking <- FALSE
    waiters <- state$waiters
    state$waiters <- list()
    for (attempt in waiters) {
      if (!attempt()) {
        state$waiters <- c(state$waiters, list(attempt))
      }
    }
  })
  invisible(NULL)
}

background_task_view <- function(owner, task, outcome = FALSE) {
  private <- owner$.__enclos_env__$private
  record <- background_record(owner, task)
  state <- background_task_state(owner, task)
  view <- list(
    task_id = task$task_id,
    agent = task$agent,
    state = state,
    follows = task$previous_task_id
  )
  if (!task$settled) {
    child <- private$active_subagents[[task$delegation_id]]
    if (!is.null(child)) {
      usage <- tryCatch(
        child$.__enclos_env__$private$current_run_usage(),
        error = function(error) NULL
      )
      view$progress <- list(
        requests = usage$requests %||% 0L,
        tool_calls = usage$tool_calls %||% 0L,
        seconds = round(as.numeric(difftime(
          Sys.time(),
          record$started_at,
          units = "secs"
        )))
      )
    }
    return(view)
  }
  view$stop_reason <- record$stop_reason %||% task$cancel_reason
  if (!is.null(task$error)) {
    view$error <- task$error
  }
  if (outcome && !is.null(record)) {
    view$outcome <- S7::props(delegation_outcome(record, compact = TRUE))
  }
  view
}

background_status <- function(owner, task_ids) {
  tasks <- background_ids(owner, task_ids) %||% background_run_tasks(owner)
  delegation_json(list(
    tasks = unname(lapply(tasks, function(task) {
      view <- background_task_view(owner, task)
      view$collected <- task$collected
      view
    }))
  ))
}

background_wait <- function(owner, task_ids, until = NULL) {
  until <- until %||% "any"
  if (!is_nonempty_string(until) || !until %in% c("any", "all")) {
    ellmer::tool_reject("until must be 'any' or 'all'.")
  }
  state <- background_state(owner)
  named <- background_ids(owner, task_ids)
  # Evaluated once per settlement. Naming tasks fixes the set; otherwise it is
  # every task not yet collected, including ones started while waiting.
  targets <- function() {
    named %||%
      Filter(function(task) !task$collected, background_run_tasks(owner))
  }
  collect <- function() {
    tasks <- targets()
    done <- Filter(function(task) task$settled, tasks)
    pending <- Filter(function(task) !task$settled, tasks)
    ready <- if (identical(until, "all")) {
      !length(pending)
    } else {
      length(done) > 0L || !length(pending)
    }
    if (!ready) {
      return(NULL)
    }
    done <- done[order(vapply(done, function(task) task$order, numeric(1)))]
    payload <- list(
      tasks = unname(lapply(done, function(task) {
        view <- background_task_view(owner, task, outcome = TRUE)
        task$collected <- TRUE
        view
      })),
      # A list, so one ID is still a JSON array.
      still_running = unname(lapply(
        Filter(function(task) !task$settled, background_run_tasks(owner)),
        function(task) task$task_id
      ))
    )
    if (!length(done)) {
      payload$note <- "No background tasks are pending."
    }
    delegation_json(payload)
  }
  payload <- collect()
  if (!is.null(payload)) {
    return(payload)
  }
  promises::promise(function(resolve, reject) {
    state$waiters <- c(
      state$waiters,
      list(function() {
        payload <- tryCatch(collect(), error = function(error) {
          reject(error)
          TRUE
        })
        if (isTRUE(payload)) {
          return(TRUE)
        }
        if (is.null(payload)) {
          return(FALSE)
        }
        resolve(payload)
        TRUE
      })
    )
  })
}

background_cancel_task <- function(owner, task, reason, by = "caller") {
  if (task$settled || !is.null(task$cancel_reason)) {
    return(invisible(FALSE))
  }
  task$cancel_reason <- reason
  record <- background_record(owner, task)
  if (is.null(record)) {
    # Still waiting for its agent: it never starts. Its queue entry finds the
    # cancellation when it is woken.
    task$final_state <- "cancelled"
    background_settle(owner, task)
    return(invisible(TRUE))
  }
  interrupt_delegation(owner, task$delegation_id, reason, by)
  invisible(TRUE)
}

background_cancel <- function(owner, task_id, reason = NULL) {
  task <- background_lookup(owner, task_id)
  # The model's words are kept as a note. The recorded stop reason is fixed,
  # so a host can act on it.
  requested <- isTRUE(background_cancel_task(owner, task, "cancelled"))
  if (requested && is_nonempty_string(reason)) {
    task$cancel_note <- inspection_text(reason, 512L)
  }
  view <- background_task_view(owner, task)
  view$cancel_requested <- requested
  delegation_json(view)
}

# The owner's pass has ended: nothing can collect a task now. Cancel what is
# waiting, ask what is running to stop, and return a promise for their
# settlement, or NULL when there is nothing to wait for.
background_join <- function(owner, reason = "parent_completed") {
  private <- owner$.__enclos_env__$private
  state <- private$.background
  if (is.null(state)) {
    return(NULL)
  }
  pending <- Filter(function(task) !task$settled, state$tasks)
  if (!length(pending)) {
    return(NULL)
  }
  for (task in pending) {
    background_cancel_task(owner, task, reason, by = "parent")
  }
  pending <- Filter(function(task) !task$settled, pending)
  if (!length(pending)) {
    return(NULL)
  }
  promises::promise(function(resolve, reject) {
    state$waiters <- c(
      state$waiters,
      list(function() {
        if (background_unsettled(state)) {
          return(FALSE)
        }
        resolve(TRUE)
        TRUE
      })
    )
  })
}

# A new run starts with an empty registry; the previous run's rows were kept
# for the host until now.
background_reset <- function(owner) {
  private <- owner$.__enclos_env__$private
  state <- private$.background
  if (is.null(state)) {
    return(invisible(NULL))
  }
  state$tasks <- Filter(function(task) !task$settled, state$tasks)
  private$background_reservations <- intersect(
    private$background_reservations,
    vapply(state$tasks, function(task) task$delegation_id, character(1))
  )
  invisible(NULL)
}

# The owner's limits less what unsettled background tasks have set aside.
background_reserved <- function(private) {
  ids <- intersect(
    private$background_reservations,
    names(private$delegation_usage_reservations)
  )
  if (!length(ids)) {
    return(NULL)
  }
  Reduce(`+`, private$delegation_usage_reservations[ids])
}

background_limit_status <- function(private, usage, limits, require_followup) {
  reserved <- background_reserved(private)
  if (is.null(reserved)) {
    return(usage_limit_status(usage, limits, require_followup))
  }
  fields <- usage_limit_fields()
  reduced <- S7::props(limits)
  for (field in fields) {
    if (!is.null(reduced[[field]])) {
      reduced[[field]] <- max(0, reduced[[field]] - reserved[[field]])
    }
  }
  status <- usage_limit_status(
    usage,
    do.call(UsageLimits, reduced),
    require_followup
  )
  if (!is.null(status) && !is.null(status$limit)) {
    status$reserved <- reserved[[status$field]]
    status$limit <- S7::prop(limits, status$field)
  }
  status
}

background_tasks_frame <- function(owner) {
  private <- owner$.__enclos_env__$private
  state <- private$.background
  tasks <- if (is.null(state)) list() else unname(state$tasks)
  text <- function(field) {
    vapply(
      tasks,
      function(task) task[[field]] %||% NA_character_,
      character(1)
    )
  }
  time <- function(field) {
    values <- lapply(tasks, function(task) task[[field]])
    if (!length(values)) {
      return(as.POSIXct(numeric(), origin = "1970-01-01", tz = "UTC"))
    }
    do.call(c, values)
  }
  data.frame(
    task_id = text("task_id"),
    agent = text("agent"),
    state = vapply(
      tasks,
      function(task) background_task_state(owner, task),
      character(1)
    ),
    stop_reason = vapply(
      tasks,
      function(task) {
        if (!task$settled) {
          return(NA_character_)
        }
        background_record(owner, task)$stop_reason %||%
          task$cancel_reason %||%
          NA_character_
      },
      character(1)
    ),
    collected = vapply(tasks, function(task) task$collected, logical(1)),
    delegation_id = text("delegation_id"),
    previous_task_id = text("previous_task_id"),
    parent_run_id = text("run_id"),
    tool_call_id = text("tool_call_id"),
    conversation_handle = text("handle"),
    cancel_note = text("cancel_note"),
    error = text("error"),
    created_at = time("created_at"),
    settled_at = time("settled_at"),
    stringsAsFactors = FALSE
  )
}
