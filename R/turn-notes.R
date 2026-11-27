# Notes a host attaches to turns of the selected conversation.
#
# A note is content the host adds to a turn after it was recorded, such as a
# label saying whether an answer's citations were found in its sources. Like
# shown subagent activity (R/delegation-activity.R), notes are part of the
# conversation `get_turns()` returns, so shinychat records and replays them
# with its history, but never part of the model context: the Agent keeps
# them beside the turns, by each turn's position in the complete
# conversation. Deputy can't recognize a host's notes by itself, so the
# Agent's `notes` function says which contents are notes, and `set_turns()`
# and `add_turn()` take them out of turns a host supplies again.

check_note_filter <- function(notes, call = rlang::caller_env()) {
  if (!is.null(notes) && !is.function(notes)) {
    cli_abort(
      "{.arg notes} must be a function or {.code NULL}.",
      call = call
    )
  }
  invisible(notes)
}

# A filter that fails or answers anything but TRUE doesn't make a note, so a
# restored conversation never fails on a host's filter.
is_note_content <- function(filter, content) {
  !is.null(filter) &&
    inherits(content, "ellmer::Content") &&
    isTRUE(tryCatch(filter(content), error = function(e) FALSE))
}

note_split <- function(turns, filter) {
  if (is.null(filter)) {
    return(list(turns = turns, overlay = list()))
  }
  overlay_split(turns, function(content) is_note_content(filter, content))
}

# Contents kept beside the turns, by turn position: shown activity and notes.
overlay_split <- function(turns, marked) {
  overlay <- list()
  for (index in seq_along(turns)) {
    turn <- turns[[index]]
    if (!inherits(turn, "ellmer::Turn")) {
      next
    }
    contents <- turn@contents
    is_marked <- vapply(contents, marked, logical(1))
    if (!any(is_marked)) {
      next
    }
    for (content in contents[is_marked]) {
      overlay[[length(overlay) + 1L]] <- list(turn = index, content = content)
    }
    turn@contents <- contents[!is_marked]
    turns[[index]] <- turn
  }
  list(turns = turns, overlay = overlay)
}

overlay_merge <- function(turns, overlay) {
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

# One turn of the complete conversation, at `position`, with any overlay
# entries belonging to it.
overlay_merge_turn <- function(turn, position, overlay) {
  for (entry in overlay) {
    if (isTRUE(entry$turn == position)) {
      turn@contents <- c(turn@contents, list(entry$content))
    }
  }
  turn
}

# Overlay entries are keyed by their turn's position in the complete
# conversation: the compacted prefix (`offset` turns), then the context. When
# moving to another Chat drops context turns, each entry moves to where its
# turn now sits.
overlay_remap <- function(overlay, kept, offset) {
  overlay <- lapply(overlay, function(entry) {
    if (entry$turn > offset) {
      entry$turn <- offset + match(entry$turn - offset, kept)
    }
    entry
  })
  Filter(function(entry) !is.na(entry$turn), overlay)
}

# Contents kept beside the turns, as a saved session keeps them: each with the
# index of its turn. A conversation with none has no field.
overlay_session_entries <- function(overlay) {
  if (!length(overlay)) {
    return(NULL)
  }
  lapply(overlay, function(entry) {
    list(turn = as.integer(entry$turn), content = entry$content)
  })
}

# The notes of a saved session. A session lists its notes apart from its
# turns, so loading them needs no `notes` function.
note_session_overlay <- function(session, path = NULL) {
  overlay_session_overlay(
    session,
    field = "notes",
    accepts = function(content) inherits(content, "ellmer::Content"),
    malformed = "Invalid session file - its notes are malformed",
    path = path
  )
}

# Saved overlay entries, checked against the turns they are loaded with: each
# entry an accepted content on one of the conversation's turns.
overlay_session_overlay <- function(session, field, accepts, malformed, path) {
  entries <- if (is.list(session)) session[[field]]
  if (is.null(entries)) {
    return(list())
  }
  turns <- if (is.list(session$turns) && is.list(session$compacted_turns)) {
    c(session$compacted_turns, session$turns)
  } else {
    list()
  }
  valid <- function(entry) {
    turn <- if (is.list(entry) && !is.object(entry)) entry$turn
    is.numeric(turn) &&
      !is.object(turn) &&
      length(turn) == 1L &&
      !is.na(turn) &&
      turn >= 1 &&
      turn <= length(turns) &&
      turn == round(turn) &&
      inherits(turns[[turn]], "ellmer::Turn") &&
      isTRUE(accepts(entry$content))
  }
  if (
    !is.list(entries) ||
      is.object(entries) ||
      !all(vapply(entries, valid, logical(1)))
  ) {
    abort_session_load(malformed, path = path)
  }
  lapply(entries, function(entry) {
    list(turn = as.integer(entry$turn), content = entry$content)
  })
}
