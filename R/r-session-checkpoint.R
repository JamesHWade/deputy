# A checkpoint is a bounded, immutable file in a trusted host directory.
# It contains a checksum, a JSON manifest and an opaque R payload. The host
# checks identity and integrity without deserializing the worker data.
r_session_checkpoint_max_bytes <- 8L * 1024L^2
r_session_checkpoint_header_bytes <- 64L * 1024L

r_session_checkpoint_abort <- function(message, parent = NULL) {
  abort_deputy(
    message,
    class = "r_session_checkpoint",
    parent = parent,
    .envir = parent.frame()
  )
}

r_session_checkpoint_config <- function(directory, owner_id) {
  r_session_store_config(
    directory = directory,
    owner_id = owner_id,
    dir_arg = "checkpoint_dir",
    owner_arg = "checkpoint_owner_id",
    abort_fn = r_session_checkpoint_abort
  )
}

r_session_checkpoint_owner <- function(config, owner) {
  list(
    owner_id = config$owner_id,
    agent_id = unname(owner$agent_id),
    session_id = unname(owner$session_id)
  )
}

r_session_checkpoint_bindings <- function(bindings) {
  if (
    !is.character(bindings) ||
      !length(bindings) ||
      length(bindings) > 256L ||
      anyNA(bindings) ||
      !all(nzchar(bindings)) ||
      any(nchar(bindings, "bytes") > 128L) ||
      any(grepl("[[:cntrl:]]", bindings)) ||
      anyDuplicated(bindings)
  ) {
    r_session_checkpoint_abort(
      "{.arg bindings} must contain 1 to 256 distinct, nonempty names of at most 128 bytes each, without control characters."
    )
  }
  if (any(bindings %in% c("tools", ".Random.seed", ".Last"))) {
    r_session_checkpoint_abort(
      "Checkpoint bindings cannot replace the tool bridge, random state or the R shutdown hook."
    )
  }
  unname(bindings)
}

r_session_checkpoint_path <- function(config, id) {
  if (!is_nonempty_string(id) || !grepl("^r_checkpoint_[0-9a-f-]{36}$", id)) {
    r_session_checkpoint_abort("The R session checkpoint ID is invalid.")
  }
  directory <- r_session_store_verify_dir(
    config,
    "checkpoint",
    r_session_checkpoint_abort
  )
  file.path(directory, paste0(id, ".bin"))
}

r_session_checkpoint_receipt <- function(manifest, sha256) {
  c(manifest[c("id", "bindings", "generation", "bytes")], list(sha256 = sha256))
}

r_session_checkpoint_write <- function(
  config,
  owner,
  bindings,
  payload,
  generation
) {
  if (!is.raw(payload) || length(payload) > r_session_checkpoint_max_bytes) {
    r_session_checkpoint_abort("The R session checkpoint payload is invalid.")
  }
  id <- new_deputy_id("r_checkpoint_")
  manifest <- list(
    version = 1L,
    id = id,
    owner = r_session_checkpoint_owner(config, owner),
    bindings = bindings,
    generation = generation,
    bytes = length(payload)
  )
  header <- manifest
  header$bindings <- I(bindings)
  header <- charToRaw(enc2utf8(jsonlite::toJSON(header, auto_unbox = TRUE)))
  if (length(header) > r_session_checkpoint_header_bytes) {
    r_session_checkpoint_abort(
      "The R session checkpoint manifest is too large."
    )
  }
  body <- c(header, as.raw(10L), payload)
  sha256 <- digest::digest(body, algo = "sha256", serialize = FALSE)
  path <- r_session_checkpoint_path(config, id)
  write_file_atomic(
    path,
    write_fn = function(temporary) {
      connection <- file(temporary, "wb")
      tryCatch(
        writeBin(c(charToRaw(sha256), as.raw(10L), body), connection),
        finally = close(connection)
      )
    },
    prefix = ".checkpoint-",
    fail_if_exists = TRUE,
    on_write_error = function(error) {
      r_session_checkpoint_abort(
        "Could not write the R session checkpoint.",
        error
      )
    },
    on_commit_error = function() {
      r_session_checkpoint_abort("Could not publish the R session checkpoint.")
    }
  )
  r_session_checkpoint_receipt(manifest, sha256)
}

r_session_checkpoint_read <- function(config, owner, id) {
  path <- r_session_checkpoint_path(config, id)
  if (!utils::file_test("-f", path) || nzchar(read_symlink_target(path))) {
    r_session_checkpoint_abort(
      "The R session checkpoint file is missing or invalid."
    )
  }
  bytes <- tryCatch(
    suppressWarnings(read_file_raw_bounded(
      path,
      r_session_checkpoint_max_bytes + r_session_checkpoint_header_bytes + 66L
    )),
    error = function(error) {
      r_session_checkpoint_abort(
        "Could not read the R session checkpoint.",
        error
      )
    }
  )
  if (length(bytes) <= 66L || bytes[[65L]] != as.raw(10L)) {
    r_session_checkpoint_abort("The R session checkpoint header is invalid.")
  }
  body <- bytes[-seq_len(65L)]
  sha256 <- digest::digest(body, algo = "sha256", serialize = FALSE)
  if (!identical(bytes[seq_len(64L)], charToRaw(sha256))) {
    r_session_checkpoint_abort(
      "The R session checkpoint failed its integrity check."
    )
  }
  newline <- match(
    as.raw(10L),
    utils::head(body, r_session_checkpoint_header_bytes + 1L)
  )
  if (is.na(newline) || newline <= 1L || newline == length(body)) {
    r_session_checkpoint_abort("The R session checkpoint manifest is invalid.")
  }
  manifest <- tryCatch(
    jsonlite::fromJSON(rawToChar(body[seq_len(newline - 1L)])),
    error = function(error) {
      r_session_checkpoint_abort(
        "Could not read the checkpoint manifest.",
        error
      )
    }
  )
  payload <- body[seq.int(newline + 1L, length(body))]
  if (
    !is.list(manifest) ||
      !identical(
        names(manifest),
        c(
          "version",
          "id",
          "owner",
          "bindings",
          "generation",
          "bytes"
        )
      ) ||
      !identical(manifest$version, 1L) ||
      !identical(manifest$id, id) ||
      !is.integer(manifest$generation) ||
      length(manifest$generation) != 1L ||
      is.na(manifest$generation) ||
      manifest$generation < 1L ||
      !identical(manifest$bytes, length(payload)) ||
      length(payload) > r_session_checkpoint_max_bytes
  ) {
    r_session_checkpoint_abort("The R session checkpoint manifest is invalid.")
  }
  if (!identical(manifest$owner, r_session_checkpoint_owner(config, owner))) {
    r_session_checkpoint_abort(
      "The R session checkpoint belongs to another owner."
    )
  }
  manifest$bindings <- r_session_checkpoint_bindings(manifest$bindings)
  list(
    receipt = r_session_checkpoint_receipt(manifest, sha256),
    payload = payload
  )
}

# Sent to the worker with a base environment, so keep it self-contained.
r_session_checkpoint_validate_data <- function(value) {
  base_classes <- list(
    "data.frame",
    "factor",
    c("ordered", "factor"),
    "Date",
    c("POSIXct", "POSIXt"),
    c("POSIXlt", "POSIXt"),
    "difftime"
  )
  check <- function(item, depth = 0L) {
    if (depth > 100L) {
      stop("Checkpoint data exceeds its nesting limit.", call. = FALSE)
    }
    if (is.null(item)) {
      return(invisible(NULL))
    }
    if (
      !typeof(item) %in%
        c(
          "logical",
          "integer",
          "double",
          "complex",
          "character",
          "raw",
          "list"
        ) ||
        isS4(item) ||
        (is.object(item) &&
          !any(vapply(base_classes, identical, logical(1), y = class(item))))
    ) {
      stop("Checkpoint data must contain only ordinary R data.", call. = FALSE)
    }
    if (is.list(item)) {
      for (element in unclass(item)) {
        check(element, depth + 1L)
      }
    }
    for (attribute in attributes(item)) {
      check(attribute, depth + 1L)
    }
    invisible(NULL)
  }
  check(value)
}

# Checkpoint queue orchestration for RSession -------------------------------

r_session_check_checkpoint <- function(private) {
  private$check_current()
  if (is.null(private$checkpoint_config)) {
    abort_deputy(
      "Configure {.arg checkpoint_dir} and {.arg checkpoint_owner_id} to use R session checkpoints.",
      class = "r_session_checkpoint"
    )
  }
  invisible(NULL)
}

r_session_reject_checkpoint <- function(job, reason) {
  job$reject(tryCatch(
    abort_deputy(
      "R session checkpoint operation ended ({.val {reason}}).",
      class = "r_session_checkpoint"
    ),
    error = identity
  ))
  invisible(NULL)
}

r_session_prepare_checkpoint <- function(private, job, fresh) {
  if (identical(job$checkpoint, "capture")) {
    if (fresh) {
      abort_deputy(
        "Start an R execution before capturing its data.",
        class = "r_session_checkpoint"
      )
    }
    return(job)
  }
  if (!fresh) {
    abort_deputy(
      "Restore an R session checkpoint before starting a worker or after resetting it.",
      class = "r_session_checkpoint"
    )
  }
  job$artifact <- r_session_checkpoint_read(
    private$checkpoint_config,
    private$owner,
    job$checkpoint_id
  )
  job
}

r_session_finish_checkpoint <- function(private, job, response) {
  tryCatch(
    {
      private$check_current()
      if (!is.null(response$error)) {
        abort_deputy(
          "R session checkpoint failed: {response$error}",
          class = "r_session_checkpoint"
        )
      }
      receipt <- if (identical(job$checkpoint, "capture")) {
        r_session_checkpoint_write(
          private$checkpoint_config,
          private$owner,
          job$bindings,
          response$payload,
          job$generation
        )
      } else {
        c(job$artifact$receipt, list(restored_generation = job$generation))
      }
      job$resolve(receipt)
    },
    error = function(error) {
      job$reject(error)
      # Avoid retaining a newly started worker after a failed import.
      if (identical(job$checkpoint, "restore")) {
        private$reset("restore_failed")
      }
    }
  )
  invisible(NULL)
}
