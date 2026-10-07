# Descendant tool activity in a lead's user-facing conversation.
#
# A host that shows one conversation can ask an Agent to include its
# subagents' tool calls in it. Each call becomes a pair of inert ellmer
# contents, a request and a result, attached to the lead's assistant turn that
# holds the delegation, after its own contents. They are part of the
# conversation `get_turns()` returns, so shinychat records and replays them with
# its own history, but never part of the model context the wrapped Chat sends:
# `set_turns()` separates them again. Identities come from the delegation and
# the call's position in it, never from provider tool-call IDs, so concurrent
# children, repeated specialist names and reused provider IDs cannot collide.
#
# Activity is computed on the consumer side of the stream, from authorized and
# redacted views of the delegation records, the same way an inspection panel
# reads them. Execution remains the only consumer of each child stream, and
# nothing here runs a tool or resumes an agent.

activity_format <- "deputy_subagent_activity"
activity_version <- 1L
activity_id_pattern <- "^deputy_activity_[A-Za-z0-9._-]{1,200}$"
# Calls shown per lead run; a marker call replaces the rest.
activity_max_calls <- 256L
# A result value shown without a display, and a request's arguments.
activity_value_bytes <- 262144
activity_argument_bytes <- 16384

activity_marker <- function(content) {
  if (
    !inherits(content, "ellmer::ContentToolRequest") &&
      !inherits(content, "ellmer::ContentToolResult")
  ) {
    return(NULL)
  }
  marker <- tryCatch(content@extra$deputy_activity, error = function(e) NULL)
  if (
    !is.list(marker) ||
      is.object(marker) ||
      !identical(marker$format, activity_format) ||
      !is_nonempty_string(marker$activity_id) ||
      !grepl(activity_id_pattern, marker$activity_id)
  ) {
    return(NULL)
  }
  request <- if (inherits(content, "ellmer::ContentToolRequest")) {
    content
  } else {
    content@request
  }
  if (is.null(request) || !identical(request@id, marker$activity_id)) {
    return(NULL)
  }
  marker
}

is_activity_content <- function(content) {
  !is.null(activity_marker(content))
}

# Separate activity from turns a host supplies, such as a restored shinychat
# conversation. The model context gets the turns without it.
activity_split <- function(turns) {
  overlay <- list()
  for (index in seq_along(turns)) {
    turn <- turns[[index]]
    if (!inherits(turn, "ellmer::Turn")) {
      next
    }
    contents <- turn@contents
    marked <- vapply(contents, is_activity_content, logical(1))
    if (!any(marked)) {
      next
    }
    for (content in contents[marked]) {
      overlay[[length(overlay) + 1L]] <- list(turn = index, content = content)
    }
    turn@contents <- contents[!marked]
    turns[[index]] <- turn
  }
  list(turns = turns, overlay = overlay)
}

activity_merge <- function(turns, overlay) {
  for (entry in overlay) {
    index <- entry$turn
    if (index > length(turns)) {
      next
    }
    turn <- turns[[index]]
    turn@contents <- c(turn@contents, list(entry$content))
    turns[[index]] <- turn
  }
  turns
}

activity_strip <- function(turns) {
  activity_split(turns)$turns
}

new_activity_presenter <- function(requester, interval) {
  state <- new.env(parent = emptyenv())
  state$requester <- requester
  state$interval <- interval
  state$queue <- list()
  state$delegations <- list()
  state$run_id <- NULL
  state$calls <- 0L
  state$limited <- FALSE
  state$error <- NULL
  state
}

activity_enable <- function(agent, requester, interval = 0.1) {
  if (!is.function(requester)) {
    cli::cli_abort("{.arg requester} must be a function returning the viewer.")
  }
  private <- agent$.__enclos_env__$private
  private$.activity <- new_activity_presenter(requester, interval)
  invisible(agent)
}

activity_disable <- function(agent) {
  private <- agent$.__enclos_env__$private
  private$.activity <- NULL
  invisible(agent)
}

activity_take <- function(agent) {
  state <- agent$.__enclos_env__$private$.activity
  if (is.null(state) || !length(state$queue)) {
    return(list())
  }
  queue <- state$queue
  state$queue <- list()
  queue
}

# The depth-one delegation a descendant belongs to: its tool call is the one
# in the lead's own turn.
activity_root_record <- function(records, record) {
  seen <- character()
  while (!is.null(record$parent_delegation_id)) {
    if (record$delegation_id %in% seen) {
      return(NULL)
    }
    seen <- c(seen, record$delegation_id)
    record <- records[[record$parent_delegation_id]]
    if (is.null(record)) {
      return(NULL)
    }
  }
  record
}

activity_own_turns <- function(record) {
  turns <- record$turns %||% list()
  first <- (record$turns_before %||% 0L) + 1L
  if (first <= length(turns)) turns[first:length(turns)] else list()
}

# Changes only when a tool call or result appears or the delegation settles,
# so streamed text doesn't trigger a new read.
activity_signature <- function(record) {
  tools <- 0L
  for (turn in activity_own_turns(record)) {
    for (content in turn@contents) {
      if (
        inherits(content, "ellmer::ContentToolRequest") ||
          inherits(content, "ellmer::ContentToolResult")
      ) {
        tools <- tools + 1L
      }
    }
  }
  paste(record$status, tools, is.na(record$completed_at))
}

# The lead's assistant turn holding a delegation's tool request, searched from
# the newest turn: provider IDs can repeat across turns, but the delegation
# belongs to the run in progress.
activity_anchor_turn <- function(agent, tool_call_id) {
  turns <- agent$.__enclos_env__$private$transcript_turns()
  fallback <- NULL
  for (index in rev(seq_along(turns))) {
    turn <- turns[[index]]
    if (!inherits(turn, "ellmer::AssistantTurn")) {
      next
    }
    requests <- Filter(
      function(content) inherits(content, "ellmer::ContentToolRequest"),
      turn@contents
    )
    if (!length(requests)) {
      next
    }
    fallback <- fallback %||% index
    ids <- vapply(requests, function(content) content@id, character(1))
    if (is_nonempty_string(tool_call_id) && tool_call_id %in% ids) {
      return(index)
    }
  }
  # A provider without call IDs leaves only the run's latest tool turn.
  fallback
}

activity_label <- function(agent, state, record, records) {
  name <- inspection_text(record$agent_name %||% "subagent", 64L)
  named <- c(
    vapply(
      agent$.__enclos_env__$private$.activity_overlay,
      function(entry) {
        marker <- activity_marker(entry$content)
        if (identical(marker$agent_name, name)) marker$delegation_id else ""
      },
      character(1)
    ),
    vapply(
      state$delegations,
      function(entry) {
        if (identical(entry$agent_name, name)) entry$delegation_id else ""
      },
      character(1)
    )
  )
  ordinal <- length(unique(named[nzchar(named)])) + 1L
  label <- if (ordinal > 1L) paste0(name, " #", ordinal) else name
  parent <- if (!is.null(record$parent_delegation_id)) {
    records[[record$parent_delegation_id]]
  }
  if (!is.null(parent)) {
    parent_name <- state$delegations[[parent$delegation_id]]$label %||%
      inspection_text(parent$agent_name %||% "subagent", 64L)
    label <- paste0(label, " (via ", parent_name, ")")
  }
  inspection_text(label, 256L)
}

# Authorized, redacted view of one delegation with only its own turns, shaped
# like an inspection view so a host's redactor treats both alike.
activity_view <- function(agent, record, requester) {
  private <- agent$.__enclos_env__$private
  disclosure <- private$.delegation_disclosure
  view <- lead_inspection_view(agent, record, TRUE, activity_own_turns(record))
  view <- disclosure$redact(view, requester)
  if (!is.list(view)) {
    cli::cli_abort("Disclosure redaction must return a list.")
  }
  inspection_portable(view)
  view
}

# Pair each request in a delegation's turns with its result, in order. A
# repeated provider ID pairs with the earliest unanswered request.
activity_calls <- function(view) {
  calls <- list()
  for (record in view$transcript %||% list()) {
    turn <- inspection_replay(record)
    for (content in turn@contents) {
      if (inherits(content, "ellmer::ContentToolRequest")) {
        calls[[length(calls) + 1L]] <- list(request = content, result = NULL)
      } else if (inherits(content, "ellmer::ContentToolResult")) {
        id <- content@request@id %||% ""
        open <- which(vapply(
          calls,
          function(call) is.null(call$result) && identical(call$request@id, id),
          logical(1)
        ))
        if (length(open)) {
          calls[[open[[1L]]]]$result <- content
        }
      }
    }
  }
  calls
}

activity_lineage <- function(record, anchor, label, activity_id, sequence) {
  text <- function(value, bytes = 256L) {
    if (is_nonempty_string(value)) inspection_text(value, bytes) else NULL
  }
  Filter(
    Negate(is.null),
    list(
      format = activity_format,
      version = activity_version,
      activity_id = activity_id,
      sequence = as.integer(sequence),
      label = label,
      agent_name = text(record$agent_name, 64L),
      agent_id = text(record$agent_id),
      delegation_id = text(record$delegation_id),
      parent_delegation_id = text(record$parent_delegation_id),
      depth = if (is.numeric(record$depth)) as.integer(record$depth),
      run_id = text(record$run_id),
      conversation_id = text(record$session_id),
      root_tool_call_id = text(anchor$tool_call_id)
    )
  )
}

activity_bounded_value <- function(value, bytes, label) {
  if (observation_payload_fits(value, bytes)) {
    return(value)
  }
  paste0(
    "[",
    label,
    " omitted from the conversation view: over ",
    bytes,
    " bytes.]"
  )
}

activity_request_content <- function(request, marker) {
  arguments <- request@arguments
  if (!is.list(arguments) || is.object(arguments)) {
    arguments <- list()
  }
  if (!observation_payload_fits(arguments, activity_argument_bytes)) {
    arguments <- list(`_omitted` = "Arguments over 16 KiB are not shown.")
  }
  ellmer::ContentToolRequest(
    id = marker$activity_id,
    name = request@name,
    arguments = arguments,
    extra = list(deputy_activity = marker)
  )
}

activity_result_content <- function(result, request, marker) {
  display <- result@extra$display
  display <- if (is.list(display)) subagent_safe_display(display) else list()
  display$label <- if (is_nonempty_string(display$label)) {
    inspection_text(paste0(marker$label, ": ", display$label), 1024L)
  } else {
    marker$label
  }
  extra <- list(display = display)
  if (is_nonempty_string(result@extra$commons_tag)) {
    extra$commons_tag <- result@extra$commons_tag
  }
  extra$deputy_activity <- marker
  if (!is.null(result@error)) {
    return(ellmer::ContentToolResult(
      error = inspection_text(as.character(result@error)[[1L]], 4096L),
      request = request,
      extra = extra
    ))
  }
  ellmer::ContentToolResult(
    value = activity_bounded_value(
      result@value,
      activity_value_bytes,
      "Result"
    ),
    request = request,
    extra = extra
  )
}

activity_unfinished_content <- function(request, marker, record, closing) {
  reason <- record$stop_reason %||% record$status %||% "stopped"
  ellmer::ContentToolResult(
    error = if (closing && is.na(record$completed_at)) {
      "Not completed when the reply ended."
    } else {
      paste0(
        "Not completed: the subagent ",
        if (identical(record$status, "failed")) "failed" else "stopped",
        " (",
        inspection_text(reason, 128L),
        ") before this call returned."
      )
    },
    request = request,
    extra = list(
      display = list(label = marker$label),
      deputy_activity = marker
    )
  )
}

activity_emit <- function(agent, state, anchor_turn, content) {
  private <- agent$.__enclos_env__$private
  private$.activity_overlay[[length(private$.activity_overlay) + 1L]] <- list(
    turn = anchor_turn,
    content = content
  )
  state$queue[[length(state$queue) + 1L]] <- content
  invisible(NULL)
}

activity_limit_marker <- function(agent, state, anchor_turn, record, anchor) {
  id <- paste0(
    "deputy_activity_",
    sub("^delegation_", "", record$delegation_id),
    "_limit"
  )
  marker <- activity_lineage(record, anchor, "subagents", id, 0L)
  request <- ellmer::ContentToolRequest(
    id = id,
    name = "more_subagent_tool_calls",
    arguments = list(),
    extra = list(deputy_activity = marker)
  )
  activity_emit(agent, state, anchor_turn, request)
  activity_emit(
    agent,
    state,
    anchor_turn,
    ellmer::ContentToolResult(
      value = paste0(
        "More subagent tool calls ran in this reply than the ",
        activity_max_calls,
        " shown here. Their full history is in the subagent records."
      ),
      request = request,
      extra = list(
        display = list(label = "subagents"),
        deputy_activity = marker
      )
    )
  )
}

# Bring the lead's view of its subagents' tool calls up to date. `final`
# rereads every open delegation and settles calls that won't return once their
# delegation has settled; `closing` does so for every open call, because the
# lead's reply is ending and a card must not stay running in saved history.
activity_poll <- function(agent, final = FALSE, closing = FALSE) {
  private <- agent$.__enclos_env__$private
  state <- private$.activity
  run_id <- private$current_run_id
  if (is.null(state) || is.null(run_id)) {
    return(invisible(NULL))
  }
  if (!identical(state$run_id, run_id)) {
    state$run_id <- run_id
    state$calls <- 0L
    state$limited <- FALSE
  }
  result <- tryCatch(
    {
      requester <- state$requester()
      inspection_authorize(
        private$.delegation_disclosure,
        requester,
        inspection_scope(agent)
      )
      activity_refresh(
        agent,
        state,
        requester,
        run_id,
        final || closing,
        closing
      )
      state$error <- NULL
    },
    error = function(error) {
      # A viewer who may not see the subagents sees no activity; the runs and
      # the lead's own conversation are unaffected.
      state$error <- inspection_text(conditionMessage(error), 1024L)
    }
  )
  invisible(result)
}

activity_refresh <- function(
  agent,
  state,
  requester,
  run_id,
  final,
  closing = FALSE
) {
  records <- lead_delegation_records(agent, messages = TRUE)
  names(records) <- vapply(
    records,
    function(record) record$delegation_id,
    character(1)
  )
  for (record in records) {
    id <- record$delegation_id
    entry <- state$delegations[[id]]
    if (isTRUE(entry$done)) {
      next
    }
    root <- activity_root_record(records, record)
    if (is.null(root) || !identical(root$parent_run_id, run_id)) {
      next
    }
    signature <- activity_signature(record)
    settled <- !is.na(record$completed_at)
    if (!final && !is.null(entry) && identical(entry$signature, signature)) {
      next
    }
    if (is.null(entry)) {
      anchor_turn <- activity_anchor_turn(agent, root$tool_call_id)
      if (is.null(anchor_turn)) {
        next
      }
      entry <- list(
        delegation_id = id,
        agent_name = inspection_text(record$agent_name %||% "subagent", 64L),
        anchor_turn = anchor_turn,
        emitted = list()
      )
      entry$label <- activity_label(agent, state, record, records)
      state$delegations[[id]] <- entry
    }
    view <- activity_view(agent, record, requester)
    calls <- activity_calls(view)
    suffix <- sub("^delegation_", "", id)
    for (index in seq_along(calls)) {
      call <- calls[[index]]
      key <- as.character(index)
      emitted <- entry$emitted[[key]] %||% character()
      activity_id <- paste0("deputy_activity_", suffix, "_", index)
      marker <- activity_lineage(record, root, entry$label, activity_id, index)
      request <- activity_request_content(call$request, marker)
      if (!"request" %in% emitted) {
        if (state$calls >= activity_max_calls) {
          if (!isTRUE(state$limited)) {
            activity_limit_marker(agent, state, entry$anchor_turn, record, root)
            state$limited <- TRUE
          }
          break
        }
        activity_emit(agent, state, entry$anchor_turn, request)
        state$calls <- state$calls + 1L
        emitted <- c(emitted, "request")
      }
      if (!"result" %in% emitted) {
        content <- if (!is.null(call$result)) {
          activity_result_content(call$result, request, marker)
        } else if (settled || closing) {
          activity_unfinished_content(request, marker, record, closing)
        }
        if (!is.null(content)) {
          activity_emit(agent, state, entry$anchor_turn, content)
          emitted <- c(emitted, "result")
        }
      }
      entry$emitted[[key]] <- emitted
    }
    entry$signature <- signature
    entry$done <- settled || closing
    state$delegations[[id]] <- entry
  }
  invisible(NULL)
}

activity_wait <- function(slot, seconds) {
  promises::promise(function(resolve, reject) {
    slot$waiter <- resolve
    later::later(
      function() {
        if (identical(slot$waiter, resolve)) {
          slot$waiter <- NULL
          resolve(FALSE)
        }
      },
      seconds
    )
  })
}

activity_wake <- function(slot) {
  waiter <- slot$waiter
  if (is.function(waiter)) {
    slot$waiter <- NULL
    waiter(TRUE)
  }
  invisible(NULL)
}

activity_watch <- function(slot, value) {
  slot$done <- FALSE
  slot$value <- NULL
  slot$error <- NULL
  promises::then(
    promises::as.promise(value),
    onFulfilled = function(result) {
      slot$value <- result
      slot$done <- TRUE
      activity_wake(slot)
    },
    onRejected = function(error) {
      slot$error <- error
      slot$done <- TRUE
      activity_wake(slot)
    }
  )
  invisible(NULL)
}

# The lead's stream with its subagents' tool calls merged in as they happen.
# While the lead waits on a delegation, the stream checks for new calls on a
# timer; before it yields a tool result, and when it ends, it settles them.
activity_stream <- coro::async_generator(function(agent, inner, interval) {
  slot <- new.env(parent = emptyenv())
  waiting <- FALSE
  repeat {
    for (content in activity_take(agent)) {
      coro::yield(content)
    }
    if (!waiting) {
      next_value <- tryCatch(
        inner(),
        error = function(error) promises::promise_reject(error)
      )
      activity_watch(slot, next_value)
      waiting <- TRUE
    }
    if (!isTRUE(slot$done)) {
      coro::await(activity_wait(slot, interval))
      if (!isTRUE(slot$done)) {
        activity_poll(agent)
        next
      }
    }
    waiting <- FALSE
    if (!is.null(slot$error)) {
      activity_poll(agent, closing = TRUE)
      for (content in activity_take(agent)) {
        coro::yield(content)
      }
      rlang::cnd_signal(slot$error)
    }
    value <- slot$value
    if (coro::is_exhausted(value)) {
      activity_poll(agent, closing = TRUE)
      for (content in activity_take(agent)) {
        coro::yield(content)
      }
      break
    }
    if (inherits(value, "ellmer::ContentToolResult")) {
      activity_poll(agent, final = TRUE)
      for (content in activity_take(agent)) {
        coro::yield(content)
      }
    }
    coro::yield(value)
  }
})
