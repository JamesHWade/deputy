# Descendant tool activity in a lead's user-facing conversation.
#
# A host that shows one conversation can ask an Agent to include its
# subagents' tool calls in it. Each call becomes a pair of inert ellmer
# contents, a request and a result, attached to the lead's assistant turn that
# holds the delegation, after its own contents. They are part of the
# conversation `get_turns()` returns, so shinychat records and replays them with
# its own history, but never part of the model context the wrapped Chat sends:
# `set_turns()` and `add_turn()` separate them again. Identities come from the
# delegation and the call's position in it, never from provider tool-call IDs,
# so concurrent children, repeated specialist names and reused provider IDs
# cannot collide.
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
# A tool name: providers allow far shorter ones, so a longer name (from a
# provider or a redactor) is cut, and every part of a card stays bounded.
activity_name_bytes <- 256L

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

#' Which subagent call a shown tool card is
#'
#' [subagent_chat_activity()] shows each tool call a subagent makes as a pair of
#' cards in the lead's conversation: a request and its result. Use this
#' function on the contents of `lead$get_turns()` to tell those cards apart
#' from the lead's own tool calls, for example to check an answer against what
#' the subagent's tools returned. Use `lead$get_turns(activity = FALSE)` to
#' leave the cards out instead.
#'
#' @param content An ellmer content object.
#' @return `NULL` unless `content` is a card shown by
#'   [subagent_chat_activity()]. For a card, a list with:
#'   * `activity_id`: the card's ID, which its request and result share.
#'   * `root_tool_call_id`: the ID of the lead's tool call that delegated the
#'     work, so you can find the delegation the card belongs to.
#'   * `label`, `agent_name`, `agent_id`: which subagent made the call.
#'   * `depth`: 1 for the lead's own subagents, 2 for theirs, and so on.
#'   * `sequence`, `delegation_id`, `parent_delegation_id`, `run_id`: the
#'     call's position among the cards and the delegation it ran in.
#'
#'   Fields with no value are left out.
#' @seealso [subagent_chat_activity()]
#' @export
#' @examples
#' subagent_activity_info(ellmer::ContentText("Not a card"))
subagent_activity_info <- function(content) {
  marker <- activity_marker(content)
  if (is.null(marker)) {
    return(NULL)
  }
  marker[setdiff(names(marker), c("format", "version", "conversation_id"))]
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
  overlay_split(turns, is_activity_content)
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
  turns <- agent_private(agent)$transcript_turns()
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
activity_label <- function(agent, state, name) {
  keys <- c(
    vapply(
      agent_private(agent)$.activity_overlay,
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
  if (ordinal > 1L) paste0(name, " #", ordinal) else name
}

# Authorized, redacted view of one delegation with only its own turns, shaped
# like an inspection view so a host's redactor treats both alike. NULL when the
# redacted view is over the disclosure's size bound.
activity_view <- function(agent, record, requester) {
  disclosure <- lead_disclosure(agent)
  view <- lead_inspection_view(agent, record, TRUE, activity_own_turns(record))
  view <- inspection_redact(disclosure, view, requester)
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
    name = inspection_text(request@name, activity_name_bytes),
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
  private <- agent_private(agent)
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
  for (entry in agent_private(agent)$.activity_overlay) {
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

# A result for a shown request that says why it has none of its own.
activity_settled_result <- function(entry, text) {
  marker <- entry$content@extra$deputy_activity
  ellmer::ContentToolResult(
    value = text,
    request = entry$content,
    extra = list(
      display = list(label = marker$label),
      deputy_activity = marker
    )
  )
}

# Give a shown request a result that says why it has none of its own.
activity_settle <- function(agent, entry, text, state = NULL) {
  result <- activity_settled_result(entry, text)
  if (is.null(state)) {
    private <- agent_private(agent)
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

# Once per reply, the note that more calls ran than are shown.
activity_limit_note <- function(agent, state, entry, runtime, root_call) {
  if (isTRUE(state$limited)) {
    return(invisible(NULL))
  }
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
  invisible(NULL)
}

activity_name <- function(runtime) {
  name <- runtime$agent_name
  if (is_nonempty_string(name)) inspection_text(name, 64L) else "subagent"
}

# The label and lead call ID a delegation's new cards carry, from `runtime` as
# its redacted view reports it in this refresh: its name, numbered while the
# view still shows the name first shown; its parent's label while the view
# still reports a parent; and the lead's call ID as the depth-one
# delegation's view reports it. An ancestor's part comes from the ancestor's
# view as read in this refresh, never an earlier read, so a viewer or
# redaction that has changed since sees only what it allows now.
activity_attribute <- function(
  agent,
  state,
  records,
  record,
  runtime,
  requester,
  pass
) {
  id <- record$delegation_id
  name <- activity_name(runtime)
  entry <- state$delegations[[id]]
  label <- if (identical(name, entry$agent_name)) entry$numbered else name
  parent_id <- runtime$parent_delegation_id
  parent <- NULL
  if (is_nonempty_string(parent_id)) {
    parent <- activity_attribution(
      agent,
      state,
      records,
      parent_id,
      requester,
      pass
    )
    label <- paste0(label, " (via ", parent$label %||% "a subagent", ")")
  }
  # The lead's call is reached only through parents the redacted views
  # report, so a view that hides its parent hides that call too.
  root_call <- if (is.null(record$parent_delegation_id)) {
    if (is_nonempty_string(runtime$tool_call_id)) runtime$tool_call_id
  } else {
    parent$root_call
  }
  list(label = inspection_text(label, 256L), root_call = root_call)
}

# A delegation's attribution as the requester's redacted view shows it in this
# refresh, read at most once. A parent ID comes from a redacted view, so one
# leading back to a delegation already being worked out has no label.
activity_attribution <- function(agent, state, records, id, requester, pass) {
  if (!is.null(pass$done[[id]])) {
    return(pass$done[[id]])
  }
  record <- records[[id]]
  if (is.null(record) || id %in% pass$visiting) {
    return(list())
  }
  pass$visiting <- c(pass$visiting, id)
  view <- activity_view(agent, record, requester)
  runtime <- if (!is.null(view)) view$outcome$runtime
  attribution <- if (is.list(runtime) && !is.object(runtime)) {
    activity_attribute(agent, state, records, record, runtime, requester, pass)
  } else {
    list()
  }
  pass$visiting <- setdiff(pass$visiting, id)
  pass$done[[id]] <- attribution
  attribution
}

activity_handle_oversized <- function(agent, state, id, entry) {
  # Without a view, nothing the viewer may see links the delegation to
  # the lead's call, so its note doesn't name one.
  root_call <- NULL
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
  # The note is a card like any other, so it counts toward the reply's limit.
  if (state$calls >= activity_max_calls) {
    activity_limit_note(agent, state, entry, list(), root_call)
  } else {
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
    state$calls <- state$calls + 1L
  }
  entry$done <- TRUE
  state$delegations[[id]] <- entry
  invisible(entry)
}

activity_emit_delegation_calls <- function(
  agent,
  state,
  record,
  view,
  entry,
  runtime,
  root_call,
  settled,
  closing
) {
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
  # Its provider ID and tool alone identify a call when no other request in
  # the record or the view has them, so a call the redactor shows
  # differently from one view to the next keeps its card.
  call_keys <- vapply(
    calls,
    function(call) activity_call_key(call$request),
    character(1)
  )
  record_keys <- activity_record_keys(record)
  unique_keys <- vapply(
    call_keys,
    function(key) {
      sum(record_keys == key) == 1L && sum(call_keys == key) == 1L
    },
    logical(1),
    USE.NAMES = FALSE
  )
  slots <- activity_call_slots(
    known,
    call_ids,
    result_ids,
    call_keys,
    unique_keys
  )
  for (position in seq_along(calls)) {
    call <- calls[[position]]
    call_identity <- call_ids[[position]]
    result_identity <- result_ids[[position]]
    index <- slots[[position]]
    if (is.na(index)) {
      index <- length(known) + 1L
      known[[index]] <- list(
        identity = call_identity,
        key = call_keys[[position]],
        emitted = character()
      )
    }
    # The card follows the call as it's shown now, so later views match it
    # in that form.
    known[[index]]$identity <- call_identity
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
        activity_limit_note(agent, state, entry, runtime, root_call)
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
    } else if (!is.null(result_identity)) {
      known[[index]]$result <- result_identity
    }
    known[[index]]$emitted <- emitted
  }
  known
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
  # What each delegation's cards say of it, as the requester's redacted views
  # show it in this refresh (`activity_attribution()`).
  pass <- new.env(parent = emptyenv())
  pass$done <- list()
  pass$visiting <- character()
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
    if (is.null(view)) {
      activity_handle_oversized(agent, state, id, entry)
      next
    }
    runtime <- view$outcome$runtime
    if (!is.list(runtime) || is.object(runtime)) {
      runtime <- list()
    }
    # The number that tells delegations of one name apart is drawn once, for
    # the name first shown.
    if (is.null(entry$agent_name)) {
      entry$agent_name <- activity_name(runtime)
      entry$numbered <- activity_label(agent, state, entry$agent_name)
      state$delegations[[id]] <- entry
    }
    attribution <- activity_attribute(
      agent,
      state,
      records,
      record,
      runtime,
      requester,
      pass
    )
    pass$done[[id]] <- attribution
    entry$label <- attribution$label
    entry$calls <- activity_emit_delegation_calls(
      agent = agent,
      state = state,
      record = record,
      view = view,
      entry = entry,
      runtime = runtime,
      root_call = attribution$root_call,
      settled = settled,
      closing = closing
    )
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

# A request's provider ID and tool, without its arguments.
activity_call_key <- function(request) {
  digest::digest(list(request@id, request@name), algo = "sha256")
}

# The keys of the requests in a delegation's own turns, as recorded. Used only
# to match calls to cards, never shown.
activity_record_keys <- function(record) {
  keys <- character()
  for (turn in activity_own_turns(record)) {
    for (content in turn@contents) {
      if (inherits(content, "ellmer::ContentToolRequest")) {
        keys <- c(keys, activity_call_key(content))
      }
    }
  }
  keys
}

# The shown card each call in the view is, NA for a call not shown yet.
# Identical calls (the same provider ID, tool and arguments) are told apart by
# what their cards show. A call still running, or one whose result no
# identical card has shown, takes the earliest card still waiting. Then a call
# whose result an identical card has shown takes a waiting card if one is
# left, and otherwise that card: when one of two identical calls is hidden,
# it is far likelier the earlier, finished one than a later one still running.
# Last, a call no card matches as shown, whose key is `unique` to it in the
# record and the view, takes the earliest card with that key: it is the same
# call, its arguments or result shown differently.
activity_call_slots <- function(
  known,
  calls,
  results,
  keys = rep(NA_character_, length(calls)),
  unique = logical(length(calls))
) {
  identities <- vapply(known, function(slot) slot$identity, character(1))
  slot_keys <- vapply(
    known,
    function(slot) slot$key %||% NA_character_,
    character(1)
  )
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
  for (position in which(is.na(slots) & unique)) {
    pick(position, !is.na(slot_keys) & slot_keys == keys[[position]])
  }
  slots
}
