#' @include delegation-inspection.R delegation-activity.R subagent-history-codec.R
NULL

# Subagent records saved with a shinychat conversation.
#
# shinychat calls `on_save(values)` with an empty list each time it saves the
# active conversation and stores what the callbacks return beside its turns;
# `on_restore(values)` gets them back when the conversation is opened again.
# The lead's own conversation, with its subagent tool cards
# (R/delegation-activity.R), is already in those turns. These callbacks add
# the settled subagent records of the same conversation: each child's outcome,
# transcript with its tool displays, usage and lineage, as
# `$export_subagents()` shapes them. Restored records are read-only evidence:
# nothing is run, resumed or handed to a model, and access is checked again
# whenever they are read.
#
# Stores may write `values` as JSON (shinychat's file store does), which loses
# R's types, and the saved text comes back from storage Deputy doesn't
# control. Records are therefore saved as one JSON string in a typed encoding
# of the portable data inspection already allows, decoded without evaluating
# anything, and checked like any other saved history.

host_conversation_id <- function(value) {
  if (is.null(value)) {
    return(NULL)
  }
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.null(attributes(value)) ||
      !nzchar(value) ||
      nchar(value, type = "bytes") > 256L
  ) {
    cli::cli_abort(
      "{.arg conversation_id} must be one non-empty string of at most 256 bytes, or NULL."
    )
  }
  value
}

# Records --------------------------------------------------------------------

# The scope saved records belong to: the lead's delegation scope and the
# shinychat conversation. Process identities (agent and session IDs) change on
# reload, so they are not part of it.
subagent_history_scope <- function(lead, conversation_id) {
  scope <- lead_delegation_scope(lead)
  scope$chat_conversation_id <- conversation_id
  scope
}

# Delegation records started while the lead answered in `conversation_id`. A
# descendant belongs to the conversation of its depth-one delegation.
subagent_history_records <- function(lead, conversation_id) {
  records <- lead_delegation_records(lead)
  names(records) <- vapply(
    records,
    function(record) record$delegation_id,
    character(1)
  )
  Filter(
    function(record) {
      root <- activity_root_record(records, record)
      !is.null(root) && identical(root$host_conversation_id, conversation_id)
    },
    records
  )
}

subagent_history_view_id <- function(view) {
  id <- view$outcome$runtime$delegation_id
  if (is.character(id) && length(id) == 1L && !is.na(id) && nzchar(id)) {
    id
  } else {
    NA_character_
  }
}

# One settled child, with its transcript when the disclosure bound allows it
# and the redactor leaves it.
subagent_history_child <- function(lead, requester, id) {
  view <- tryCatch(
    lead_inspect_subagents(lead, requester, id, TRUE, settled_only = TRUE),
    error = function(error) NULL
  )
  if (length(view)) {
    return(subagent_history_transcript_kept(view[[1L]]))
  }
  # A child whose outcome alone is over the disclosure bound is left out.
  view <- tryCatch(
    lead_inspect_subagents(lead, requester, id, FALSE),
    deputy_disclosure_bound = function(error) NULL
  )
  if (!length(view)) {
    return(NULL)
  }
  list(
    view = subagent_history_without_transcript(view[[1L]]),
    transcript = FALSE
  )
}

subagent_history_without_transcript <- function(view) {
  view$transcript <- NULL
  view$retention$transcript <- "omitted"
  view
}

# A redacted view as saved: a transcript the redactor removed is marked and
# counted as omitted, like one the save leaves out.
subagent_history_transcript_kept <- function(view) {
  if (is.null(view$transcript)) {
    return(list(
      view = subagent_history_without_transcript(view),
      transcript = FALSE
    ))
  }
  list(view = view, transcript = TRUE)
}

# A child's key in saved records: a digest of its delegation ID, so children
# can be matched across saves without storing an ID the redactor may remove.
subagent_history_key <- function(delegation_id) {
  digest::digest(delegation_id, algo = "sha256", serialize = FALSE)
}

subagent_history_record_size <- function(record) {
  nchar(history_json(record), type = "bytes")
}

# What a saved child costs against the lead's disclosure bound when it is
# replayed: its view as `delegation_history()` replays it, with every reference
# marked "unresolved", and its transcript again as replayed turns.
subagent_history_replay_size <- function(view) {
  view <- inspection_unresolved_references(view)
  length(serialize(list(view, view$transcript), NULL, version = 3))
}

subagent_history_left_out <- function(omitted, child) {
  if (isTRUE(child$carried)) {
    omitted$earlier <- omitted$earlier + 1L
  } else {
    omitted$children <- omitted$children + 1L
  }
  omitted
}

subagent_history_carry_prior <- function(
  state,
  conversation_id,
  scope,
  disclosure,
  requester,
  live_allowed,
  live
) {
  children <- list()
  earlier <- 0L
  waiting <- list(running = 0L, children = 0L)
  if (!identical(state$conversation_id, conversation_id)) {
    return(list(
      children = children,
      earlier = earlier,
      waiting = waiting,
      live = live
    ))
  }
  prior <- state$record
  # Saved children belong to the scope they were saved under. A lead moved
  # to another scope since (`set_delegation_sources(scope = )`) neither
  # carries them nor counts them, and this save replaces them.
  if (!identical(prior$history$scope, scope)) {
    prior <- NULL
  }
  carried <- prior$history$children %||% list()
  keys <- prior$keys %||% character()
  # Children the last save left out are counted again below while the lead
  # still has them; the rest are gone.
  pending <- prior$pending %||% character()
  if (!live_allowed) {
    # Unread, they wait for a save that may read them, counted as before.
    live <- pending
    waiting$running <- prior$omitted$running %||% 0L
    waiting$children <- (prior$omitted$children %||% 0L) -
      (prior$omitted$earlier %||% 0L)
  }
  earlier <- (prior$omitted$earlier %||% 0L) + sum(!pending %in% live)
  for (index in seq_along(carried)) {
    # Redacted as replay shows it: its references marked "unresolved".
    view <- inspection_redact(
      disclosure,
      inspection_unresolved_references(carried[[index]]),
      requester
    )
    child <- subagent_history_transcript_kept(view)
    child$carried <- TRUE
    children[[keys[[index]]]] <- child
  }
  list(children = children, earlier = earlier, waiting = waiting, live = live)
}

subagent_history_fit_children <- function(children, budget, bound, omitted) {
  kept <- list()
  for (key in names(children)) {
    child <- children[[key]]
    view <- child$view
    size <- nchar(history_json(view), type = "bytes")
    cost <- subagent_history_replay_size(view)
    if ((size > budget || cost > bound) && !is.null(view$transcript)) {
      view <- subagent_history_without_transcript(view)
      size <- nchar(history_json(view), type = "bytes")
      cost <- subagent_history_replay_size(view)
      child$transcript <- FALSE
    }
    if (size > budget || cost > bound) {
      omitted <- subagent_history_left_out(omitted, child)
      next
    }
    budget <- budget - size
    bound <- bound - cost
    kept[[key]] <- list(
      view = view,
      transcript = isTRUE(child$transcript),
      carried = isTRUE(child$carried)
    )
  }
  list(kept = kept, omitted = omitted)
}

subagent_history_trim_record <- function(
  kept,
  omitted,
  max_bytes,
  build_record
) {
  record <- build_record(kept, omitted)
  while (length(kept) && subagent_history_record_size(record) > max_bytes) {
    last <- length(kept)
    if (!is.null(kept[[last]]$view$transcript)) {
      kept[[last]]$view <- subagent_history_without_transcript(
        kept[[last]]$view
      )
      kept[[last]]$transcript <- FALSE
    } else {
      omitted <- subagent_history_left_out(omitted, kept[[last]])
      kept[[last]] <- NULL
    }
    record <- build_record(kept, omitted)
  }
  # A record that can't fit without children would not read back.
  if (subagent_history_record_size(record) > max_bytes) {
    cli::cli_abort(c(
      "Subagent records for this conversation can't be saved.",
      "x" = "Its scope alone is over {.arg max_bytes}."
    ))
  }
  record
}

# Assemble the conversation's record: children saved earlier in this
# conversation first, passed through the current redactor again, then live
# ones in the order they started, within `max_bytes` and within what the
# lead's disclosure lets `restored()` replay. A child that doesn't fit keeps
# its outcome without its transcript, or is left out; the record counts both.
# `pending` names (by key) the live children it left out, which a later save
# counts again from the lead's records while they are there. `earlier` counts
# children left out that can't be found again: pending children no longer
# among the lead's records (another session's, or released since), and saved
# children dropped now.
subagent_history_record <- function(state, conversation_id) {
  lead <- state$lead
  requester <- state$requester()
  disclosure <- lead_disclosure(lead)
  scope <- subagent_history_scope(lead, conversation_id)
  history_of <- function(children) {
    list(
      schema_version = 1L,
      settled = TRUE,
      scope = scope,
      children = children
    )
  }
  # What `delegation_history()` measures besides the children.
  bound <- disclosure$max_bytes -
    length(serialize(history_of(list()), NULL, version = 3))
  if (bound < 0) {
    cli::cli_abort(c(
      "Subagent records for this conversation can't be saved.",
      "x" = "Its scope alone is over the lead's disclosure {.arg max_bytes}."
    ))
  }
  # The record is this conversation's history: only a requester who may read
  # it there writes it, even through the redactor.
  inspection_authorize(disclosure, requester, scope)
  # Live records are read only under the lead's live scope as well, asked
  # before they are looked up. A requester it doesn't allow saves what the
  # record already holds, the same whether or not the lead has subagents
  # here, as a reopened conversation whose lead has none saves without them.
  live_allowed <- inspection_is_authorized(
    disclosure,
    requester,
    inspection_scope(lead)
  )
  records <- if (live_allowed) {
    subagent_history_records(lead, conversation_id)
  } else {
    list()
  }
  live <- vapply(
    records,
    function(record) subagent_history_key(record$delegation_id),
    character(1),
    USE.NAMES = FALSE
  )
  prior <- subagent_history_carry_prior(
    state,
    conversation_id,
    scope,
    disclosure,
    requester,
    live_allowed,
    live
  )
  children <- prior$children
  live <- prior$live
  omitted <- list(
    running = prior$waiting$running,
    transcripts = 0L,
    children = prior$waiting$children,
    earlier = prior$earlier
  )
  for (record in records) {
    key <- subagent_history_key(record$delegation_id)
    # A live child replaces its saved copy, whether it is saved again now or
    # left out (and counted once, as pending): this lead can find it again.
    if (
      is.na(record$completed_at) ||
        !isTRUE(record$status %in% delegation_settled_statuses)
    ) {
      children[[key]] <- NULL
      omitted$running <- omitted$running + 1L
      next
    }
    child <- subagent_history_child(lead, requester, record$delegation_id)
    children[[key]] <- child
    if (is.null(child)) {
      omitted$children <- omitted$children + 1L
    }
  }
  fitted <- subagent_history_fit_children(
    children,
    state$max_bytes,
    bound,
    omitted
  )
  build <- function(kept, omitted) {
    transcripts <- sum(
      !vapply(
        kept,
        function(child) child$transcript,
        logical(1)
      )
    )
    list(
      conversation_id = conversation_id,
      history = history_of(unname(lapply(kept, function(child) child$view))),
      keys = names(kept) %||% character(),
      pending = setdiff(live, names(kept)),
      omitted = list(
        running = omitted$running,
        transcripts = transcripts,
        children = omitted$children + omitted$earlier,
        earlier = omitted$earlier
      )
    )
  }
  # The scope, keys and counts count too: until the whole record fits, the
  # newest child loses its transcript, and if that isn't enough, is dropped.
  subagent_history_trim_record(
    fitted$kept,
    fitted$omitted,
    state$max_bytes,
    build
  )
}

# Callbacks ------------------------------------------------------------------

# The open conversation's ID: shinychat's, given its chat, otherwise the one
# the host reports.
subagent_history_active_id <- function(state) {
  if (!is.null(state$chat)) {
    return(shiny::isolate(state$chat$history$conversation_id()))
  }
  host_conversation_id(shiny::isolate(state$open_id()))
}

subagent_history_save <- function(state, values) {
  id <- tryCatch(subagent_history_active_id(state), error = function(e) NULL)
  if (is.null(id)) {
    return(values)
  }
  if (identical(state$conversation_id, id) && !is.null(state$kept)) {
    values$deputy_subagents <- state$kept
    return(values)
  }
  previous <- if (identical(state$conversation_id, id)) state$envelope
  saved <- tryCatch(
    {
      if (!is.null(state$chat) && !identical(state$chat$client, state$lead)) {
        cli::cli_abort("The chat no longer runs this lead.")
      }
      record <- subagent_history_record(state, id)
      envelope <- subagent_history_envelope(record)
      state$record <- record
      state$envelope <- envelope
      state$kept <- NULL
      state$conversation_id <- id
      state$error <- NULL
      state$error_scope <- NULL
      envelope
    },
    error = function(error) {
      # A save shinychat can't complete loses the conversation, so keep the
      # last good record for it instead. A conversation saved for the first
      # time has none, but the error is still about it, not about the one
      # saved before.
      if (!identical(state$conversation_id, id)) {
        state$conversation_id <- id
        state$record <- NULL
        state$envelope <- NULL
        state$kept <- NULL
      }
      state$error <- inspection_text(conditionMessage(error), 1024L)
      # The message may hold a redactor's own text, so it is reported only
      # under the scope it was made in.
      state$error_scope <- tryCatch(
        subagent_history_scope(state$lead, id),
        error = function(error) NULL
      )
      previous
    }
  )
  values$deputy_subagents <- saved
  values
}

# A record from a newer format is saved again unchanged rather than replaced.
subagent_history_newer <- function(saved) {
  version <- if (is.list(saved)) saved$version
  if (is.list(version) && length(version) == 1L) {
    version <- version[[1L]]
  }
  format <- if (is.list(saved)) unlist(saved$format)
  identical(format, subagent_history_format) &&
    is.numeric(version) &&
    length(version) == 1L &&
    isTRUE(version > subagent_history_version)
}

subagent_history_restore <- function(state, values) {
  id <- tryCatch(subagent_history_active_id(state), error = function(e) NULL)
  state$conversation_id <- id
  state$record <- NULL
  state$envelope <- NULL
  state$kept <- NULL
  state$error <- NULL
  state$error_scope <- NULL
  saved <- values$deputy_subagents
  if (is.null(saved) || is.null(id)) {
    return(invisible(NULL))
  }
  state$error_scope <- subagent_history_scope(state$lead, id)
  if (subagent_history_newer(saved)) {
    state$kept <- saved
    state$error <- paste(
      "Saved subagent records for this conversation come from a newer",
      "version of deputy. They are kept unchanged, and new subagents are not",
      "added to them."
    )
    return(invisible(NULL))
  }
  tryCatch(
    {
      state$record <- subagent_history_read(
        saved,
        state$lead,
        id,
        state$max_bytes
      )
      state$envelope <- subagent_history_envelope(state$record)
    },
    error = function(error) {
      state$error <- "Saved subagent records for this conversation could not be read."
    }
  )
  invisible(NULL)
}

subagent_history_restored <- function(
  state,
  transcript = TRUE,
  delegation_id = NULL
) {
  if (
    !is.logical(transcript) || length(transcript) != 1L || is.na(transcript)
  ) {
    cli::cli_abort("{.arg transcript} must be TRUE or FALSE.")
  }
  if (!is.null(delegation_id) && !is_nonempty_string(delegation_id)) {
    cli::cli_abort("{.arg delegation_id} must be one delegation ID, or NULL.")
  }
  id <- subagent_history_active_id(state)
  if (
    is.null(id) ||
      !identical(state$conversation_id, id) ||
      is.null(state$record)
  ) {
    return(NULL)
  }
  history <- state$record$history
  if (!is.null(delegation_id)) {
    # One subagent is read and bounded on its own, so the others' transcripts
    # can't push it over the disclosure bound.
    history$children <- Filter(
      function(view) identical(subagent_history_view_id(view), delegation_id),
      history$children
    )
  }
  if (!transcript) {
    # Left out on request, as inspection marks it; a transcript the save
    # itself omitted stays marked "omitted".
    history$children <- lapply(history$children, function(view) {
      if (!identical(view$retention$transcript, "omitted")) {
        view$retention$transcript <- "not_requested"
      }
      view$transcript <- NULL
      view
    })
  }
  replay <- function(history) {
    delegation_history(
      history,
      state$requester(),
      lead_disclosure(state$lead),
      subagent_history_scope(state$lead, id)
    )
  }
  views <- tryCatch(replay(history), deputy_disclosure_bound = function(error) {
    # Saved under a larger bound than the lead's disclosure now allows: the
    # outcomes are still shown, without their transcripts, as many as fit.
    # Only transcripts still there are dropped; a child listed without its
    # transcript on request stays marked "not_requested".
    children <- lapply(history$children, function(view) {
      if (is.null(view$transcript)) {
        view
      } else {
        subagent_history_without_transcript(view)
      }
    })
    first <- function(n) {
      history$children <- children[seq_len(n)]
      tryCatch(replay(history), deputy_disclosure_bound = function(error) {
        NULL
      })
    }
    bisect_max_fitting(length(children), first, empty = list())$value
  })
  # A transcript the current redactor removes is marked as the save marks
  # one: left out, not included.
  lapply(views, function(view) {
    if (
      is.null(view$transcript) &&
        identical(view$retention$transcript, "included")
    ) {
      view$retention$transcript <- "omitted"
    }
    view
  })
}

subagent_history_status <- function(state) {
  id <- subagent_history_active_id(state)
  current <- !is.null(id) && identical(state$conversation_id, id)
  scope <- if (current) subagent_history_scope(state$lead, id)
  # The counts and any problem are about the conversation's saved subagents,
  # so they are read only for a requester its scope allows, as `restored()`
  # reads the record itself.
  allowed <- !current ||
    inspection_is_authorized(
      lead_disclosure(state$lead),
      state$requester(),
      scope
    )
  # A record saved under another scope (the lead has moved since) isn't
  # counted: `restored()` refuses it, and the next save replaces it.
  record <- if (
    current && allowed && identical(state$record$history$scope, scope)
  ) {
    state$record
  }
  counts <- record$omitted
  list(
    conversation_id = id,
    saved = length(record$history$children),
    omitted = list(
      running = counts$running %||% 0L,
      transcripts = counts$transcripts %||% 0L,
      children = counts$children %||% 0L
    ),
    error = if (!allowed) {
      "This conversation's saved subagents are not available to this user."
    } else if (current && identical(state$error_scope, scope)) {
      # A problem met under another scope (the lead has moved since) isn't
      # this one's to report.
      state$error
    }
  )
}

# A saved record's counts: whole, non-negative, `earlier` within `children`,
# and one pending child for each running or live child left out.
subagent_history_counts <- function(counts, pending) {
  count <- function(value) {
    is.integer(value) && length(value) == 1L && !is.na(value) && value >= 0L
  }
  is.list(counts) &&
    all(vapply(
      c("running", "transcripts", "children", "earlier"),
      function(name) count(counts[[name]]),
      logical(1)
    )) &&
    counts$earlier <= counts$children &&
    identical(
      length(pending),
      counts$running + counts$children - counts$earlier
    )
}

# The subagent panel's list for the open conversation: live subagents that
# ran in it, then saved ones that aren't live. `live` comes from
# `subagent_history_live_views()`, which picks them by their records, since a
# redactor may leave the conversation out of the views.
subagent_history_panel_views <- function(conversation, live, disclosure) {
  if (is.null(conversation)) {
    return(live)
  }
  live_ids <- vapply(live, subagent_history_view_id, character(1))
  restored <- Filter(
    function(view) !subagent_history_view_id(view) %in% live_ids,
    subagent_history_panel_saved(conversation, transcript = FALSE)
  )
  # Each list keeps to the disclosure bound on its own. Together they keep to
  # it too: every live subagent, and as many saved ones, oldest first, as fit
  # beside them, found by bisection since fewer only make the list smaller.
  fits <- function(n) {
    tryCatch(
      {
        inspection_bound(c(restored[seq_len(n)], live), disclosure)
        TRUE
      },
      deputy_disclosure_bound = function(error) FALSE
    )
  }
  kept <- bisect_max_fitting(length(restored), fits)$count
  c(restored[seq_len(kept)], live)
}

# Saved subagents are authorized on their own: a requester the disclosure
# refuses them still sees the live ones, with no saved ones beside them.
subagent_history_panel_saved <- function(
  conversation,
  transcript = TRUE,
  delegation_id = NULL
) {
  tryCatch(
    conversation$restored(
      transcript = transcript,
      delegation_id = delegation_id
    ) %||%
      list(),
    deputy_delegation_disclosure = function(error) list()
  )
}

# The open conversation's live subagents as `$inspect_subagents()` shows
# them, reading and bounding only the records that ran in it, so other
# conversations' subagents can't push its list over the disclosure bound.
subagent_history_live_views <- function(conversation, lead, requester) {
  disclosure <- lead_disclosure(lead)
  inspection_authorize(disclosure, requester, inspection_scope(lead))
  id <- conversation$conversation_id()
  if (is.null(id)) {
    return(list())
  }
  ids <- vapply(
    subagent_history_records(lead, id),
    function(record) record$delegation_id,
    character(1),
    USE.NAMES = FALSE
  )
  records <- Filter(
    function(record) record$delegation_id %in% ids,
    lead_delegation_records(lead, usage = TRUE)
  )
  views <- lapply(records, function(record) {
    inspection_redact(
      disclosure,
      lead_inspection_view(lead, record, FALSE),
      requester
    )
  })
  inspection_bound(views, disclosure)
}

# The observation cursor now, read without building any subagent's view.
subagent_history_cursor <- function(lead, requester) {
  reader <- lead$observe_subagents(requester)
  tryCatch(reader$poll()$cursor, finally = reader$close())
}

# One child for the panel to show: live if its record says it ran in the open
# conversation (a redactor may leave that out of the view), otherwise saved
# with it.
subagent_history_panel_child <- function(conversation, lead, live, id) {
  if (is.null(conversation)) {
    return(live)
  }
  # The lead's records are read only behind a live view the requester was
  # allowed; without one, only the saved child can be shown.
  if (length(live)) {
    open <- conversation$conversation_id()
    ran_here <- !is.null(open) &&
      id %in%
        vapply(
          subagent_history_records(lead, open),
          function(record) record$delegation_id,
          character(1)
        )
    if (ran_here) {
      return(live)
    }
  }
  Filter(
    function(view) identical(subagent_history_view_id(view), id),
    subagent_history_panel_saved(conversation, delegation_id = id)
  )
}

#' Save subagent records with a shinychat conversation
#'
#' Keeps the subagents of each conversation in a shinychat chat with that
#' conversation, so reopening it, after a reload or in a new session, brings
#' back what each subagent did: its task, outcome, conversation with tool
#' results and their cards, usage, and where it sat among the other
#' subagents. The records come back read-only. Nothing is run again, no
#' subagent is resumed, and the lead's model doesn't see them; it keeps the
#' short summary each subagent returned. Show them in the subagent panel by
#' passing the returned value to [subagent_chat_server()] as `conversation`,
#' or read them with `restored()`.
#'
#' Records are saved through the chat's history callbacks each time shinychat
#' saves the conversation, as one JSON text, so any history store can hold
#' them. A subagent still running at that point is saved the next time. Access
#' is checked with the lead's [DelegationDisclosure] when records are saved
#' and every time they are read. A save adds the lead's subagents only when
#' `requester` may also inspect them on the lead; otherwise it keeps the ones
#' saved before. When reading them back, `authorize` gets a `scope` holding
#' the lead's `delegation_scope` and the conversation's ID as
#' `chat_conversation_id`; records saved under another scope are not read.
#' Large results that subagents saved to disk are kept as references, which
#' may no longer resolve. Needs shiny and shinychat (>= 0.5.0) with history
#' enabled.
#'
#' @section Apps that run the lead's replies themselves:
#' If your app streams the lead's replies into the chat itself instead of
#' using [shinychat::chat_server()], and keeps conversations with
#' [shinychat::chat_enable_history()], leave out `chat`. The returned list then
#' also holds `on_save` and `on_restore`: pass them to `chat_enable_history()`.
#' If you already have your own `on_save`, call this one from inside it and
#' return what it returns; do the same with `on_restore`.
#'
#' Records are kept under the ID of the conversation open in the chat, which
#' `chat_server()` otherwise looks after. Before each reply, set
#' `lead$conversation_id` to the ID of the conversation the reply belongs to,
#' as `chat_server()` does, so the subagents it starts are saved with that
#' conversation. shinychat's "new chat" empties the lead's conversation, which
#' sets `lead$conversation_id` back to `NULL`, so the previous conversation's
#' subagents stop showing until you set the next ID. If you pass your own
#' `conversation_id` function, make it return `NULL` or the new ID after a new
#' chat. shinychat also empties the lead when the first message of a
#' conversation is edited, and from the lead the two look the same: the
#' example below gives such an edit a new ID, so the subagents from before the
#' edit are no longer saved with that conversation. When a conversation is
#' reopened, its ID must be the open one
#' before `on_restore` runs: records saved under another ID are not read. By
#' default the open conversation's ID is read from `lead$conversation_id`;
#' pass `conversation_id` to read it from somewhere else. For example, keeping
#' the ID with the conversation itself:
#'
#' ```r
#' saved <- subagent_chat_history(lead = lead, requester = user)
#' shinychat::chat_enable_history(
#'   "chat",
#'   lead,
#'   on_save = function(values) {
#'     values$conversation <- lead$conversation_id
#'     saved$on_save(values)
#'   },
#'   on_restore = function(values) {
#'     lead$conversation_id <- values$conversation
#'     saved$on_restore(values)
#'   }
#' )
#' shiny::observeEvent(input$chat_user_input, {
#'   if (length(lead$get_turns()) == 0) {
#'     lead$conversation_id <- new_conversation_id() # your own ID scheme
#'   }
#'   stream <- lead$stream_async(input$chat_user_input, stream = "content")
#'   shinychat::chat_append("chat", stream)
#' })
#' ```
#'
#' @param chat The value returned by [shinychat::chat_server()] for the lead's
#'   chat, or `NULL` (the default) when your app runs the lead's replies
#'   itself.
#' @param lead The [Agent] or [LeadAgent] given to `chat_server()` as its
#'   client, or whose replies your app streams into the chat.
#' @param requester A function returning the current user, as your
#'   [DelegationDisclosure] expects it.
#' @param max_bytes Most bytes of records to save per conversation. Children
#'   that don't fit, here or in the `max_bytes` of the lead's
#'   `delegation_disclosure`, keep their outcome without their conversation,
#'   or are left out, and `status()` counts them. Defaults to 16 MiB.
#' @param conversation_id Only without `chat`: a function returning the ID of
#'   the conversation open in the chat, or `NULL` when none is. Defaults to
#'   reading `lead$conversation_id`.
#' @return Invisibly, a list of functions:
#'   * `restored(transcript = TRUE, delegation_id = NULL)`: the subagents
#'     saved with the open conversation, as [delegation_history()] returns
#'     them, or `NULL`. With `transcript = FALSE`, without their
#'     conversations, each marked `retention$transcript = "not_requested"` (or
#'     `"omitted"` when it wasn't saved). With `delegation_id`, only that
#'     saved subagent, whose conversation is kept if it fits the disclosure's
#'     `max_bytes` on its own.
#'   * `status()`: the open conversation's ID, how many subagents its saved
#'     record holds, how many were still running, saved without their
#'     conversation (too large, or removed by the disclosure's `redact`) or
#'     left out at the last save (including subagents left out earlier that
#'     can't be found again, such as an earlier session's or those released
#'     since), and any problem saving or reading it. A user the lead's
#'     `delegation_disclosure` doesn't let see them gets no counts, and a note
#'     saying so.
#'   * `conversation_id()`: the open conversation's ID, or `NULL`.
#'   * Without `chat`, also `on_save(values)` and `on_restore(values)`, the
#'     callbacks for [shinychat::chat_enable_history()]. `on_save` returns
#'     `values` with the conversation's records added.
#' @seealso [subagent_chat_activity()] to show subagent tool calls in the
#'   chat itself.
#' @export
subagent_chat_history <- function(
  chat = NULL,
  lead,
  requester,
  max_bytes = 16 * 1024^2,
  conversation_id = NULL
) {
  if (missing(lead)) {
    lead <- NULL
  }
  if (!is.null(chat) && !is.null(conversation_id)) {
    cli::cli_abort(c(
      "Give {.arg chat} or {.arg conversation_id}, not both.",
      "i" = "With {.arg chat}, the open conversation's ID comes from its history."
    ))
  }
  subagent_chat_check_lead(
    chat,
    lead,
    c("on_save", "on_restore", "conversation_id")
  )
  if (!is.function(requester)) {
    cli::cli_abort("{.arg requester} must be a function.")
  }
  if (!is.null(conversation_id) && !is.function(conversation_id)) {
    cli::cli_abort(
      "{.arg conversation_id} must be a function returning the open conversation's ID."
    )
  }
  max_bytes <- validate_positive_int(max_bytes, "max_bytes")
  if (is.null(max_bytes) || max_bytes < 1024) {
    cli::cli_abort("{.arg max_bytes} must be at least 1024.")
  }
  state <- new.env(parent = emptyenv())
  state$chat <- chat
  state$open_id <- conversation_id %||% function() lead$conversation_id
  state$lead <- lead
  state$requester <- requester
  state$max_bytes <- as.double(max_bytes)
  state$conversation_id <- NULL
  state$record <- NULL
  state$envelope <- NULL
  state$kept <- NULL
  state$error <- NULL
  state$error_scope <- NULL
  on_save <- function(values) subagent_history_save(state, values)
  on_restore <- function(values) subagent_history_restore(state, values)
  result <- list(
    restored = function(transcript = TRUE, delegation_id = NULL) {
      subagent_history_restored(state, transcript, delegation_id)
    },
    status = function() subagent_history_status(state),
    conversation_id = function() subagent_history_active_id(state)
  )
  if (is.null(chat)) {
    # The host registers these with `chat_enable_history()` itself: shinychat
    # keeps that history's callbacks where Deputy can't reach them.
    result$on_save <- on_save
    result$on_restore <- on_restore
  } else {
    chat$history$on_save(on_save)
    chat$history$on_restore(on_restore)
  }
  invisible(result)
}
