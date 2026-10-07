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

# A portable turn record (from `ellmer::contents_record()`) without its
# activity contents, found by the same marker as `activity_marker()`.
activity_strip_record <- function(record) {
  props <- record$props
  if (!is.list(props) || is.object(props) || !is.list(props$contents)) {
    return(record)
  }
  marked <- vapply(props$contents, activity_record_marked, logical(1))
  if (!any(marked)) {
    return(record)
  }
  record$props$contents <- props$contents[!marked]
  record
}

activity_record_marked <- function(content) {
  props <- if (is.list(content) && !is.object(content)) content$props
  class <- if (is.list(content)) content$class
  if (
    !is.list(props) ||
      is.object(props) ||
      !(identical(class, "ellmer::ContentToolRequest") ||
        identical(class, "ellmer::ContentToolResult"))
  ) {
    return(FALSE)
  }
  marker <- if (is.list(props$extra)) props$extra$deputy_activity
  if (
    !is.list(marker) ||
      is.object(marker) ||
      !identical(marker$format, activity_format) ||
      !is_nonempty_string(marker$activity_id) ||
      !grepl(activity_id_pattern, marker$activity_id)
  ) {
    return(FALSE)
  }
  id <- if (identical(class, "ellmer::ContentToolRequest")) {
    props$id
  } else if (is.list(props$request)) {
    props$request$props$id
  }
  identical(id, marker$activity_id)
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

# A replaced conversation starts the presenter afresh: cards waiting to be
# streamed, labels and counts belong to the conversation they were shown in,
# as do the results a stopped presenter left for the reply streaming now.
activity_reset <- function(agent) {
  private <- agent$.__enclos_env__$private
  private$.activity_leftover <- NULL
  state <- private$.activity
  if (is.null(state)) {
    return(invisible(NULL))
  }
  state$queue <- list()
  state$delegations <- list()
  state$run_id <- NULL
  state$calls <- 0L
  state$limited <- FALSE
  # A reply still streaming belongs to the replaced conversation: its
  # subagents' calls aren't shown in the new one.
  state$skip_run <- private$current_run_id
  invisible(NULL)
}

activity_enable <- function(agent, requester, interval = 0.1) {
  if (!is.function(requester)) {
    cli::cli_abort("{.arg requester} must be a function returning the viewer.")
  }
  private <- agent$.__enclos_env__$private
  # One presenter per lead. A second would show the same calls again under
  # new keys, and the first one's running cards would never be settled.
  if (!is.null(private$.activity)) {
    cli::cli_abort(c(
      "Subagent activity is already shown for this lead.",
      "i" = paste(
        "Call {.fn stop} on the value {.fn subagent_chat_activity} returned",
        "before showing it again."
      )
    ))
  }
  state <- new_activity_presenter(requester, interval)
  private$.activity <- state
  invisible(state)
}

# `presenter` is the one to stop: once it has been stopped and another shown,
# stopping it again leaves the other running.
activity_disable <- function(agent, presenter = NULL) {
  private <- agent$.__enclos_env__$private
  state <- private$.activity
  if (!is.null(presenter) && !identical(state, presenter)) {
    return(invisible(agent))
  }
  # Cards still running when the presenter stops would stay running in saved
  # history, since no later poll will settle them.
  for (entry in activity_open_entries(agent)) {
    activity_settle(
      agent,
      entry,
      "Not shown: subagent activity stopped before this call returned.",
      state = state
    )
  }
  # The reply streaming now, if it started with this presenter, takes what
  # was queued, those results included; a later reply doesn't. A presenter
  # shown during a reply has no stream in it, so an earlier presenter's
  # results for that reply are kept.
  run_id <- private$current_run_id
  earlier <- private$.activity_leftover
  if (
    !is.null(state) &&
      length(state$queue) &&
      !is.null(run_id) &&
      !identical(earlier$run_id, run_id)
  ) {
    private$.activity_leftover <- list(
      run_id = run_id,
      presenter = state,
      queue = state$queue
    )
  }
  private$.activity <- NULL
  invisible(agent)
}

# `presenter` is the one the reading stream started with: a stream takes only
# its own presenter's cards, and what that presenter left queued for this
# reply when it stopped, never another presenter's.
activity_take <- function(agent, presenter = NULL) {
  private <- agent$.__enclos_env__$private
  mine <- function(state) is.null(presenter) || identical(state, presenter)
  queue <- list()
  leftover <- private$.activity_leftover
  if (!is.null(leftover) && mine(leftover$presenter)) {
    private$.activity_leftover <- NULL
    if (identical(leftover$run_id, private$current_run_id)) {
      queue <- leftover$queue
    }
  }
  state <- private$.activity
  if (!is.null(state) && mine(state)) {
    queue <- c(queue, state$queue)
    state$queue <- list()
  }
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

# The delegation an activity ID belongs to, as an opaque key.
activity_id_key <- function(activity_id) {
  sub("^deputy_activity_(.+)_[^_]+$", "\\1", activity_id)
}

activity_new_key <- function() {
  substr(gsub("-", "", new_deputy_id()), 1L, 16L)
}

# Names come from the redacted view, and repeated names are counted by
# delegation key, so a label never shows what the host's redactor removed.
activity_label <- function(agent, state, name, parent_label = NULL) {
  keys <- c(
    vapply(
      agent$.__enclos_env__$private$.activity_overlay,
      function(entry) {
        marker <- activity_marker(entry$content)
        if (identical(marker$agent_name, name)) {
          activity_id_key(marker$activity_id)
        } else {
          ""
        }
      },
      character(1)
    ),
    vapply(
      state$delegations,
      function(entry) {
        if (identical(entry$agent_name, name)) entry$key %||% "" else ""
      },
      character(1)
    )
  )
  ordinal <- length(unique(keys[nzchar(keys)])) + 1L
  label <- if (ordinal > 1L) paste0(name, " #", ordinal) else name
  if (!is.null(parent_label)) {
    label <- paste0(label, " (via ", parent_label, ")")
  }
  inspection_text(label, 256L)
}

# Authorized, redacted view of one delegation with only its own turns, shaped
# like an inspection view so a host's redactor treats both alike. NULL when the
# redacted view is over the disclosure's size bound.
activity_view <- function(agent, record, requester) {
  private <- agent$.__enclos_env__$private
  disclosure <- private$.delegation_disclosure
  view <- lead_inspection_view(agent, record, TRUE, activity_own_turns(record))
  view <- disclosure$redact(view, requester)
  if (!is.list(view)) {
    cli::cli_abort("Disclosure redaction must return a list.")
  }
  inspection_portable(view)
  fits <- tryCatch(
    {
      inspection_bound(view, disclosure)
      TRUE
    },
    error = function(error) FALSE
  )
  if (!fits) {
    return(NULL)
  }
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

# Lineage as the redacted view reports it; `anchor` is the lead's own tool
# call, already in the conversation the viewer sees.
# `root_call` is the lead's tool call ID as the depth-one delegation's
# redacted view reports it, or NULL.
activity_lineage <- function(runtime, root_call, label, activity_id, sequence) {
  text <- function(value, bytes = 256L) {
    if (is_nonempty_string(value)) inspection_text(value, bytes) else NULL
  }
  depth <- runtime$depth
  Filter(
    Negate(is.null),
    list(
      format = activity_format,
      version = activity_version,
      activity_id = activity_id,
      sequence = as.integer(sequence),
      label = label,
      agent_name = text(runtime$agent_name, 64L),
      agent_id = text(runtime$agent_id),
      delegation_id = text(runtime$delegation_id),
      parent_delegation_id = text(runtime$parent_delegation_id),
      depth = if (is.numeric(depth) && length(depth) == 1L && !is.na(depth)) {
        as.integer(depth)
      },
      run_id = text(runtime$run_id),
      conversation_id = text(runtime$session_id),
      root_tool_call_id = text(root_call)
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

# The reason shown is the redacted view's; `settled` comes from the record.
activity_unfinished_content <- function(
  request,
  marker,
  runtime,
  settled,
  closing
) {
  status <- if (is_nonempty_string(runtime$status)) runtime$status
  reason <- runtime$stop_reason
  reason <- if (is_nonempty_string(reason)) reason else status %||% "stopped"
  ellmer::ContentToolResult(
    error = if (closing && !settled) {
      "Not completed when the reply ended."
    } else {
      paste0(
        "Not completed: the subagent ",
        if (identical(status, "failed")) "failed" else "stopped",
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

# Shown requests without a result, as overlay entries; `key` limits them to
# one delegation.
activity_open_entries <- function(agent, key = NULL) {
  prefix <- paste0("deputy_activity_", if (!is.null(key)) paste0(key, "_"))
  requests <- list()
  answered <- character()
  for (entry in agent$.__enclos_env__$private$.activity_overlay) {
    marker <- activity_marker(entry$content)
    if (is.null(marker) || !startsWith(marker$activity_id, prefix)) {
      next
    }
    if (inherits(entry$content, "ellmer::ContentToolResult")) {
      answered <- c(answered, marker$activity_id)
    } else {
      requests[[marker$activity_id]] <- entry
    }
  }
  requests[setdiff(names(requests), answered)]
}

# Give a shown request a result that says why it has none of its own.
activity_settle <- function(agent, entry, text, state = NULL) {
  marker <- entry$content@extra$deputy_activity
  result <- ellmer::ContentToolResult(
    value = text,
    request = entry$content,
    extra = list(
      display = list(label = marker$label),
      deputy_activity = marker
    )
  )
  if (is.null(state)) {
    private <- agent$.__enclos_env__$private
    private$.activity_overlay[[length(private$.activity_overlay) + 1L]] <-
      list(turn = entry$turn, content = result)
  } else {
    activity_emit(agent, state, entry$turn, result)
  }
  invisible(NULL)
}

# One marker card standing in for calls that aren't shown.
activity_note <- function(agent, state, entry, runtime, root_call, kind, text) {
  id <- paste0("deputy_activity_", entry$key, "_", kind)
  marker <- activity_lineage(runtime, root_call, "subagents", id, 0L)
  request <- ellmer::ContentToolRequest(
    id = id,
    name = "more_subagent_tool_calls",
    arguments = list(),
    extra = list(deputy_activity = marker)
  )
  activity_emit(agent, state, entry$anchor_turn, request)
  activity_emit(
    agent,
    state,
    entry$anchor_turn,
    ellmer::ContentToolResult(
      value = text,
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
# A stream polls only the presenter it started with; once that presenter is
# stopped, or another shown, it reads nothing more.
activity_poll <- function(
  agent,
  final = FALSE,
  closing = FALSE,
  presenter = NULL
) {
  private <- agent$.__enclos_env__$private
  state <- private$.activity
  run_id <- private$current_run_id
  if (
    is.null(state) ||
      is.null(run_id) ||
      identical(state$skip_run, run_id) ||
      (!is.null(presenter) && !identical(state, presenter))
  ) {
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
      # Cards already shown still get a result when the reply ends, so none
      # stays running in saved history.
      if (closing) {
        for (open in activity_open_entries(agent)) {
          activity_settle(
            agent,
            open,
            "Not shown: subagent activity could not be read when the reply ended.",
            state = state
          )
        }
      }
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
        key = activity_new_key(),
        anchor_turn = anchor_turn,
        calls = list()
      )
    }
    view <- activity_view(agent, record, requester)
    # The lead's call ID is shown as the depth-one delegation's redacted view
    # reports it, so a redactor that removes it removes it from every card.
    is_root <- identical(root$delegation_id, id)
    root_call <- if (!is_root) state$delegations[[root$delegation_id]]$root_call
    if (is.null(view)) {
      # Calls shown before the record grew too large get a result, so no card
      # stays running in saved history.
      for (open in activity_open_entries(agent, entry$key)) {
        activity_settle(
          agent,
          open,
          paste(
            "Not shown: the subagent's record grew past the size the viewer",
            "may see."
          ),
          state = state
        )
      }
      activity_note(
        agent,
        state,
        entry,
        list(),
        root_call,
        "oversized",
        paste(
          "More tool calls of this subagent aren't shown here: its record is",
          "over the size the viewer may see. Its history is in the subagent",
          "records."
        )
      )
      entry$done <- TRUE
      state$delegations[[id]] <- entry
      next
    }
    runtime <- view$outcome$runtime
    if (!is.list(runtime) || is.object(runtime)) {
      runtime <- list()
    }
    if (is_root) {
      entry$root_call <- if (is_nonempty_string(runtime$tool_call_id)) {
        runtime$tool_call_id
      }
      root_call <- entry$root_call
    }
    if (is.null(entry$label)) {
      name <- runtime$agent_name
      entry$agent_name <- if (is_nonempty_string(name)) {
        inspection_text(name, 64L)
      } else {
        "subagent"
      }
      # Named only when the redacted view still reports the parent.
      parent_id <- runtime$parent_delegation_id
      parent_label <- if (is_nonempty_string(parent_id)) {
        state$delegations[[parent_id]]$label %||% "a subagent"
      }
      entry$label <- activity_label(
        agent,
        state,
        entry$agent_name,
        parent_label
      )
      state$delegations[[id]] <- entry
    }
    calls <- activity_calls(view)
    # Each call keeps the number it was first shown with, matched by its
    # provider ID, tool and arguments, so a redaction that later hides an
    # earlier call can't move a later call onto that call's card.
    known <- entry$calls %||% list()
    call_ids <- vapply(
      calls,
      function(call) activity_call_identity(call$request),
      character(1)
    )
    result_ids <- lapply(calls, function(call) {
      if (!is.null(call$result)) activity_call_identity(call$result)
    })
    slots <- activity_call_slots(known, call_ids, result_ids)
    for (position in seq_along(calls)) {
      call <- calls[[position]]
      call_identity <- call_ids[[position]]
      result_identity <- result_ids[[position]]
      index <- slots[[position]]
      if (is.na(index)) {
        index <- length(known) + 1L
        known[[index]] <- list(identity = call_identity, emitted = character())
      }
      emitted <- known[[index]]$emitted
      activity_id <- paste0("deputy_activity_", entry$key, "_", index)
      marker <- activity_lineage(
        runtime,
        root_call,
        entry$label,
        activity_id,
        index
      )
      request <- activity_request_content(call$request, marker)
      if (!"request" %in% emitted) {
        if (state$calls >= activity_max_calls) {
          if (!isTRUE(state$limited)) {
            activity_note(
              agent,
              state,
              entry,
              runtime,
              root_call,
              "limit",
              paste0(
                "More subagent tool calls ran in this reply than the ",
                activity_max_calls,
                " shown here. Their full history is in the subagent records."
              )
            )
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
          activity_unfinished_content(
            request,
            marker,
            runtime,
            settled,
            closing
          )
        }
        if (!is.null(content)) {
          activity_emit(agent, state, entry$anchor_turn, content)
          emitted <- c(emitted, "result")
          known[[index]]$result <- result_identity %||% "closed"
        }
      }
      known[[index]]$emitted <- emitted
    }
    entry$calls <- known
    if (settled || closing) {
      # A call shown earlier that the view no longer includes still gets a
      # result, so no card stays running in saved history.
      for (open in activity_open_entries(agent, entry$key)) {
        activity_settle(
          agent,
          open,
          "Not shown: the subagent's record no longer shows this call.",
          state = state
        )
      }
    }
    entry$signature <- signature
    entry$done <- settled || closing
    state$delegations[[id]] <- entry
  }
  invisible(NULL)
}

# What identifies a call from one poll to the next, and the result a card
# has shown.
activity_call_identity <- function(content) {
  parts <- if (inherits(content, "ellmer::ContentToolRequest")) {
    list(content@id, content@name, content@arguments)
  } else {
    list(content@value, content@error)
  }
  digest::digest(parts, algo = "sha256")
}

# The shown card each call in the view is, NA for a call not shown yet.
# Identical calls (the same provider ID, tool and arguments) are told apart by
# what their cards show. A call still running, or one whose result no
# identical card has shown, takes the earliest card still waiting. Then a call
# whose result an identical card has shown takes a waiting card if one is
# left, and otherwise that card: when one of two identical calls is hidden,
# it is far likelier the earlier, finished one than a later one still running.
activity_call_slots <- function(known, calls, results) {
  identities <- vapply(known, function(slot) slot$identity, character(1))
  shown <- lapply(known, function(slot) slot$result)
  waiting <- vapply(shown, is.null, logical(1))
  taken <- logical(length(known))
  slots <- rep(NA_integer_, length(calls))
  same <- function(position) {
    result <- results[[position]]
    !is.null(result) &
      identities == calls[[position]] &
      vapply(shown, identical, logical(1), result)
  }
  pick <- function(position, candidates) {
    index <- which(candidates & !taken)[1L]
    if (!is.na(index)) {
      taken[[index]] <<- TRUE
      slots[[position]] <<- index
    }
  }
  repeated <- vapply(
    seq_along(calls),
    function(position) any(same(position)),
    logical(1)
  )
  for (position in which(!repeated)) {
    pick(position, waiting & identities == calls[[position]])
  }
  for (position in which(repeated)) {
    open <- waiting & identities == calls[[position]] & !taken
    pick(position, if (any(open)) open else same(position))
  }
  slots
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
activity_stream <- coro::async_generator(function(agent, inner, presenter) {
  slot <- new.env(parent = emptyenv())
  waiting <- FALSE
  interval <- presenter$interval
  repeat {
    for (content in activity_take(agent, presenter)) {
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
        activity_poll(agent, presenter = presenter)
        next
      }
    }
    waiting <- FALSE
    if (!is.null(slot$error)) {
      activity_poll(agent, closing = TRUE, presenter = presenter)
      for (content in activity_take(agent, presenter)) {
        coro::yield(content)
      }
      rlang::cnd_signal(slot$error)
    }
    value <- slot$value
    if (coro::is_exhausted(value)) {
      activity_poll(agent, closing = TRUE, presenter = presenter)
      for (content in activity_take(agent, presenter)) {
        coro::yield(content)
      }
      break
    }
    if (inherits(value, "ellmer::ContentToolResult")) {
      activity_poll(agent, final = TRUE, presenter = presenter)
      for (content in activity_take(agent, presenter)) {
        coro::yield(content)
      }
    }
    coro::yield(value)
  }
})
