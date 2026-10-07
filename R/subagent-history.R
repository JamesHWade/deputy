#' @include delegation-inspection.R delegation-activity.R
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

subagent_history_format <- "deputy_conversation_subagents"
subagent_history_version <- 1L
subagent_history_codec <- "deputy_portable_json"

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

# Encoding ----------------------------------------------------------------

history_codec_abort <- function() {
  cli::cli_abort("Saved subagent records are not in a readable form.")
}

history_encode_double <- function(value) {
  if (is.nan(value)) {
    return("NaN")
  }
  if (is.na(value)) {
    return(NULL)
  }
  if (is.infinite(value)) {
    return(if (value > 0) "Inf" else "-Inf")
  }
  sprintf("%.17g", value)
}

history_encode <- function(x, depth = 0L) {
  if (depth > 64L) {
    history_codec_abort()
  }
  if (is.null(x)) {
    return(list(t = "null"))
  }
  if (
    is.object(x) ||
      !all(names(attributes(x)) %in% c("names", "dim", "dimnames"))
  ) {
    history_codec_abort()
  }
  values <- unname(x)
  attributes(values) <- NULL
  text <- function(value) if (is.na(value)) NULL else enc2utf8(value)
  node <- if (is.list(x)) {
    list(t = "list", v = lapply(values, history_encode, depth = depth + 1L))
  } else if (is.logical(x)) {
    list(
      t = "lgl",
      v = lapply(values, function(value) {
        if (is.na(value)) NULL else value
      })
    )
  } else if (is.integer(x)) {
    list(
      t = "int",
      v = lapply(values, function(value) {
        if (is.na(value)) NULL else format(value, scientific = FALSE)
      })
    )
  } else if (is.double(x)) {
    list(t = "dbl", v = lapply(values, history_encode_double))
  } else if (is.character(x)) {
    list(t = "chr", v = lapply(values, text))
  } else if (is.raw(x)) {
    list(t = "raw", v = list(gsub("\n", "", jsonlite::base64_enc(values))))
  } else if (is.complex(x)) {
    list(
      t = "cplx",
      v = lapply(values, function(value) {
        list(history_encode_double(Re(value)), history_encode_double(Im(value)))
      })
    )
  } else {
    history_codec_abort()
  }
  if (!is.null(names(x)) && is.null(dim(x))) {
    node$n <- lapply(names(x), text)
  }
  if (!is.null(dim(x))) {
    node$d <- lapply(dim(x), format, scientific = FALSE)
    if (!is.null(dimnames(x))) {
      node$dn <- history_encode(dimnames(x), depth + 1L)
    }
  }
  node
}

history_json <- function(x) {
  as.character(jsonlite::toJSON(
    history_encode(x),
    auto_unbox = TRUE,
    null = "null",
    na = "null"
  ))
}

history_decode_number <- function(value, integer) {
  if (is.null(value)) {
    return(if (integer) NA_integer_ else NA_real_)
  }
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    history_codec_abort()
  }
  if (integer) {
    if (!grepl("^-?[0-9]{1,10}$", value)) {
      history_codec_abort()
    }
    number <- as.numeric(value)
    if (abs(number) > .Machine$integer.max) {
      history_codec_abort()
    }
    return(as.integer(number))
  }
  if (identical(value, "NaN")) {
    return(NaN)
  }
  if (identical(value, "Inf")) {
    return(Inf)
  }
  if (identical(value, "-Inf")) {
    return(-Inf)
  }
  if (
    !grepl(
      "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][-+]?[0-9]{1,3})?$",
      value
    )
  ) {
    history_codec_abort()
  }
  as.numeric(value)
}

history_decode_text <- function(value) {
  if (is.null(value)) {
    return(NA_character_)
  }
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    history_codec_abort()
  }
  value
}

history_decode_raw <- function(values) {
  if (
    length(values) != 1L ||
      !is.character(values[[1L]]) ||
      length(values[[1L]]) != 1L ||
      !grepl("^[A-Za-z0-9+/]*={0,2}$", values[[1L]]) ||
      nchar(values[[1L]]) %% 4L != 0L
  ) {
    history_codec_abort()
  }
  jsonlite::base64_dec(values[[1L]])
}

history_decode <- function(node, depth = 0L) {
  if (
    depth > 64L ||
      !is.list(node) ||
      is.null(names(node)) ||
      anyDuplicated(names(node)) ||
      !all(names(node) %in% c("t", "v", "n", "d", "dn")) ||
      !is.character(node$t) ||
      length(node$t) != 1L
  ) {
    history_codec_abort()
  }
  if (identical(node$t, "null")) {
    if (length(node) != 1L) {
      history_codec_abort()
    }
    return(NULL)
  }
  values <- node$v
  if (!is.list(values) || !is.null(names(values))) {
    history_codec_abort()
  }
  x <- switch(
    node$t,
    list = lapply(values, history_decode, depth = depth + 1L),
    lgl = vapply(
      values,
      function(value) {
        if (is.null(value)) {
          return(NA)
        }
        if (!is.logical(value) || length(value) != 1L || is.na(value)) {
          history_codec_abort()
        }
        value
      },
      logical(1)
    ),
    int = vapply(values, history_decode_number, integer(1), integer = TRUE),
    dbl = vapply(values, history_decode_number, double(1), integer = FALSE),
    chr = vapply(values, history_decode_text, character(1)),
    raw = history_decode_raw(values),
    cplx = vapply(
      values,
      function(value) {
        if (!is.list(value) || length(value) != 2L || !is.null(names(value))) {
          history_codec_abort()
        }
        complex(
          real = history_decode_number(value[[1L]], integer = FALSE),
          imaginary = history_decode_number(value[[2L]], integer = FALSE)
        )
      },
      complex(1)
    ),
    history_codec_abort()
  )
  if (!is.null(node$n)) {
    if (!is.null(node$d) || !is.list(node$n) || length(node$n) != length(x)) {
      history_codec_abort()
    }
    names(x) <- vapply(node$n, history_decode_text, character(1))
  }
  if (!is.null(node$d)) {
    if (!is.list(node$d) || !length(node$d)) {
      history_codec_abort()
    }
    dims <- vapply(node$d, history_decode_number, integer(1), integer = TRUE)
    if (anyNA(dims) || any(dims < 0L) || prod(dims) != length(x)) {
      history_codec_abort()
    }
    dim(x) <- dims
    if (!is.null(node$dn)) {
      dimnames <- history_decode(node$dn, depth + 1L)
      if (!is.list(dimnames) || length(dimnames) != length(dims)) {
        history_codec_abort()
      }
      dimnames(x) <- dimnames
    }
  } else if (!is.null(node$dn)) {
    history_codec_abort()
  }
  x
}

history_parse <- function(text) {
  history_decode(jsonlite::parse_json(text, simplifyVector = FALSE))
}

# Records --------------------------------------------------------------------

# The scope saved records belong to: the lead's delegation scope and the
# shinychat conversation. Process identities (agent and session IDs) change on
# reload, so they are not part of it.
subagent_history_scope <- function(lead, conversation_id) {
  scope <- lead$.__enclos_env__$private$delegation_scope
  scope$chat_conversation_id <- conversation_id
  scope
}

subagent_history_settled <- c(
  "completed",
  "failed",
  "stopped",
  "not_started",
  "suspended"
)

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
# replayed: its view, and its transcript again as replayed turns.
subagent_history_replay_size <- function(view) {
  length(serialize(list(view, view$transcript), NULL, version = 3))
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
  disclosure <- lead$.__enclos_env__$private$.delegation_disclosure
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
  # it there writes it, even through the redactor. Live records are read
  # under the lead's live scope as well, so a reopened conversation whose
  # lead has none here saves without it.
  inspection_authorize(disclosure, requester, scope)
  records <- subagent_history_records(lead, conversation_id)
  if (length(records)) {
    inspection_authorize(disclosure, requester, inspection_scope(lead))
  }
  live <- vapply(
    records,
    function(record) subagent_history_key(record$delegation_id),
    character(1),
    USE.NAMES = FALSE
  )
  children <- list()
  earlier <- 0L
  if (identical(state$conversation_id, conversation_id)) {
    prior <- state$record
    # Saved children belong to the scope they were saved under. A lead moved
    # to another scope since (`set_delegation_sources(scope = )`) neither
    # carries them nor counts them, and this save replaces them.
    if (!identical(prior$history$scope, scope)) {
      prior <- NULL
    }
    carried <- prior$history$children %||% list()
    keys <- prior$keys %||% character()
    # Children the last save left out are counted again below while the
    # lead still has them; the rest are gone.
    pending <- prior$pending %||% character()
    earlier <- (prior$omitted$earlier %||% 0L) + sum(!pending %in% live)
    for (index in seq_along(carried)) {
      view <- disclosure$redact(carried[[index]], requester)
      if (!is.list(view)) {
        cli::cli_abort("Disclosure redaction must return a list.")
      }
      inspection_portable(view)
      child <- subagent_history_transcript_kept(view)
      child$carried <- TRUE
      children[[keys[[index]]]] <- child
    }
  }
  omitted <- list(
    running = 0L,
    transcripts = 0L,
    children = 0L,
    earlier = earlier
  )
  left_out <- function(omitted, child) {
    if (isTRUE(child$carried)) {
      omitted$earlier <- omitted$earlier + 1L
    } else {
      omitted$children <- omitted$children + 1L
    }
    omitted
  }
  for (record in records) {
    key <- subagent_history_key(record$delegation_id)
    # A live child replaces its saved copy, whether it is saved again now or
    # left out (and counted once, as pending): this lead can find it again.
    if (
      is.na(record$completed_at) ||
        !isTRUE(record$status %in% subagent_history_settled)
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
  budget <- state$max_bytes
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
      omitted <- left_out(omitted, child)
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
  build <- function(kept) {
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
  # The scope, keys and counts count too: drop the newest children until the
  # whole record fits.
  record <- build(kept)
  while (
    length(kept) && subagent_history_record_size(record) > state$max_bytes
  ) {
    omitted <- left_out(omitted, kept[[length(kept)]])
    kept[[length(kept)]] <- NULL
    record <- build(kept)
  }
  # A record that can't fit without children would not read back.
  if (subagent_history_record_size(record) > state$max_bytes) {
    cli::cli_abort(c(
      "Subagent records for this conversation can't be saved.",
      "x" = "Its scope alone is over {.arg max_bytes}."
    ))
  }
  record
}

subagent_history_envelope <- function(record) {
  list(
    format = subagent_history_format,
    version = subagent_history_version,
    codec = subagent_history_codec,
    conversation_id = record$conversation_id,
    data = history_json(record)
  )
}

# Check saved values before anything reads them: the envelope, the decoded
# record, its scope and every transcript.
subagent_history_read <- function(saved, lead, conversation_id, max_bytes) {
  scalar <- function(value) {
    if (is.list(value) && length(value) == 1L) value[[1L]] else value
  }
  text <- function(value) {
    value <- scalar(value)
    is.character(value) && length(value) == 1L && !is.na(value)
  }
  if (!is.list(saved)) {
    history_codec_abort()
  }
  version <- scalar(saved$version)
  if (
    !identical(scalar(saved$format), subagent_history_format) ||
      !is.numeric(version) ||
      length(version) != 1L ||
      !isTRUE(version == subagent_history_version) ||
      !identical(scalar(saved$codec), subagent_history_codec) ||
      !identical(scalar(saved$conversation_id), conversation_id) ||
      !text(saved$data) ||
      nchar(scalar(saved$data), type = "bytes") > 2 * max_bytes
  ) {
    history_codec_abort()
  }
  record <- history_parse(scalar(saved$data))
  inspection_portable(record)
  history <- record$history
  if (
    !is.list(record) ||
      !identical(record$conversation_id, conversation_id) ||
      !is.list(history) ||
      !identical(history$schema_version, 1L) ||
      !identical(history$settled, TRUE) ||
      !identical(
        history$scope,
        subagent_history_scope(lead, conversation_id)
      ) ||
      !is.list(history$children) ||
      !is.character(record$keys) ||
      length(record$keys) != length(history$children) ||
      anyDuplicated(record$keys) ||
      !all(grepl("^[0-9a-f]{64}$", record$keys)) ||
      !is.character(record$pending) ||
      anyDuplicated(record$pending) ||
      !all(grepl("^[0-9a-f]{64}$", record$pending)) ||
      any(record$pending %in% record$keys) ||
      !subagent_history_counts(record$omitted, record$pending)
  ) {
    history_codec_abort()
  }
  for (view in history$children) {
    status <- if (is.list(view)) view$outcome$runtime$status
    if (
      !is.list(view) ||
        (!is.null(status) && !isTRUE(status %in% subagent_history_settled))
    ) {
      history_codec_abort()
    }
    lapply(view$transcript, inspection_replay)
  }
  record
}

# Callbacks ------------------------------------------------------------------

subagent_history_active_id <- function(state) {
  shiny::isolate(state$chat$history$conversation_id())
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
      if (!identical(state$chat$client, state$lead)) {
        cli::cli_abort("The chat no longer runs this lead.")
      }
      record <- subagent_history_record(state, id)
      envelope <- subagent_history_envelope(record)
      state$record <- record
      state$envelope <- envelope
      state$kept <- NULL
      state$conversation_id <- id
      state$error <- NULL
      envelope
    },
    error = function(error) {
      # A save shinychat can't complete loses the conversation, so keep the
      # last good record for it instead.
      state$error <- inspection_text(conditionMessage(error), 1024L)
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
  saved <- values$deputy_subagents
  if (is.null(saved) || is.null(id)) {
    return(invisible(NULL))
  }
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

subagent_history_restored <- function(state, transcript = TRUE) {
  if (
    !is.logical(transcript) || length(transcript) != 1L || is.na(transcript)
  ) {
    cli::cli_abort("{.arg transcript} must be TRUE or FALSE.")
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
      state$lead$.__enclos_env__$private$.delegation_disclosure,
      subagent_history_scope(state$lead, id)
    )
  }
  tryCatch(replay(history), deputy_disclosure_bound = function(error) {
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
    shown <- first(length(children))
    if (!is.null(shown)) {
      return(shown)
    }
    # Fewer children only make the history smaller, so the longest run of
    # them that fits is found by bisection: `low` fits or is zero, `high`
    # doesn't fit.
    shown <- list()
    low <- 0L
    high <- length(children)
    while (low < high) {
      middle <- (low + high) %/% 2L
      fits <- first(middle)
      if (is.null(fits)) {
        high <- middle
      } else {
        shown <- fits
        low <- middle + 1L
      }
    }
    shown
  })
}

subagent_history_status <- function(state) {
  id <- subagent_history_active_id(state)
  current <- !is.null(id) && identical(state$conversation_id, id)
  record <- if (current) state$record
  counts <- record$omitted
  list(
    conversation_id = id,
    saved = length(record$history$children),
    omitted = list(
      running = counts$running %||% 0L,
      transcripts = counts$transcripts %||% 0L,
      children = counts$children %||% 0L
    ),
    error = if (current) state$error
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
# ran in it, then saved ones that aren't live.
subagent_history_panel_views <- function(conversation, live) {
  if (is.null(conversation)) {
    return(live)
  }
  id <- conversation$conversation_id()
  live <- Filter(
    function(view) {
      !is.null(id) &&
        identical(view$outcome$runtime$host_conversation_id, id)
    },
    live
  )
  live_ids <- vapply(live, subagent_history_view_id, character(1))
  restored <- Filter(
    function(view) !subagent_history_view_id(view) %in% live_ids,
    subagent_history_panel_saved(conversation, transcript = FALSE)
  )
  c(restored, live)
}

# Saved subagents are authorized on their own: a requester the disclosure
# refuses them still sees the live ones, with no saved ones beside them.
subagent_history_panel_saved <- function(conversation, transcript = TRUE) {
  tryCatch(
    conversation$restored(transcript = transcript) %||% list(),
    deputy_delegation_disclosure = function(error) list()
  )
}

# The open conversation's live subagents as `$inspect_subagents()` shows
# them, reading and bounding only the records that ran in it, so other
# conversations' subagents can't push its list over the disclosure bound.
subagent_history_live_views <- function(conversation, lead, requester) {
  disclosure <- lead$.__enclos_env__$private$.delegation_disclosure
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
    view <- disclosure$redact(
      lead_inspection_view(lead, record, FALSE),
      requester
    )
    if (!is.list(view)) {
      cli::cli_abort("Disclosure redaction must return a list.")
    }
    inspection_portable(view)
    view
  })
  inspection_bound(views, disclosure)
}

# The observation cursor now, read without building any subagent's view.
subagent_history_cursor <- function(lead, requester) {
  reader <- lead$observe_subagents(requester)
  tryCatch(reader$poll()$cursor, finally = reader$close())
}

# One child for the panel to show: live if it ran in the open conversation,
# otherwise saved with it.
subagent_history_panel_child <- function(conversation, live, id) {
  if (is.null(conversation)) {
    return(live)
  }
  open <- conversation$conversation_id()
  live <- Filter(
    function(view) {
      !is.null(open) &&
        identical(view$outcome$runtime$host_conversation_id, open)
    },
    live
  )
  if (length(live)) {
    return(live)
  }
  Filter(
    function(view) identical(subagent_history_view_id(view), id),
    subagent_history_panel_saved(conversation)
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
#' and every time they are read. When reading them back, `authorize` gets a
#' `scope` holding the lead's `delegation_scope` and the conversation's ID as
#' `chat_conversation_id`; records saved under another scope are not read.
#' Large results that subagents saved to disk are kept as references, which
#' may no longer resolve. Needs shiny and shinychat (>= 0.5.0) with history
#' enabled.
#'
#' @param chat The value returned by [shinychat::chat_server()] for the lead's
#'   chat.
#' @param lead The [Agent] or [LeadAgent] given to `chat_server()` as its
#'   client.
#' @param requester A function returning the current user, as your
#'   [DelegationDisclosure] expects it.
#' @param max_bytes Most bytes of records to save per conversation. Children
#'   that don't fit, here or in the `max_bytes` of the lead's
#'   `delegation_disclosure`, keep their outcome without their conversation,
#'   or are left out, and `status()` counts them. Defaults to 16 MiB.
#' @return Invisibly, a list of functions:
#'   * `restored(transcript = TRUE)`: the subagents saved with the open
#'     conversation, as [delegation_history()] returns them, or `NULL`. With
#'     `transcript = FALSE`, without their conversations, each marked
#'     `retention$transcript = "not_requested"` (or `"omitted"` when it wasn't
#'     saved).
#'   * `status()`: the open conversation's ID, how many subagents its saved
#'     record holds, how many were still running, saved without their
#'     conversation (too large, or removed by the disclosure's `redact`) or
#'     left out at the last save (including subagents left out earlier that
#'     can't be found again, such as an earlier session's or those released
#'     since), and any problem saving or reading it.
#' @seealso [subagent_chat_activity()] to show subagent tool calls in the
#'   chat itself.
#' @export
subagent_chat_history <- function(
  chat,
  lead,
  requester,
  max_bytes = 16 * 1024^2
) {
  if (
    !is.environment(chat) ||
      !is.environment(chat$history) ||
      !is.function(chat$history$on_save) ||
      !is.function(chat$history$on_restore) ||
      !is.function(chat$history$conversation_id)
  ) {
    cli::cli_abort(
      "{.arg chat} must be the value returned by {.fn shinychat::chat_server}."
    )
  }
  if (!inherits(lead, "Agent") || !identical(chat$client, lead)) {
    cli::cli_abort(
      "{.arg lead} must be the Agent that {.arg chat} runs as its client."
    )
  }
  if (!is.function(requester)) {
    cli::cli_abort("{.arg requester} must be a function.")
  }
  max_bytes <- context_policy_whole_number(max_bytes, "max_bytes")
  if (is.null(max_bytes) || max_bytes < 1024) {
    cli::cli_abort("{.arg max_bytes} must be at least 1024.")
  }
  state <- new.env(parent = emptyenv())
  state$chat <- chat
  state$lead <- lead
  state$requester <- requester
  state$max_bytes <- as.double(max_bytes)
  state$conversation_id <- NULL
  state$record <- NULL
  state$envelope <- NULL
  state$kept <- NULL
  state$error <- NULL
  chat$history$on_save(function(values) subagent_history_save(state, values))
  chat$history$on_restore(function(values) {
    subagent_history_restore(state, values)
  })
  invisible(list(
    restored = function(transcript = TRUE) {
      subagent_history_restored(state, transcript)
    },
    status = function() subagent_history_status(state),
    conversation_id = function() subagent_history_active_id(state)
  ))
}
