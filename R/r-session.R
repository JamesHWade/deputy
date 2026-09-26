#' Persistent R session for a conversation
#'
#' @description
#' An R process that keeps variables and loaded packages between calls in one
#' agent's conversation. Register `$tools()` on the agent to give the model a
#' `run_r_code` tool that uses it. Calls run in order and return promises, so
#' other conversations aren't blocked.
#'
#' The process runs with your user account's access to files and the network;
#' it is not an OS sandbox. The default permissions deny the tool; allow it
#' with `r_code = TRUE` in [Permissions()]. `$run()` runs code directly,
#' without permission checks. See `vignette("code-execution")`.
#'
#' @section Working directory and resets:
#' Each call starts in the agent's working directory; `setwd()` lasts until
#' the next call. `$cancel()` and timeouts kill the R process and discard its
#' variables and queued calls; the next call starts fresh and says so. Effects
#' outside R, such as written files, are not undone. The session belongs to one
#' agent and stops accepting calls if the agent's session changes. Call
#' `$close()` when the conversation ends.
#'
#' @section Results and saved conversations:
#' Each result holds ellmer text and image content, HTML for display, and an
#' `extra$deputy_r` record of the call. Saved turns keep the code, output and
#' plots but not the variables, which must be recreated after a restart. Agent
#' snapshots keep only the current model context, so with compaction, store the
#' full display history yourself. Base, ggplot2, grid and patchwork plots are
#' captured; htmlwidgets and rich HTML tables report `unsupported_output`, so
#' print the data instead.
#'
#' @section Calling agent tools from R:
#' With `tools = c("name")`, code run through the agent's `run_r_code` tool can
#' call `tools$name(...)`. The calls go through the agent's permissions, hooks
#' and usage limits, and their events carry `parent_tool_call_id`. Selected
#' tools must already be registered on the agent, use `convert = FALSE` and
#' validate their raw JSON arguments; `run_r_code` itself can't be selected. R
#' gets the tool's original return value, even if a `PostToolUse` hook sets
#' `updated_tool_output`. A call must finish within the remaining `timeout`,
#' or the session resets.
#'
#' With selected tools, `$run()` is unavailable and the agent can't have an
#' `approval_dir`. Requests are limited to 256 KiB and results to 8 MiB
#' serialized. The tool functions run in your main R process; selecting them
#' doesn't limit what the R code can do.
#'
#' @export
RSession <- R6::R6Class(
  "RSession",
  cloneable = FALSE,
  public = list(
    #' @description Create a session. The R process starts on the first call.
    #' @param agent The agent that owns the session.
    #' @param tools Names of tools registered on `agent` that R code may call
    #'   as `tools$<name>(...)`. None by default.
    #' @param timeout Maximum seconds for each call. A call that takes longer
    #'   resets the session.
    #' @param startup_timeout Maximum seconds for the R process to start.
    #' @param queue_limit Maximum number of calls waiting behind the running
    #'   one.
    #' @param max_output_bytes Maximum bytes of output kept per call. This
    #'   limits captured output, not memory use.
    #' @param plot_width,plot_height PNG plot size in pixels, at most 4096.
    initialize = function(
      agent,
      timeout = 30,
      startup_timeout = 60,
      queue_limit = 16L,
      max_output_bytes = 8 * 1024 * 1024,
      plot_width = 1000L,
      plot_height = 650L,
      tools = character()
    ) {
      private$owner <- r_session_owner(agent)
      private$agent <- agent
      private$tool_names <- r_session_tool_names(tools)
      if (
        length(private$tool_names) &&
          !is.null(r_session_tool_agent_private(agent)$.approval_dir)
      ) {
        abort_deputy(
          "R sessions with selected tools cannot use an Agent with durable approvals configured.",
          class = "r_session_tool"
        )
      }
      private$tool_specs <- if (length(private$tool_names)) {
        r_session_tool_specs(agent, private$tool_names)
      } else {
        list()
      }
      for (name in c("timeout", "startup_timeout")) {
        value <- get(name)
        if (
          !is.numeric(value) ||
            length(value) != 1L ||
            is.na(value) ||
            !is.finite(value) ||
            value <= 0
        ) {
          abort_deputy(
            "{.arg {name}} must be positive and finite.",
            class = "r_session"
          )
        }
      }
      for (name in c(
        "queue_limit",
        "max_output_bytes",
        "plot_width",
        "plot_height"
      )) {
        value <- context_policy_whole_number(get(name), name)
        if (is.null(value)) {
          abort_deputy(
            "{.arg {name}} must be a positive whole number.",
            class = "r_session"
          )
        }
      }
      if (plot_width > 4096L || plot_height > 4096L) {
        abort_deputy(
          "Plot dimensions must not exceed 4096 pixels.",
          class = "r_session"
        )
      }
      private$settings <- list(
        timeout = timeout,
        startup_timeout = startup_timeout,
        queue_limit = queue_limit,
        max_output_bytes = max_output_bytes,
        plot_width = plot_width,
        plot_height = plot_height
      )
      private$id <- new_deputy_id("r_session_")
      private$resource <- new.env(parent = emptyenv())
      private$resource$worker <- NULL
      private$bridge_root <- NULL
      invisible(self)
    },

    #' @description Return the `run_r_code` tool for this session, to register
    #'   on the agent.
    #' @return A list containing one ellmer tool.
    tools = function() {
      private$check_current()
      tool <- ellmer::tool(
        function(code) private$enqueue(code, execution_id = NULL),
        name = "run_r_code",
        description = paste(
          c(
            "Run R code in this conversation's persistent trusted R session.",
            "Variables and loaded packages persist between ordered calls.",
            "You and the user receive output, warnings, errors and rendered plots.",
            "Create static base, ggplot2, grid or patchwork figures normally; print plots inside loops.",
            "Interactive htmlwidgets and rich HTML tables are not supported; print underlying data for tables.",
            "Perform follow-up calculations and revisions yourself.",
            "After a reported reset, rerun required setup; old variables are gone.",
            "The session uses the local account's files and network access; it is not an OS sandbox.",
            r_session_tool_description(private$tool_specs)
          ),
          collapse = " "
        ),
        arguments = list(code = ellmer::type_string("R code to execute.")),
        annotations = ellmer::tool_annotations(
          read_only_hint = FALSE,
          destructive_hint = TRUE,
          idempotent_hint = FALSE,
          open_world_hint = TRUE
        )
      )
      attr(tool, "deputy_r_session_owner") <- private$owner
      if (length(private$tool_names)) {
        attr(tool, "deputy_r_session_invoke") <- function(code, execution_id) {
          private$enqueue(code, execution_id = execution_id)
        }
        attr(tool, "deputy_r_session_tool_names") <- private$tool_names
      }
      attr(tool, "deputy_r_session_cancel_active") <- function() {
        if (!is.null(private$active) || length(private$queue)) {
          self$cancel()
        }
        invisible(NULL)
      }
      list(tool)
    },

    #' @description Run code directly, without the agent's permissions or
    #'   hooks. Errors at once if `code` is invalid or the queue is full.
    #' @param code One non-empty string of R code, at most 256 KiB.
    #' @return A promise for an `ellmer::ContentToolResult`. R errors, crashes
    #'   and cancelled calls resolve to a result that describes them.
    run = function(code) {
      private$check_current()
      private$enqueue(code, execution_id = NULL)
    },

    #' @description Report the session's state without running code.
    #' @return A list with `id`, `state`, `generation` (incremented each time a
    #'   fresh R process starts), `queued`, `last_reset`, `pid` and
    #'   `working_dir`.
    status = function() {
      worker <- private$resource$worker
      list(
        id = private$id,
        state = if (!is.null(worker) && !worker$is_alive()) {
          "lost"
        } else {
          private$state
        },
        generation = private$generation,
        queued = length(private$queue),
        last_reset = private$last_reset,
        pid = if (!is.null(worker) && worker$is_alive()) {
          worker$get_pid()
        } else {
          NULL
        },
        working_dir = private$owner$working_dir
      )
    },

    #' @description Cancel running and queued calls and discard the session's
    #'   variables.
    #' @return Invisible `NULL`.
    cancel = function() {
      if (!identical(private$state, "closed")) {
        private$reset("cancelled")
      }
      invisible(NULL)
    },

    #' @description Close the session for good and stop its R process.
    close = function() {
      if (!identical(private$state, "closed")) {
        private$reset("closed")
        private$state <- "closed"
      }
      invisible(NULL)
    }
  ),
  private = list(
    agent = NULL,
    owner = NULL,
    tool_names = character(),
    tool_specs = list(),
    settings = NULL,
    resource = NULL,
    bridge_root = NULL,
    id = NULL,
    state = "new",
    generation = 0L,
    last_reset = NULL,
    active = NULL,
    queue = list(),
    check_current = function() {
      if (identical(private$state, "closed")) {
        abort_deputy("The R session is closed.", class = "r_session_closed")
      }
      if (!identical(private$owner, r_session_owner(private$agent))) {
        abort_deputy(
          "The R session owner has changed; create a new session.",
          class = "r_session_owner"
        )
      }
    },
    enqueue = function(code, execution_id = NULL) {
      private$check_current()
      if (!is_nonempty_string(code) || nchar(code, "bytes") > 256 * 1024) {
        abort_deputy(
          "{.arg code} must be one non-empty string of at most 256 KiB.",
          class = "r_session"
        )
      }
      run_id <- NULL
      if (length(private$tool_names)) {
        if (!is_nonempty_string(execution_id)) {
          abort_deputy(
            "R code with bridged Agent tools must run inside its active governed tool execution.",
            class = "r_session_tool_context"
          )
        }
        agent_private <- r_session_tool_agent_private(private$agent)
        run_id <- if (
          !is.null(agent_private) && isTRUE(agent_private$run_active)
        ) {
          agent_private$current_run_id
        } else {
          NULL
        }
        if (!is_nonempty_string(run_id)) {
          abort_deputy(
            "R session tool calls require the owning Agent's active governed run.",
            class = "r_session_tool_context"
          )
        }
      }
      dispatch <- NULL
      if (length(private$tool_names)) {
        dispatch <- r_session_tool_dispatcher(
          private$agent,
          private$tool_names,
          parent_tool_call_id = execution_id,
          run_id = run_id
        )
      }
      if (
        is.null(private$active) &&
          !is.null(private$resource$worker) &&
          !private$resource$worker$is_alive()
      ) {
        private$reset("worker_exited")
      }
      if (length(private$queue) >= private$settings$queue_limit) {
        abort_deputy(
          "The R session waiting queue is full.",
          class = "r_session_busy"
        )
      }
      promises::promise(function(resolve, reject) {
        private$queue <- c(
          private$queue,
          list(list(
            id = new_deputy_id("r_call_"),
            code = code,
            resolve = resolve,
            governed_execution_id = execution_id,
            run_id = run_id,
            dispatch = dispatch,
            tool_requests = new.env(parent = emptyenv())
          ))
        )
        private$drain()
      })
    },
    bridge_directory = function(job) {
      if (is.null(private$bridge_root)) {
        private$bridge_root <- tempfile("deputy-r-tools-")
        if (!dir.create(private$bridge_root, recursive = TRUE, mode = "0700")) {
          abort_deputy(
            "Could not create the R session tool mailbox.",
            class = "r_session_tool_mailbox"
          )
        }
      }
      directory <- file.path(
        private$bridge_root,
        paste0("generation-", private$generation),
        paste0("call-", job$id)
      )
      if (!dir.create(directory, recursive = TRUE, mode = "0700")) {
        abort_deputy(
          "Could not create the R session execution mailbox.",
          class = "r_session_tool_mailbox"
        )
      }
      directory
    },
    cleanup_bridge = function() {
      if (!is.null(private$bridge_root)) {
        unlink(private$bridge_root, recursive = TRUE, force = TRUE)
        private$bridge_root <- NULL
      }
      invisible(NULL)
    },
    active_job = function(job) {
      !is.null(private$active) && identical(private$active$id, job$id)
    },
    write_tool_response = function(
      job,
      request,
      status,
      value = NULL,
      error = NULL
    ) {
      if (!private$active_job(job)) {
        return(invisible(NULL))
      }
      request_id <- request$request_id
      if (
        exists(request_id, envir = job$tool_requests, inherits = FALSE) &&
          identical(get(request_id, envir = job$tool_requests), "settled")
      ) {
        return(invisible(NULL))
      }
      response <- tryCatch(
        r_session_tool_response(
          request,
          status = status,
          value = value,
          error = error,
          session_id = private$id,
          call_id = job$id,
          generation = job$generation
        ),
        error = function(condition) {
          list(
            protocol = r_session_tool_protocol_version,
            request_id = request_id,
            session_id = private$id,
            call_id = job$id,
            execution_id = job$governed_execution_id,
            generation = job$generation,
            tool_name = request$tool_name %||% "unknown",
            status = "error",
            error = r_session_tool_error_message(condition)
          )
        }
      )
      path <- file.path(job$mailbox_dir, paste0(request_id, ".response.json"))
      tryCatch(
        r_session_tool_atomic_write(
          path,
          r_session_tool_json(
            response,
            r_session_tool_max_result_bytes * 2L,
            context = "response"
          )
        ),
        error = function(condition) {
          # The worker may have timed out or the owner may be resetting.  In
          # either case there is no later execution to which this response may
          # be delivered.
          invisible(NULL)
        }
      )
      assign(request_id, "settled", envir = job$tool_requests)
      invisible(NULL)
    },
    poll_tool_mailbox = function(job) {
      if (
        !length(private$tool_names) ||
          is.null(job$mailbox_dir) ||
          !dir.exists(job$mailbox_dir)
      ) {
        return(invisible(NULL))
      }
      paths <- list.files(
        job$mailbox_dir,
        pattern = "\\.request\\.json$",
        full.names = TRUE,
        no.. = TRUE
      )
      for (path in paths) {
        request_id <- sub("\\.request\\.json$", "", basename(path))
        if (exists(request_id, envir = job$tool_requests, inherits = FALSE)) {
          next
        }
        assign(request_id, "processing", envir = job$tool_requests)
        request <- tryCatch(
          r_session_tool_read_json(
            path,
            r_session_tool_max_request_bytes,
            context = "request"
          ),
          error = function(condition) condition
        )
        if (inherits(request, "condition")) {
          # A malformed request cannot be safely associated with an execution;
          # mark it consumed and leave the worker to report its bounded timeout.
          assign(request_id, "settled", envir = job$tool_requests)
          next
        }
        validated <- tryCatch(
          r_session_tool_validate_request(
            request,
            session_id = private$id,
            call_id = job$id,
            execution_id = job$governed_execution_id,
            generation = job$generation,
            tool_names = private$tool_names,
            request_basename = basename(path)
          ),
          error = function(condition) condition
        )
        if (inherits(validated, "condition")) {
          if (
            is.list(request) &&
              is_nonempty_string(request$request_id) &&
              r_session_tool_valid_request_id(request$request_id) &&
              identical(request$request_id, request_id)
          ) {
            private$write_tool_response(
              job,
              request,
              status = "error",
              error = r_session_tool_error_message(validated)
            )
          } else {
            assign(request_id, "settled", envir = job$tool_requests)
          }
          next
        }
        value <- tryCatch(
          job$dispatch(
            validated$tool_name,
            validated$arguments,
            execution_id = job$id,
            generation = as.character(job$generation)
          ),
          error = function(condition) condition
        )
        if (inherits(value, "condition")) {
          private$write_tool_response(
            job,
            request,
            status = "error",
            error = r_session_tool_error_message(value)
          )
          next
        }
        if (promises::is.promising(value)) {
          local({
            pending_request <- request
            promises::then(
              value,
              function(result) {
                private$write_tool_response(
                  job,
                  pending_request,
                  "ok",
                  value = result
                )
                invisible(NULL)
              },
              function(condition) {
                private$write_tool_response(
                  job,
                  pending_request,
                  "error",
                  error = r_session_tool_error_message(condition)
                )
                invisible(NULL)
              }
            )
          })
          assign(request_id, "pending", envir = job$tool_requests)
        } else {
          private$write_tool_response(job, request, "ok", value = value)
        }
      }
      invisible(NULL)
    },
    reset = function(reason) {
      private$cleanup_bridge()
      worker <- private$resource$worker
      private$resource$worker <- NULL
      if (!is.null(worker)) {
        try(worker$kill_tree(), silent = TRUE)
        try(worker$close(grace = 0), silent = TRUE)
      }
      active <- private$active
      queued <- private$queue
      private$active <- NULL
      private$queue <- list()
      private$state <- "new"
      private$last_reset <- reason
      if (!is.null(active)) {
        private$settle(
          active,
          list(list(
            type = "error",
            text = paste0(
              "R execution ",
              reason,
              "; session variables were discarded. ",
              "Partial output is unavailable and external effects are not rolled back."
            )
          )),
          reason
        )
      }
      for (job in queued) {
        private$settle(
          job,
          list(list(
            type = "error",
            text = paste0(
              "Queued R code was not executed: session ",
              reason,
              ". Session variables were discarded."
            )
          )),
          "not_executed"
        )
      }
      invisible(NULL)
    },
    settle = function(job, segments, outcome) {
      if (!is.null(job$mailbox_dir)) {
        unlink(job$mailbox_dir, recursive = TRUE)
      }
      # Record any nested tool request still in flight before the enclosing
      # run_r_code result is released, so its record is still open. A late
      # nested result is then dropped rather than reaching a later execution.
      if (!is.null(job$dispatch)) {
        abandon <- attr(job$dispatch, "deputy_r_session_abandon", exact = TRUE)
        if (is.function(abandon)) {
          tryCatch(abandon(outcome), error = function(condition) NULL)
        }
      }
      job$resolve(r_session_result(
        code = job$code,
        segments = segments,
        session_id = private$id,
        execution_id = job$id,
        generation = job$generation %||% private$generation,
        fresh = isTRUE(job$fresh),
        reset_reason = job$reset_reason,
        outcome = outcome
      ))
      invisible(NULL)
    },
    drain = function() {
      if (
        !is.null(private$active) ||
          !length(private$queue) ||
          identical(private$state, "closed")
      ) {
        return(invisible(NULL))
      }
      job <- private$queue[[1L]]
      private$queue <- private$queue[-1L]
      private$active <- job
      tryCatch(
        {
          private$check_current()
          worker <- private$resource$worker
          if (!is.null(worker) && !worker$is_alive()) {
            private$reset("worker_exited")
            return(invisible(NULL))
          }
          fresh <- is.null(worker)
          if (fresh) {
            worker <- callr::r_session$new(
              options = callr::r_session_options(
                libpath = .libPaths(),
                user_profile = FALSE,
                system_profile = FALSE,
                # Let processx finalize its own native resources. Calling
                # callr$close() from an R finalizer can re-enter pipe cleanup.
                extra = list(cleanup_tree = TRUE)
              ),
              wait = FALSE
            )
            private$resource$worker <- worker
            private$generation <- private$generation + 1L
          }
          job$fresh <- fresh
          job$generation <- private$generation
          if (length(private$tool_names)) {
            job$mailbox_dir <- private$bridge_directory(job)
          }
          private$active <- job
          private$active$fresh <- fresh
          private$active$generation <- private$generation
          private$active$reset_reason <- if (fresh) private$last_reset else NULL
          private$state <- if (fresh) "starting" else "running"
          began <- unname(proc.time()[["elapsed"]])
          dispatched <- FALSE
          deadline <- began + private$settings$startup_timeout
          poll <- function() {
            if (
              is.null(private$active) || !identical(private$active$id, job$id)
            ) {
              return(invisible(NULL))
            }
            tryCatch(
              {
                if (!worker$is_alive()) {
                  private$reset("worker_exited")
                  return(invisible(NULL))
                }
                if (unname(proc.time()[["elapsed"]]) >= deadline) {
                  private$reset(
                    if (dispatched) "timed_out" else "startup_timed_out"
                  )
                  return(invisible(NULL))
                }
                if (!dispatched) {
                  if (identical(worker$get_state(), "idle")) {
                    fun <- r_session_evaluate
                    environment(fun) <- baseenv()
                    worker$call(
                      fun,
                      list(
                        code = job$code,
                        working_dir = private$owner$working_dir,
                        max_output_bytes = private$settings$max_output_bytes,
                        plot_width = private$settings$plot_width,
                        plot_height = private$settings$plot_height,
                        mailbox_dir = job$mailbox_dir,
                        session_id = private$id,
                        call_id = job$id,
                        execution_id = job$governed_execution_id,
                        generation = job$generation,
                        tool_specs = private$tool_specs,
                        tool_timeout = private$settings$timeout
                      )
                    )
                    dispatched <<- TRUE
                    private$state <- "running"
                    deadline <<- unname(proc.time()[["elapsed"]]) +
                      private$settings$timeout
                  } else if (identical(worker$poll_process(0), "ready")) {
                    worker$read()
                  }
                } else if (identical(worker$poll_process(0), "ready")) {
                  response <- worker$read()
                  if (
                    inherits(response, "callr_session_result") &&
                      !identical(response$code, 301L)
                  ) {
                    if (!is.null(response$error) || response$code != 200L) {
                      private$reset("worker_failed")
                      return(invisible(NULL))
                    }
                    finished <- private$active
                    private$active <- NULL
                    private$state <- "idle"
                    private$settle(
                      finished,
                      response$result$segments,
                      response$result$outcome
                    )
                    private$drain()
                    return(invisible(NULL))
                  }
                }
                if (dispatched && private$active_job(job)) {
                  private$poll_tool_mailbox(job)
                }
                if (private$active_job(job)) later::later(poll, 0.01)
              },
              error = function(e) private$reset("worker_failed")
            )
            invisible(NULL)
          }
          poll()
        },
        error = function(e) private$reset("startup_failed")
      )
      invisible(NULL)
    }
  )
)

r_session_owner <- function(agent, run_context = agent$run_context) {
  if (!inherits(agent, "Agent")) {
    abort_deputy("{.arg agent} must be an Agent.", class = "r_session")
  }
  list(
    agent = agent,
    agent_id = agent$agent_id,
    session_id = agent$session_id(),
    working_dir = agent$working_dir,
    run_context = run_context
  )
}

validate_r_session_tool_owner <- function(
  tool,
  agent,
  run_context = agent$run_context
) {
  source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
  owner <- attr(source, "deputy_r_session_owner", exact = TRUE)
  if (
    !is.null(owner) && !identical(owner, r_session_owner(agent, run_context))
  ) {
    tool_registration_error(
      "The R session belongs to a different Agent, session, workspace or run context."
    )
  }
  invisible(NULL)
}

cancel_active_r_session_tools <- function(tools, agent, run_context) {
  owner <- r_session_owner(agent, run_context)
  for (tool in tools) {
    source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
    if (
      !identical(attr(source, "deputy_r_session_owner", exact = TRUE), owner)
    ) {
      next
    }
    cancel <- attr(source, "deputy_r_session_cancel_active", exact = TRUE)
    if (is.function(cancel)) cancel()
  }
  invisible(NULL)
}
