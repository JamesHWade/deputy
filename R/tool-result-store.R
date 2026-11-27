# Offloaded tool-result storage, manifests, and integrity validation ----------

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

tool_result_uri <- function(result_id, text_sha256) {
  paste0("deputy://tool-result/", result_id, "?text_sha256=", text_sha256)
}

validate_tool_result_text_meta <- function(
  record,
  result_id = NULL,
  session_id = NULL
) {
  is.list(record) &&
    is.character(record$id) &&
    length(record$id) == 1L &&
    grepl("^result_[a-f0-9]{64}$", record$id) &&
    (is.null(result_id) || identical(record$id, result_id)) &&
    is.character(record$session_id) &&
    length(record$session_id) == 1L &&
    !is.na(record$session_id) &&
    nzchar(record$session_id) &&
    (is.null(session_id) || identical(record$session_id, session_id)) &&
    is.numeric(record$text_chars) &&
    length(record$text_chars) == 1L &&
    !is.na(record$text_chars) &&
    is.finite(record$text_chars) &&
    record$text_chars >= 0 &&
    record$text_chars == floor(record$text_chars) &&
    is.character(record$text_sha256) &&
    length(record$text_sha256) == 1L &&
    grepl("^[a-f0-9]{64}$", record$text_sha256)
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

write_tool_result_text <- function(value, path, public_content = FALSE) {
  if (public_content) {
    value <- project_tool_content(value)
  }
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
  stats <- write_tool_result_text(
    envelope$value,
    temporary,
    public_content = identical(envelope$text_format, "public-content-v1")
  )
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
  valid <- validate_tool_result_text_meta(
    manifest,
    result_id = result_id,
    session_id = session_id
  ) &&
    identical(manifest$schema_version, 1L)
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
    cli_abort(
      "Offloaded tool-result manifest not found: {.val {result_id}}",
      class = "deputy_tool_result_not_found"
    )
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
  agent_id,
  force = FALSE,
  public_content = FALSE
) {
  threshold <- policy$max_tool_result_bytes
  if (
    (is.null(threshold) && !force) ||
      inherits(value, "ellmer::ContentToolResult")
  ) {
    return(NULL)
  }

  value_format <- if (public_content) "native-content-v1" else NULL
  serialized <- serialize_tool_result_value(value, value_format)
  bytes <- length(serialized)
  if (!force && bytes <= threshold) {
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
  created <- !file.exists(path)
  if (created) {
    text_temporary <- tempfile(
      "result-text-",
      tmpdir = directory,
      fileext = ".txt"
    )
    on.exit(unlink(text_temporary), add = TRUE)
    text_stats <- write_tool_result_text(value, text_temporary, public_content)
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
      text_format = if (public_content) "public-content-v1" else NULL,
      created_at = Sys.time(),
      value = value,
      value_format = value_format
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
    created = created,
    uri = tool_result_uri(result_id, envelope$text_sha256),
    bytes = bytes,
    sha256 = sha256,
    preview = tool_result_preview(
      if (identical(envelope$text_format, "public-content-v1")) {
        project_tool_content(value)
      } else {
        value
      }
    ),
    path = path
  )
}

validate_tool_result_envelope <- function(
  envelope,
  result_id = NULL,
  session_id = NULL
) {
  serialized <- if (is.list(envelope) && "value" %in% names(envelope)) {
    serialize_tool_result_value(envelope$value, envelope$value_format)
  } else {
    NULL
  }
  sha256 <- if (is.null(serialized)) {
    NULL
  } else {
    digest::digest(serialized, algo = "sha256", serialize = FALSE)
  }
  valid <- validate_tool_result_text_meta(
    envelope,
    result_id = result_id,
    session_id = session_id
  ) &&
    identical(envelope$schema_version, 2L) &&
    identical(envelope$id, paste0("result_", sha256)) &&
    identical(envelope$bytes, length(serialized)) &&
    identical(envelope$sha256, sha256)
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
