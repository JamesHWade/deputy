# Runtime tool adaptation ---------------------------------------------------

native_file_tool_names <- c(
  "read_file",
  "read_markdown",
  "write_file",
  "edit_file",
  "multi_edit",
  "list_files",
  "glob_files",
  "grep_files",
  "read_csv"
)

deputy_tool_result_reader_marker <- new.env(parent = emptyenv())

clear_chat_tool_callbacks <- function(chat) {
  private <- tryCatch(chat$.__enclos_env__$private, error = function(e) NULL)
  for (name in c("callback_on_tool_request", "callback_on_tool_result")) {
    manager <- private[[name]]
    if (!is.null(manager) && is.function(manager$clear)) manager$clear()
  }
  invisible(chat)
}

runtime_wrap_tool <- function(
  tool,
  resolve_arguments,
  process_result,
  begin_execution = function(tool_name) NULL,
  execute = function(tool, arguments) do.call(tool, arguments)
) {
  if (!inherits(tool, "ellmer::ToolDef")) {
    cli_abort("{.arg tool} must be an ellmer tool definition")
  }
  if (
    !is.function(resolve_arguments) ||
      !is.function(process_result) ||
      !is.function(begin_execution) ||
      !is.function(execute)
  ) {
    cli_abort("Runtime tool adapters must be functions")
  }

  source_tool <- attr(tool, "deputy_runtime_source_tool", exact = TRUE)
  if (is.null(source_tool)) {
    source_tool <- tool
  }

  wrapper_env <- rlang::env(
    original = source_tool,
    resolve_arguments = resolve_arguments,
    process_result = process_result,
    begin_execution = begin_execution,
    execute = execute,
    tool_name = source_tool@name
  )
  invoke <- rlang::new_function(
    alist(arguments = ),
    quote({
      arguments <- resolve_arguments(
        tool_name,
        arguments
      )
      execution_id <- begin_execution(tool_name)
      value <- execute(original, arguments)
      if (promises::is.promising(value)) {
        return(promises::then(value, function(resolved) {
          process_result(tool_name, resolved, execution_id)
        }))
      }
      process_result(tool_name, value, execution_id)
    }),
    wrapper_env
  )
  wrapper <- rlang::new_function(
    formals(source_tool),
    rlang::expr((!!invoke)(base::as.list(
      base::environment(),
      all.names = TRUE
    )))
  )

  wrapped <- ellmer::tool(
    fun = wrapper,
    name = source_tool@name,
    description = source_tool@description,
    arguments = source_tool@arguments@properties,
    convert = source_tool@convert,
    annotations = source_tool@annotations
  )
  attr(wrapped, "deputy_runtime_tool") <- TRUE
  attr(wrapped, "deputy_runtime_source_tool") <- source_tool
  internal_tool <- attr(source_tool, "deputy_internal_tool", exact = TRUE)
  if (!is.null(internal_tool)) {
    attr(wrapped, "deputy_internal_tool") <- internal_tool
  }
  wrapped
}

resolve_runtime_tool_arguments <- function(tool_name, arguments, working_dir) {
  if (
    !tool_name %in% native_file_tool_names ||
      is.null(arguments$path) ||
      !is.character(arguments$path) ||
      length(arguments$path) != 1L ||
      is.na(arguments$path) ||
      !nzchar(arguments$path)
  ) {
    return(arguments)
  }

  if (!is_absolute_path(arguments$path)) {
    arguments$path <- file.path(working_dir, arguments$path)
  }
  arguments
}

tool_result_offload_dir <- function(policy, session_id) {
  root <- policy$offload_dir %||%
    file.path(tools::R_user_dir("deputy", "cache"), "tool-results")
  file.path(path.expand(root), session_id)
}

tool_result_text_path <- function(directory, result_id) {
  file.path(directory, paste0(result_id, ".txt"))
}

tool_result_manifest_path <- function(directory, result_id) {
  file.path(directory, paste0(result_id, ".meta.rds"))
}

tool_result_text_stats <- function(path) {
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  chars <- 0
  repeat {
    chunk <- readChar(connection, nchars = 65536L, useBytes = FALSE)
    if (length(chunk) == 0L || !nzchar(chunk)) {
      break
    }
    chars <- chars + nchar(chunk, type = "chars")
  }
  list(
    chars = as.numeric(chars),
    sha256 = digest::digest(
      file = path,
      algo = "sha256",
      serialize = FALSE
    )
  )
}

write_tool_result_text <- function(value, path) {
  if (is.character(value)) {
    connection <- file(path, open = "wb")
    on.exit(close(connection), add = TRUE)
    for (index in seq_along(value)) {
      if (index > 1L) {
        writeChar("\n", connection, eos = NULL, useBytes = TRUE)
      }
      piece <- if (is.na(value[[index]])) "NA" else value[[index]]
      writeChar(
        enc2utf8(piece),
        connection,
        eos = NULL,
        useBytes = TRUE
      )
    }
    close(connection)
    on.exit(NULL, add = FALSE)
  } else {
    dput(value, file = path)
  }
  Sys.chmod(path, mode = "0600")
  tool_result_text_stats(path)
}

validate_tool_result_text <- function(path, envelope) {
  if (!file.exists(path)) {
    return(FALSE)
  }
  stats <- tool_result_text_stats(path)
  valid <- identical(stats$chars, envelope$text_chars) &&
    identical(stats$sha256, envelope$text_sha256)
  if (!isTRUE(valid)) {
    cli_abort("Offloaded tool-result text failed integrity validation")
  }
  TRUE
}

ensure_tool_result_text <- function(envelope, directory) {
  path <- tool_result_text_path(directory, envelope$id)
  if (file.exists(path)) {
    validate_tool_result_text(path, envelope)
    return(path)
  }

  temporary <- tempfile("result-text-", tmpdir = directory, fileext = ".txt")
  on.exit(unlink(temporary), add = TRUE)
  stats <- write_tool_result_text(envelope$value, temporary)
  if (
    !identical(stats$chars, envelope$text_chars) ||
      !identical(stats$sha256, envelope$text_sha256)
  ) {
    cli_abort("Offloaded tool-result text does not match its envelope")
  }
  if (!file.rename(temporary, path)) {
    cli_abort("Could not commit the chunkable tool-result text")
  }
  path
}

validate_tool_result_manifest <- function(
  manifest,
  result_id = NULL,
  session_id = NULL
) {
  valid <- is.list(manifest) &&
    identical(manifest$schema_version, 1L) &&
    is.character(manifest$id) &&
    length(manifest$id) == 1L &&
    grepl("^result_[a-f0-9]{64}$", manifest$id) &&
    (is.null(result_id) || identical(manifest$id, result_id)) &&
    is.character(manifest$session_id) &&
    length(manifest$session_id) == 1L &&
    !is.na(manifest$session_id) &&
    nzchar(manifest$session_id) &&
    (is.null(session_id) || identical(manifest$session_id, session_id)) &&
    is.numeric(manifest$text_chars) &&
    length(manifest$text_chars) == 1L &&
    !is.na(manifest$text_chars) &&
    is.finite(manifest$text_chars) &&
    manifest$text_chars >= 0 &&
    manifest$text_chars == floor(manifest$text_chars) &&
    is.character(manifest$text_sha256) &&
    length(manifest$text_sha256) == 1L &&
    grepl("^[a-f0-9]{64}$", manifest$text_sha256)
  if (!isTRUE(valid)) {
    cli_abort("Offloaded tool-result manifest failed integrity validation")
  }
  manifest
}

ensure_tool_result_manifest <- function(envelope, directory) {
  manifest <- list(
    schema_version = 1L,
    id = envelope$id,
    session_id = envelope$session_id,
    text_chars = envelope$text_chars,
    text_sha256 = envelope$text_sha256
  )
  path <- tool_result_manifest_path(directory, envelope$id)
  if (file.exists(path)) {
    stored <- validate_tool_result_manifest(
      readRDS(path),
      result_id = envelope$id,
      session_id = envelope$session_id
    )
    if (
      !identical(stored$text_chars, envelope$text_chars) ||
        !identical(stored$text_sha256, envelope$text_sha256)
    ) {
      cli_abort("Offloaded tool-result manifest does not match its envelope")
    }
    return(path)
  }

  temporary <- tempfile(
    "result-manifest-",
    tmpdir = directory,
    fileext = ".rds"
  )
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(manifest, temporary, version = 3)
  Sys.chmod(temporary, mode = "0600")
  if (!file.rename(temporary, path)) {
    cli_abort("Could not commit the tool-result manifest")
  }
  path
}

ensure_tool_result_artifacts <- function(envelope, directory) {
  c(
    text = ensure_tool_result_text(envelope, directory),
    manifest = ensure_tool_result_manifest(envelope, directory)
  )
}

read_tool_result_manifest <- function(reference, policy, session_id) {
  details <- parse_tool_result_text_reference(reference)
  result_id <- details$id
  directory <- tool_result_offload_dir(policy, session_id)
  path <- tool_result_manifest_path(directory, result_id)
  if (!file.exists(path)) {
    cli_abort("Offloaded tool-result manifest not found: {.val {result_id}}")
  }
  manifest <- validate_tool_result_manifest(
    readRDS(path),
    result_id = result_id,
    session_id = session_id
  )
  if (!identical(manifest$text_sha256, details$text_sha256)) {
    cli_abort("Tool-result reference does not match its chunkable text")
  }
  text_path <- tool_result_text_path(directory, result_id)
  if (!file.exists(text_path)) {
    cli_abort("Chunkable tool-result text not found: {.val {result_id}}")
  }
  validate_tool_result_text(text_path, manifest)
  list(manifest = manifest, text_path = text_path)
}

offload_tool_result <- function(
  value,
  tool_name,
  policy,
  session_id,
  agent_id
) {
  threshold <- policy$max_tool_result_bytes
  if (is.null(threshold) || inherits(value, "ellmer::ContentToolResult")) {
    return(NULL)
  }

  serialized <- serialize(value, NULL, version = 3)
  bytes <- length(serialized)
  if (bytes <= threshold) {
    return(NULL)
  }

  sha256 <- digest::digest(serialized, algo = "sha256", serialize = FALSE)
  result_id <- paste0("result_", sha256)
  directory <- tool_result_offload_dir(policy, session_id)
  if (!dir.exists(directory)) {
    dir.create(directory, recursive = TRUE, showWarnings = FALSE)
    Sys.chmod(directory, mode = "0700")
  }
  if (!dir.exists(directory)) {
    cli_abort("Could not create the tool-result offload directory")
  }

  path <- file.path(directory, paste0(result_id, ".rds"))
  if (!file.exists(path)) {
    text_temporary <- tempfile(
      "result-text-",
      tmpdir = directory,
      fileext = ".txt"
    )
    on.exit(unlink(text_temporary), add = TRUE)
    text_stats <- write_tool_result_text(value, text_temporary)
    envelope <- list(
      schema_version = 2L,
      id = result_id,
      tool_name = tool_name,
      session_id = session_id,
      agent_id = agent_id,
      bytes = bytes,
      sha256 = sha256,
      text_chars = text_stats$chars,
      text_sha256 = text_stats$sha256,
      created_at = Sys.time(),
      value = value
    )
    temporary <- tempfile("result-", tmpdir = directory, fileext = ".rds")
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(envelope, temporary, version = 3)
    Sys.chmod(temporary, mode = "0600")
    text_path <- tool_result_text_path(directory, result_id)
    if (file.exists(text_path)) {
      validate_tool_result_text(text_path, envelope)
    } else if (!file.rename(text_temporary, text_path)) {
      cli_abort("Could not commit the chunkable tool-result text")
    }
    if (!file.rename(temporary, path)) {
      cli_abort("Could not commit the offloaded tool result")
    }
    ensure_tool_result_manifest(envelope, directory)
  } else {
    envelope <- validate_tool_result_envelope(
      readRDS(path),
      result_id = result_id,
      session_id = session_id
    )
    ensure_tool_result_artifacts(envelope, directory)
  }

  list(
    id = result_id,
    uri = paste0(
      "deputy://tool-result/",
      result_id,
      "?text_sha256=",
      envelope$text_sha256
    ),
    bytes = bytes,
    sha256 = sha256,
    preview = tool_result_preview(value),
    path = path
  )
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

validate_tool_result_envelope <- function(
  envelope,
  result_id = NULL,
  session_id = NULL
) {
  serialized <- if (is.list(envelope) && "value" %in% names(envelope)) {
    serialize(envelope$value, NULL, version = 3)
  } else {
    NULL
  }
  sha256 <- if (is.null(serialized)) {
    NULL
  } else {
    digest::digest(serialized, algo = "sha256", serialize = FALSE)
  }
  valid <- is.list(envelope) &&
    identical(envelope$schema_version, 2L) &&
    is.character(envelope$id) &&
    length(envelope$id) == 1L &&
    grepl("^result_[a-f0-9]{64}$", envelope$id) &&
    identical(envelope$id, paste0("result_", sha256)) &&
    (is.null(result_id) || identical(envelope$id, result_id)) &&
    is.character(envelope$session_id) &&
    length(envelope$session_id) == 1L &&
    !is.na(envelope$session_id) &&
    nzchar(envelope$session_id) &&
    (is.null(session_id) || identical(envelope$session_id, session_id)) &&
    identical(envelope$bytes, length(serialized)) &&
    identical(envelope$sha256, sha256) &&
    is.numeric(envelope$text_chars) &&
    length(envelope$text_chars) == 1L &&
    !is.na(envelope$text_chars) &&
    is.finite(envelope$text_chars) &&
    envelope$text_chars >= 0 &&
    envelope$text_chars == floor(envelope$text_chars) &&
    is.character(envelope$text_sha256) &&
    length(envelope$text_sha256) == 1L &&
    grepl("^[a-f0-9]{64}$", envelope$text_sha256)
  if (!isTRUE(valid)) {
    cli_abort("Offloaded tool result failed integrity validation")
  }
  envelope
}

validate_tool_result_envelopes <- function(envelopes, session_id) {
  if (
    !is.character(session_id) ||
      length(session_id) != 1L ||
      is.na(session_id) ||
      !nzchar(session_id) ||
      !grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", session_id)
  ) {
    cli_abort("Saved tool results require one non-empty session identifier")
  }
  if (!is.list(envelopes)) {
    cli_abort("Saved tool results must be a named list")
  }
  if (length(envelopes) == 0L) {
    return(list())
  }
  result_ids <- names(envelopes)
  if (
    is.null(result_ids) ||
      anyNA(result_ids) ||
      !all(nzchar(result_ids)) ||
      anyDuplicated(result_ids)
  ) {
    cli_abort("Saved tool results must have unique result identifiers")
  }

  Map(
    function(envelope, result_id) {
      validate_tool_result_envelope(
        envelope,
        result_id = result_id,
        session_id = session_id
      )
    },
    envelopes,
    result_ids
  )
}

collect_tool_result_envelopes <- function(policy, session_id) {
  directory <- tool_result_offload_dir(policy, session_id)
  if (!dir.exists(directory)) {
    return(list())
  }
  paths <- list.files(
    directory,
    pattern = "^result_[a-f0-9]{64}\\.rds$",
    full.names = TRUE
  )
  if (length(paths) == 0L) {
    return(list())
  }
  result_ids <- sub("\\.rds$", "", basename(paths))
  envelopes <- Map(
    function(path, result_id) {
      validate_tool_result_envelope(
        readRDS(path),
        result_id = result_id,
        session_id = session_id
      )
    },
    paths,
    result_ids
  )
  names(envelopes) <- result_ids
  envelopes
}

begin_tool_result_envelope_replacement <- function(
  envelopes,
  policy,
  source_session_id,
  target_session_id
) {
  target_session_id <- validate_deputy_id(
    target_session_id,
    argument = "target_session_id"
  )
  envelopes <- validate_tool_result_envelopes(
    envelopes,
    source_session_id
  )

  directory <- tool_result_offload_dir(policy, target_session_id)
  if (length(envelopes) == 0L && !file.exists(directory)) {
    return(list(directory = directory, backup = NULL))
  }
  root <- dirname(directory)
  if (!dir.exists(root)) {
    dir.create(root, recursive = TRUE, showWarnings = FALSE)
    Sys.chmod(root, mode = "0700")
  }
  if (!dir.exists(root)) {
    cli_abort("Could not create the tool-result offload root")
  }

  staging <- NULL
  installed <- FALSE
  on.exit(
    {
      if (!installed && !is.null(staging) && dir.exists(staging)) {
        unlink(staging, recursive = TRUE)
      }
    },
    add = TRUE
  )

  if (length(envelopes) > 0L) {
    staging <- tempfile(
      paste0(".", basename(directory), "-staging-"),
      tmpdir = root
    )
    dir.create(staging, showWarnings = FALSE)
    Sys.chmod(staging, mode = "0700")
    if (!dir.exists(staging)) {
      cli_abort("Could not stage restored tool results")
    }

    for (result_id in names(envelopes)) {
      envelope <- envelopes[[result_id]]
      envelope$session_id <- target_session_id
      path <- file.path(staging, paste0(result_id, ".rds"))
      saveRDS(envelope, path, version = 3)
      Sys.chmod(path, mode = "0600")
      ensure_tool_result_artifacts(envelope, staging)
    }
  }

  if (file.exists(directory) && !dir.exists(directory)) {
    cli_abort("Tool-result offload path is not a directory")
  }
  backup <- NULL
  if (dir.exists(directory)) {
    backup <- tempfile(
      paste0(".", basename(directory), "-backup-"),
      tmpdir = root
    )
    if (!file.rename(directory, backup)) {
      cli_abort("Could not preserve the existing tool-result offloads")
    }
  }

  if (!is.null(staging) && !file.rename(staging, directory)) {
    if (!is.null(backup)) {
      file.rename(backup, directory)
    }
    cli_abort("Could not activate the restored tool results")
  }
  installed <- TRUE

  list(
    directory = directory,
    backup = backup
  )
}

rollback_tool_result_envelope_replacement <- function(replacement) {
  if (dir.exists(replacement$directory)) {
    unlink(replacement$directory, recursive = TRUE)
  }
  if (!is.null(replacement$backup) && dir.exists(replacement$backup)) {
    if (!file.rename(replacement$backup, replacement$directory)) {
      cli_abort("Could not roll back the tool-result offloads")
    }
  }
  invisible(NULL)
}

commit_tool_result_envelope_replacement <- function(replacement) {
  if (!is.null(replacement$backup) && dir.exists(replacement$backup)) {
    unlink(replacement$backup, recursive = TRUE)
  }
  invisible(NULL)
}

read_tool_result_envelope <- function(reference, policy, session_id) {
  result_id <- parse_tool_result_reference(reference)
  path <- file.path(
    tool_result_offload_dir(policy, session_id),
    paste0(result_id, ".rds")
  )
  if (!file.exists(path)) {
    cli_abort("Offloaded tool result not found: {.val {result_id}}")
  }

  validate_tool_result_envelope(
    readRDS(path),
    result_id = result_id,
    session_id = session_id
  )
}

read_tool_result_chunk <- function(
  reference,
  offset,
  max_chars,
  policy,
  session_id
) {
  offset <- context_policy_nonnegative_whole_number(offset, "offset")
  max_chars <- context_policy_whole_number(max_chars, "max_chars")
  if (max_chars > 16384L) {
    cli_abort("{.arg max_chars} must not exceed 16384")
  }

  artifact <- read_tool_result_manifest(reference, policy, session_id)
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
    paste0(
      "reference: deputy://tool-result/",
      manifest$id,
      "?text_sha256=",
      manifest$text_sha256
    ),
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
