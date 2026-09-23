# Governed host invocation from a persistent R session.

r_session_tool_argument_max_bytes <- 1024^2
r_session_tool_result_max_bytes <- 8 * 1024^2

r_session_tool_dispatch_abort <- function(
  message,
  ...,
  .envir = parent.frame()
) {
  abort_deputy(
    message,
    class = c("r_session_tool_dispatch", "tool"),
    ...,
    .envir = .envir
  )
}

r_session_tool_abandoned_condition <- function(reason) {
  rlang::catch_cnd(
    r_session_tool_dispatch_abort(
      paste0(
        "The enclosing R execution ended before the nested tool result ",
        "arrived (reason: {reason})."
      ),
      reason = reason
    ),
    "error"
  )
}

r_session_tool_context <- function() {
  context <- tryCatch(
    ellmer::tool_context(),
    error = function(error) NULL
  )
  if (
    !is.list(context) ||
      !isTRUE(context$deputy_r_session_nested)
  ) {
    return(NULL)
  }

  parent_tool_call_id <- context$parent_tool_call_id
  if (!is_nonempty_string(parent_tool_call_id)) {
    return(NULL)
  }

  list(
    parent_tool_call_id = parent_tool_call_id,
    execution_id = if (is_nonempty_string(context$r_session_execution_id)) {
      context$r_session_execution_id
    } else {
      NULL
    },
    generation = if (is_nonempty_string(context$r_session_generation)) {
      context$r_session_generation
    } else {
      NULL
    }
  )
}

r_session_tool_record_context <- function(record) {
  fields <- list(
    parent_tool_call_id = record$parent_tool_call_id,
    r_session_execution_id = record$r_session_execution_id,
    r_session_generation = record$r_session_generation
  )
  fields[!vapply(fields, is.null, logical(1))]
}

r_session_tool_agent_event <- function(private, type, record, ...) {
  do.call(
    private$agent_event,
    c(
      list(type = type),
      list(...),
      r_session_tool_record_context(record)
    )
  )
}

r_session_tool_notify_observers <- function(private, phase, payload) {
  callbacks <- private[[paste0(".tool_", phase, "_observers")]]
  coro::async(function() {
    for (callback in callbacks) {
      coro::await(callback(payload))
    }
    invisible(NULL)
  })()
}

r_session_tool_notify <- function(private, message, record, ...) {
  do.call(
    private$notify,
    c(
      list(message = message),
      list(...),
      r_session_tool_record_context(record)
    )
  )
}

r_session_tool_argument_size <- function(arguments) {
  tryCatch(
    length(serialize(arguments, NULL, version = 3)),
    error = function(error) NA_real_
  )
}

r_session_tool_validate_arguments <- function(arguments) {
  if (!is.list(arguments) || is.object(arguments)) {
    r_session_tool_dispatch_abort(
      "Nested R session tool arguments must be a plain named list."
    )
  }
  approval_validate_inputs(arguments)
  bytes <- r_session_tool_argument_size(arguments)
  if (
    is.na(bytes) ||
      !is.finite(bytes) ||
      bytes > r_session_tool_argument_max_bytes
  ) {
    r_session_tool_dispatch_abort(c(
      "Nested R session tool arguments exceed the 1 MiB transfer bound.",
      "i" = "Pass a bounded JSON record and keep large values in a host-owned artifact."
    ))
  }
  arguments
}

r_session_tool_validate_result_size <- function(value) {
  bytes <- tryCatch(
    length(serialize(value, NULL, version = 3)),
    error = function(error) NA_real_
  )
  if (
    is.na(bytes) ||
      !is.finite(bytes) ||
      bytes > r_session_tool_result_max_bytes
  ) {
    r_session_tool_dispatch_abort(c(
      "Nested R session tool result exceeds the 8 MiB transfer bound.",
      "i" = "Return a bounded value or use Deputy's existing result offload path."
    ))
  }
  invisible(value)
}

r_session_tool_parent_record <- function(private, parent_tool_call_id) {
  records <- private$tool_call_records
  matches <- Filter(
    function(record) {
      identical(record$tool_call_id, parent_tool_call_id) &&
        isTRUE(record$request_seen) &&
        isTRUE(record$execution_started) &&
        !isTRUE(record$end_seen)
    },
    records
  )
  if (
    length(matches) != 1L || !identical(matches[[1L]]$tool_name, "run_r_code")
  ) {
    r_session_tool_dispatch_abort(
      "Nested R session tools require the active registered run_r_code call."
    )
  }
  matches[[1L]]
}

r_session_tool_dispatcher <- function(
  agent,
  tool_names,
  parent_tool_call_id,
  run_id
) {
  if (!inherits(agent, "Agent")) {
    r_session_tool_dispatch_abort("{.arg agent} must be an Agent.")
  }
  private <- agent$.__enclos_env__$private
  if (
    !is_nonempty_string(run_id) ||
      !is_nonempty_string(parent_tool_call_id)
  ) {
    r_session_tool_dispatch_abort(
      "Nested R session dispatch requires non-empty run_id and parent_tool_call_id."
    )
  }
  if (
    !isTRUE(private$run_active) ||
      !identical(private$current_run_id, run_id)
  ) {
    r_session_tool_dispatch_abort(
      "Nested R session tools require their owning Agent's active governed run."
    )
  }

  context <- tryCatch(ellmer::tool_context(), error = function(error) NULL)
  request <- if (is.list(context)) context$request else NULL
  if (
    is.null(request) ||
      !inherits(request, "ellmer::ContentToolRequest") ||
      !identical(request@id, parent_tool_call_id) ||
      !identical(request@name, "run_r_code")
  ) {
    r_session_tool_dispatch_abort(
      "Nested R session tools must be requested from an active registered run_r_code call."
    )
  }
  parent_source <- attr(
    request@tool,
    "deputy_runtime_source_tool",
    exact = TRUE
  ) %||%
    request@tool
  parent_owner <- attr(
    parent_source,
    "deputy_r_session_owner",
    exact = TRUE
  )
  if (
    is.null(parent_owner) ||
      !identical(parent_owner$agent, agent)
  ) {
    r_session_tool_dispatch_abort(
      "The active run_r_code call does not belong to this Agent."
    )
  }
  r_session_tool_parent_record(private, parent_tool_call_id)

  if (
    !is.character(tool_names) ||
      length(tool_names) == 0L ||
      anyNA(tool_names) ||
      !all(nzchar(tool_names)) ||
      anyDuplicated(tool_names)
  ) {
    r_session_tool_dispatch_abort(
      "{.arg tool_names} must contain unique non-empty tool names."
    )
  }

  registered <- private$.chat$get_tools()
  selected <- lapply(tool_names, function(name) {
    tool <- registered[[name]]
    if (is.null(tool) || !inherits(tool, "ellmer::ToolDef")) {
      r_session_tool_dispatch_abort(
        "Nested R session tool {.val {name}} is not registered as a function tool."
      )
    }
    source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||%
      tool
    if (!identical(source@name, name)) {
      r_session_tool_dispatch_abort(
        "Nested R session tool {.val {name}} does not have an exact registered executable."
      )
    }
    if (isTRUE(source@convert)) {
      r_session_tool_dispatch_abort(c(
        "Nested R session tool {.val {name}} must use {.code convert = FALSE}.",
        "i" = "The worker sends bounded raw JSON arguments; the tool validates its own domain inputs."
      ))
    }
    if (
      identical(name, "run_r_code") ||
        identical(name, "run_bash") ||
        !is.null(composition_tool_owner(tool)) ||
        !is.null(composition_tool_owner(source)) ||
        !is.null(attr(source, "deputy_r_session_owner", exact = TRUE))
    ) {
      r_session_tool_dispatch_abort(
        "Nested R session dispatch cannot invoke recursive execution or composition tools."
      )
    }
    list(tool = tool, source = source)
  })
  names(selected) <- tool_names

  state <- new.env(parent = emptyenv())
  state$active <- list()
  state$abandoned <- list()

  current <- function() {
    if (
      !isTRUE(private$run_active) ||
        !identical(private$current_run_id, run_id) ||
        isTRUE(private$should_stop)
    ) {
      r_session_tool_dispatch_abort(
        "The owning governed run is no longer accepting nested R session work."
      )
    }
    r_session_tool_parent_record(private, parent_tool_call_id)
    invisible(NULL)
  }

  selected_current <- function(name) {
    registered_now <- private$.chat$get_tools()[[name]]
    source_now <- attr(
      registered_now,
      "deputy_runtime_source_tool",
      exact = TRUE
    ) %||%
      registered_now
    if (!identical(source_now, selected[[name]]$source)) {
      r_session_tool_dispatch_abort(
        "The selected nested tool was replaced after dispatcher admission."
      )
    }
    invisible(NULL)
  }

  invoke <- function(
    name,
    arguments,
    execution_id = NULL,
    generation = NULL
  ) {
    current()
    if (!is_nonempty_string(name) || !name %in% names(selected)) {
      r_session_tool_dispatch_abort(
        "Nested R session requested an unknown or unselected tool {.val {name}}."
      )
    }
    if (
      !is.null(execution_id) &&
        !is_nonempty_string(execution_id)
    ) {
      r_session_tool_dispatch_abort(
        "{.arg execution_id} must be NULL or one non-empty string."
      )
    }
    if (
      !is.null(generation) &&
        !is_nonempty_string(generation)
    ) {
      r_session_tool_dispatch_abort(
        "{.arg generation} must be NULL or one non-empty string."
      )
    }
    arguments <- r_session_tool_validate_arguments(arguments)

    selected_current(name)
    if (!is.null(private$.approval_dir)) {
      r_session_tool_dispatch_abort(c(
        "Nested R session tools cannot suspend for durable approval.",
        "i" = "The active R expression has no resumable stack; deny the nested request before its effect."
      ))
    }

    request_id <- new_deputy_id("r_tool_")
    request <- ellmer::ContentToolRequest(
      id = request_id,
      name = name,
      arguments = arguments,
      tool = selected[[name]]$source,
      extra = list(
        deputy_r_session = list(
          parent_tool_call_id = parent_tool_call_id,
          execution_id = execution_id,
          generation = generation
        )
      )
    )
    tool_context <- structure(
      list(
        request = request,
        turns = private$.chat$get_turns(),
        deputy_r_session_nested = TRUE,
        parent_tool_call_id = parent_tool_call_id,
        r_session_execution_id = execution_id,
        r_session_generation = generation
      ),
      class = "ellmer_tool_context"
    )
    state$active[[request_id]] <- list(
      execution_id = execution_id,
      generation = generation,
      request = request
    )
    pending <- FALSE
    on.exit(
      {
        if (!pending) state$active[[request_id]] <- NULL
      },
      add = TRUE
    )

    # The enclosing R execution may end (timeout, cancellation, worker exit)
    # while this request is still pending. Governance then records the
    # abandonment; the late result must neither execute nor settle again.
    live <- function() {
      abandoned <- state$abandoned[[request_id]]
      if (!is.null(abandoned)) {
        stop(abandoned)
      }
      if (is.null(state$active[[request_id]])) {
        r_session_tool_dispatch_abort(
          "A nested R session request was settled before it completed."
        )
      }
      current()
    }

    settle <- function(value = NULL, error = NULL) {
      active <- state$active[[request_id]]
      if (is.null(active)) {
        abandoned <- state$abandoned[[request_id]]
        if (!is.null(abandoned)) {
          stop(abandoned)
        }
        r_session_tool_dispatch_abort(
          "A nested R session result arrived after its request was settled."
        )
      }
      if (
        !isTRUE(private$run_active) ||
          !identical(private$current_run_id, run_id)
      ) {
        state$active[[request_id]] <- NULL
        r_session_tool_dispatch_abort(
          "A nested R session result arrived after its owning run stopped."
        )
      }
      on.exit(
        {
          state$active[[request_id]] <- NULL
        },
        add = TRUE
      )
      r_session_tool_parent_record(private, parent_tool_call_id)

      if (is.null(error)) {
        result_value <- tryCatch(
          {
            approval_portable(value, allow_classed = TRUE)
            r_session_tool_validate_result_size(value)
            private$offload_tool_result(name, value, request_id)
          },
          error = identity
        )
        if (inherits(result_value, "condition")) {
          error <- result_value
        } else {
          value <- result_value
        }
      }

      content <- if (is.null(error)) {
        ellmer::ContentToolResult(value = value, request = request)
      } else {
        ellmer::ContentToolResult(error = error, request = request)
      }
      observed <- private$handle_tool_result(content)
      if (!is.null(error)) {
        stop(error)
      }
      observed
    }

    pending <- TRUE
    coro::async(function() {
      value <- tryCatch(
        {
          live()
          ellmer::with_tool_context(
            tool_context,
            private$handle_tool_request(request)
          )
          coro::await(r_session_tool_notify_observers(
            private,
            "request",
            request
          ))
          live()
          selected_current(name)
          execution <- private$begin_tool_execution(name, request_id)
          if (!is_nonempty_string(execution)) {
            r_session_tool_dispatch_abort(
              "Nested tool execution could not be admitted."
            )
          }
          resolved <- arguments
          if (
            !identical(
              tool_metadata(selected[[name]]$source)$source$type,
              "mcp"
            )
          ) {
            resolved <- private$resolve_tool_arguments(name, arguments)
          }
          coro::await(ellmer::with_tool_context(
            tool_context,
            private$execute_tool(selected[[name]]$source, resolved, execution)
          ))
        },
        error = identity
      )
      if (inherits(value, "condition")) {
        result <- tryCatch(settle(error = value), error = identity)
      } else {
        result <- tryCatch(settle(value = value), error = identity)
      }
      # Governance has already recorded the outcome. User observers receive
      # the same request identity without adding synthetic model turns.
      if (
        isTRUE(private$run_active) && identical(private$current_run_id, run_id)
      ) {
        if (inherits(result, "condition")) {
          content <- ellmer::ContentToolResult(
            error = result,
            request = request
          )
        } else {
          content <- ellmer::ContentToolResult(
            value = result,
            request = request
          )
        }
        coro::await(r_session_tool_notify_observers(private, "result", content))
      }
      if (inherits(result, "condition")) {
        stop(result)
      }
      result
    })()
  }

  # Settle every request still in flight when the enclosing R execution
  # leaves the active slot. Each pending call is recorded as a tool error
  # under its original request identity while the parent run_r_code record
  # is still open, so counters stay balanced and a tool_end event is emitted.
  # A result arriving later is dropped by settle().
  abandon <- function(reason = "ended") {
    reason <- if (is_nonempty_string(reason)) reason else "ended"
    ids <- names(state$active)
    for (request_id in ids) {
      active <- state$active[[request_id]]
      state$active[[request_id]] <- NULL
      condition <- r_session_tool_abandoned_condition(reason)
      state$abandoned[[request_id]] <- condition
      if (
        !isTRUE(private$run_active) ||
          !identical(private$current_run_id, run_id) ||
          !inherits(active$request, "ellmer::ContentToolRequest")
      ) {
        next
      }
      tryCatch(
        private$handle_tool_result(
          ellmer::ContentToolResult(
            error = condition,
            request = active$request
          )
        ),
        error = function(error) NULL
      )
    }
    invisible(ids)
  }

  attr(invoke, "deputy_r_session_tool_dispatcher") <- TRUE
  attr(invoke, "deputy_r_session_abandon") <- abandon
  attr(invoke, "deputy_r_session_tool_names") <- tool_names
  attr(invoke, "deputy_r_session_parent_tool_call_id") <- parent_tool_call_id
  attr(invoke, "deputy_r_session_run_id") <- run_id
  invoke
}
