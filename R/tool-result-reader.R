# Offloaded tool-result references, previews, and bounded chunk reader -------

#' Find a tool result saved outside the model context
#'
#' When a [ContextPolicy] moves a large tool result out of the model context,
#' the result recorded in the conversation holds a preview and a reference in
#' place of what the tool returned: in place of its value, of its error, or,
#' for a result made of content objects, as the last of them. Use this
#' function on the contents of `agent$get_turns()` to find those results, and
#' `agent$restore_tool_result()` to put back what the tool returned, for
#' example to check an answer against the full results its tools returned.
#'
#' @param x An ellmer [ContentToolResult][ellmer::ContentToolResult], or the
#'   text of one.
#' @return The `deputy://tool-result/...` reference, a string, or `NULL` when
#'   `x` is not a result saved outside the context.
#' @seealso [ContextPolicy()]
#' @export
#' @examples
#' tool_result_reference(ellmer::ContentToolResult("A short result"))
tool_result_reference <- function(x) {
  if (inherits(x, "ellmer::ContentToolResult")) {
    return(tool_result_reference_slot(x)$reference)
  }
  tool_result_reference_in_text(x)
}

tool_result_reference_in_text <- function(value) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !startsWith(value, "[Tool result offloaded by Deputy]\n")
  ) {
    return(NULL)
  }
  references <- compaction_tool_result_references(value)
  if (length(references) != 1L) {
    return(NULL)
  }
  references
}

# Where an offloaded result keeps its reference, as bound_rich_tool_result()
# and the runtime offload write it: in place of the value, in place of the
# error, or as the last of a list of contents.
tool_result_reference_slot <- function(content) {
  reference <- tool_result_reference_in_text(content@error)
  if (!is.null(reference)) {
    return(list(reference = reference, slot = "error"))
  }
  value <- content@value
  reference <- tool_result_reference_in_text(value)
  if (!is.null(reference)) {
    return(list(reference = reference, slot = "value"))
  }
  if (is.list(value) && !is.object(value) && length(value)) {
    last <- value[[length(value)]]
    if (inherits(last, "ellmer::ContentText")) {
      reference <- tool_result_reference_in_text(last@text)
      if (!is.null(reference)) {
        return(list(reference = reference, slot = "contents"))
      }
    }
  }
  list(reference = NULL, slot = NULL)
}

# `content` with what its tool returned put back, read with `resolve`, or
# `content` unchanged when it holds no reference or the result can't be read.
# Errors and lists of contents are saved inside an envelope of their own
# (bound_rich_tool_result()).
restore_tool_result_content <- function(
  content,
  resolve,
  call = rlang::caller_env()
) {
  if (!inherits(content, "ellmer::ContentToolResult")) {
    cli_abort(
      "{.arg content} must be an ellmer {.cls ContentToolResult}.",
      call = call
    )
  }
  found <- tool_result_reference_slot(content)
  if (is.null(found$reference)) {
    return(content)
  }
  read <- tryCatch(
    list(value = resolve(found$reference)),
    error = function(error) NULL
  )
  if (is.null(read)) {
    return(content)
  }
  stored <- read$value
  if (identical(found$slot, "error")) {
    if (
      !is.list(stored) ||
        !is.character(stored$error) ||
        length(stored$error) != 1L
    ) {
      return(content)
    }
    content@error <- stored$error
  } else if (identical(found$slot, "contents")) {
    if (
      !is.list(stored) ||
        !identical(stored$kind, "deputy_native_content") ||
        !is.list(stored$content)
    ) {
      return(content)
    }
    content@value <- stored$content
  } else {
    content@value <- stored
  }
  content
}

tool_result_reference_text <- function(record) {
  paste(
    "[Tool result offloaded by Deputy]",
    paste0("reference: ", record$uri),
    paste0("bytes: ", record$bytes),
    paste0("sha256: ", record$sha256),
    paste0("preview:\n", record$preview),
    paste0(
      "Call deputy_read_tool_result(reference, offset) for bounded chunks; ",
      "the host can recover the R value with Agent$resolve_tool_result()."
    ),
    sep = "\n"
  )
}

tool_result_character_preview <- function(value, max_chars) {
  if (length(value) == 0L) {
    return("")
  }

  max_elements <- min(length(value), max(1L, max_chars + 1L))
  pieces <- character(max_elements)
  used <- 0L
  count <- 0L
  truncated <- FALSE
  for (index in seq_len(max_elements)) {
    separator <- if (index == 1L) "" else "\n"
    available <- max_chars - used - nchar(separator, type = "chars")
    if (available <= 0L) {
      truncated <- TRUE
      break
    }

    piece <- value[[index]]
    if (is.na(piece)) {
      piece <- "NA"
    }
    piece_chars <- nchar(piece, type = "chars")
    if (piece_chars > available) {
      piece <- substr(piece, 1L, available)
      truncated <- TRUE
    }
    count <- count + 1L
    pieces[[count]] <- paste0(separator, piece)
    used <- used + nchar(pieces[[count]], type = "chars")
    if (truncated) {
      break
    }
  }
  if (count < length(value)) {
    truncated <- TRUE
  }

  text <- paste0(pieces[seq_len(count)], collapse = "")
  if (truncated) {
    paste0(text, "\n[preview truncated]")
  } else {
    text
  }
}

tool_result_preview <- function(value, max_chars = 4000L) {
  if (is.character(value)) {
    return(tool_result_character_preview(value, max_chars))
  }

  text <- paste(
    utils::capture.output(utils::str(
      value,
      max.level = 2L,
      vec.len = 8L,
      list.len = 8L,
      nchar.max = 80L,
      give.attr = FALSE,
      strict.width = "cut",
      width = 80L
    )),
    collapse = "\n"
  )
  if (nchar(text, type = "chars") <= max_chars) {
    return(text)
  }
  paste0(substr(text, 1L, max_chars), "\n[preview truncated]")
}

# What the reader says when a well-formed reference matches nothing saved:
# the model learns where references come from instead of guessing again.
tool_result_not_found <- function(parent) {
  cli_abort(
    c(
      "No saved tool result matches that reference.",
      "i" = paste0(
        "Use a {.code deputy://tool-result/...} reference exactly as a tool ",
        "result gave it."
      )
    ),
    parent = parent,
    class = "deputy_tool_result_not_found"
  )
}

read_tool_result_chunk <- function(
  reference,
  offset,
  max_chars,
  policy,
  session_id
) {
  offset <- validate_nonnegative_int(offset, "offset")
  max_chars <- validate_positive_int(max_chars, "max_chars")
  if (max_chars > 16384L) {
    cli_abort("{.arg max_chars} must not exceed 16384")
  }

  artifact <- tryCatch(
    read_tool_result_manifest(reference, policy, session_id),
    deputy_tool_result_not_found = function(error) {
      tool_result_not_found(error)
    }
  )
  manifest <- artifact$manifest
  text_path <- artifact$text_path
  total_chars <- manifest$text_chars
  if (offset > total_chars) {
    cli_abort("{.arg offset} exceeds the result length of {total_chars}")
  }
  connection <- file(text_path, open = "rb")
  on.exit(close(connection), add = TRUE)
  remaining <- offset
  while (remaining > 0) {
    skipped <- readChar(
      connection,
      nchars = min(65536, remaining),
      useBytes = FALSE
    )
    skipped_chars <- if (length(skipped) == 0L) {
      0L
    } else {
      nchar(skipped, type = "chars")
    }
    if (skipped_chars == 0L) {
      break
    }
    remaining <- remaining - skipped_chars
  }
  chunk <- if (offset == total_chars) {
    ""
  } else {
    value <- readChar(connection, nchars = max_chars, useBytes = FALSE)
    if (length(value) == 0L) "" else value
  }
  next_offset <- offset + nchar(chunk, type = "chars")
  paste(
    paste0("reference: ", tool_result_uri(manifest$id, manifest$text_sha256)),
    paste0("offset: ", offset),
    paste0("next_offset: ", next_offset),
    paste0("total_chars: ", total_chars),
    paste0("complete: ", next_offset >= total_chars),
    "content:",
    chunk,
    sep = "\n"
  )
}

tool_result_reader_tool <- function(read_chunk) {
  tool <- ellmer::tool(
    fun = function(reference, offset = 0L, max_chars = 8192L) {
      read_chunk(reference, offset, max_chars)
    },
    name = "deputy_read_tool_result",
    description = paste(
      "Read a bounded chunk of a large tool result offloaded by Deputy.",
      "Use next_offset to continue until complete is true."
    ),
    arguments = list(
      reference = ellmer::type_string(
        "The deputy://tool-result reference returned by a tool."
      ),
      offset = ellmer::type_integer(
        "Zero-based character offset.",
        required = FALSE
      ),
      max_chars = ellmer::type_integer(
        "Maximum characters to return, up to 16384.",
        required = FALSE
      )
    ),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE
    )
  )
  attr(tool, "deputy_internal_tool") <- deputy_tool_result_reader_marker
  tool
}

parse_tool_result_reference <- function(reference) {
  if (
    !is.character(reference) ||
      length(reference) != 1L ||
      is.na(reference)
  ) {
    cli_abort("{.arg reference} must be one Deputy tool-result reference")
  }
  match <- regexec("deputy://tool-result/(result_[a-f0-9]{64})", reference)
  captured <- regmatches(reference, match)[[1]]
  if (length(captured) != 2L) {
    cli_abort("{.arg reference} is not a Deputy tool-result reference")
  }
  captured[[2]]
}

parse_tool_result_text_reference <- function(reference) {
  if (
    !is.character(reference) ||
      length(reference) != 1L ||
      is.na(reference)
  ) {
    cli_abort("{.arg reference} must be one Deputy tool-result reference")
  }
  match <- regexec(
    paste0(
      "deputy://tool-result/(result_[a-f0-9]{64})",
      "\\?text_sha256=([a-f0-9]{64})"
    ),
    reference
  )
  captured <- regmatches(reference, match)[[1]]
  if (length(captured) != 3L) {
    cli_abort(
      "{.arg reference} is not a chunkable Deputy tool-result reference"
    )
  }
  list(id = captured[[2]], text_sha256 = captured[[3]])
}

# A verified reference envelope already has bounded preview/control overhead.
# Do not wrap it in another artifact just because a tiny policy is smaller.
is_tool_result_reference_text <- function(value, policy, session_id) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.null(names(value)) ||
      nchar(value, "bytes") > 32768L ||
      !startsWith(value, "[Tool result offloaded by Deputy]\n")
  ) {
    return(FALSE)
  }
  references <- compaction_tool_result_references(value)
  if (length(references) != 1L) {
    return(FALSE)
  }
  envelope <- tryCatch(
    read_tool_result_envelope(references, policy, session_id),
    error = function(e) NULL
  )
  if (is.null(envelope)) {
    return(FALSE)
  }
  evidence <- if (identical(envelope$text_format, "public-content-v1")) {
    project_tool_content(envelope$value)
  } else {
    envelope$value
  }
  identical(
    value,
    tool_result_reference_text(list(
      uri = tool_result_uri(envelope$id, envelope$text_sha256),
      bytes = envelope$bytes,
      sha256 = envelope$sha256,
      preview = tool_result_preview(evidence)
    ))
  )
}
