# Internal persistence for approval continuations. Revisions are immutable so a
# reader sees either the preceding record or the complete next record. The OS
# lock protects writers for the entire execution, including its external effects.
approval_store_locks <- new.env(parent = emptyenv())

approval_store_abort <- function(message, reason = "invalid_store") {
  abort_deputy(message, class = "approval_error", reason = reason)
}

approval_store_limit <- function(max_bytes) {
  if (
    !is.numeric(max_bytes) ||
      length(max_bytes) != 1L ||
      is.na(max_bytes) ||
      !is.finite(max_bytes) ||
      max_bytes < 1 ||
      max_bytes > 50 * 1024^2
  ) {
    approval_store_abort(
      "Approval storage limit must be between 1 byte and 50 MiB."
    )
  }
  max_bytes
}

approval_store_record <- function(record) {
  if (
    !is.list(record) ||
      is.object(record) ||
      anyDuplicated(names(record)) ||
      !all(c("schema_version", "id", "status") %in% names(record)) ||
      !identical(record$schema_version, 1L) ||
      !is.character(record$id) ||
      length(record$id) != 1L ||
      is.na(record$id) ||
      !grepl("^[A-Za-z0-9_]+$", record$id) ||
      !is.character(record$status) ||
      length(record$status) != 1L ||
      is.na(record$status) ||
      !nzchar(record$status)
  ) {
    approval_store_abort("Invalid approval storage record.")
  }
  invisible(record)
}

approval_store_path <- function(path) {
  if (
    !is.character(path) ||
      length(path) != 1L ||
      is.na(path) ||
      !nzchar(path) ||
      !dir.exists(path)
  ) {
    approval_store_abort("Approval directory does not exist.")
  }
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

approval_store_files <- function(path) {
  files <- list.files(path, pattern = "^revision-", full.names = TRUE)
  if (
    !all(grepl("^revision-[0-9]{10}\\.rds$", basename(files))) ||
      any(dir.exists(files))
  ) {
    approval_store_abort("Approval revision filenames are invalid.")
  }
  sort(files)
}

approval_store_envelope <- function(path) {
  files <- approval_store_files(path)
  if (!length(files)) {
    approval_store_abort("Approval directory has no committed record.")
  }
  sizes <- file.info(files)$size
  if (anyNA(sizes) || sum(sizes) > 50 * 1024^2) {
    approval_store_abort("Approval revisions exceed the storage limit.")
  }
  latest <- files[[length(files)]]
  envelope <- tryCatch(
    readRDS(latest),
    error = function(e) {
      approval_store_abort("Cannot read the committed approval record.")
    }
  )
  revision <- as.numeric(sub(
    "^revision-([0-9]{10})\\.rds$",
    "\\1",
    basename(latest)
  ))
  if (
    !is.list(envelope) ||
      is.object(envelope) ||
      !identical(
        names(envelope),
        c("format_version", "revision", "max_bytes", "checksum", "payload")
      ) ||
      !identical(envelope$format_version, 1L) ||
      !identical(envelope$revision, revision) ||
      revision < 1 ||
      !is.raw(envelope$payload) ||
      !is.character(envelope$checksum) ||
      length(envelope$checksum) != 1L ||
      is.na(envelope$checksum) ||
      !identical(
        digest::digest(envelope$payload, algo = "sha256", serialize = FALSE),
        envelope$checksum
      )
  ) {
    approval_store_abort(
      "Committed approval record failed integrity validation."
    )
  }
  limit <- approval_store_limit(envelope$max_bytes)
  if (sum(sizes) > limit || length(envelope$payload) > limit) {
    approval_store_abort("Approval revisions exceed the storage limit.")
  }
  envelope
}

approval_store_decode <- function(envelope, path) {
  force(envelope)
  record <- tryCatch(
    unserialize(envelope$payload),
    error = function(e) {
      approval_store_abort("Cannot decode the committed approval record.")
    }
  )
  approval_store_record(record)
  if (!identical(record$id, basename(path))) {
    approval_store_abort("Approval record does not match its directory.")
  }
  record
}

approval_store_read <- function(path) {
  path <- approval_store_path(path)
  approval_store_decode(approval_store_envelope(path), path)
}

approval_store_lock <- function(path) {
  path <- approval_store_path(path)
  if (exists(path, envir = approval_store_locks, inherits = FALSE)) {
    approval_store_abort("Approval continuation is already locked.", "busy")
  }
  handle <- tryCatch(
    filelock::lock(file.path(path, ".lock"), timeout = 0),
    error = function(e) {
      approval_store_abort(
        "Cannot lock the approval continuation.",
        "lock_failed"
      )
    }
  )
  if (is.null(handle)) {
    approval_store_abort("Approval continuation is already locked.", "busy")
  }
  Sys.chmod(file.path(path, ".lock"), mode = "0600")
  state <- new.env(parent = emptyenv())
  state$pid <- Sys.getpid()
  state$handle <- handle
  # Serialization clears external pointers. Keep a null handle for detecting
  # tokens whose filelock handle was released outside our unlock helper.
  state$released_handle <- unserialize(serialize(handle, NULL))
  assign(path, state, envir = approval_store_locks)
  list(path = path, handle = handle, state = state)
}

approval_store_locked <- function(path, lock) {
  if (
    !is.list(lock) ||
      !identical(lock$path, path) ||
      !is.environment(lock$state) ||
      !identical(lock$state$pid, Sys.getpid()) ||
      !exists(path, envir = approval_store_locks, inherits = FALSE) ||
      !identical(get(path, envir = approval_store_locks), lock$state) ||
      !identical(lock$handle, lock$state$handle) ||
      identical(lock$handle, lock$state$released_handle)
  ) {
    approval_store_abort(
      "A held lock for this approval is required.",
      "invalid_lock"
    )
  }
  invisible(TRUE)
}

approval_store_unlock <- function(lock) {
  if (
    is.list(lock) &&
      is.character(lock$path) &&
      length(lock$path) == 1L &&
      !is.na(lock$path) &&
      exists(lock$path, envir = approval_store_locks, inherits = FALSE) &&
      identical(get(lock$path, envir = approval_store_locks), lock$state)
  ) {
    if (!identical(lock$handle, lock$state$released_handle)) {
      approval_store_locked(lock$path, lock)
      filelock::unlock(lock$handle)
    }
    rm(list = lock$path, envir = approval_store_locks)
  }
  invisible(NULL)
}

approval_store_commit <- function(path, record, revision, max_bytes) {
  approval_store_record(record)
  if (!identical(record$id, basename(path))) {
    approval_store_abort("Approval record does not match its directory.")
  }
  payload <- tryCatch(
    serialize(record, NULL, version = 3),
    error = function(e) {
      approval_store_abort("Cannot serialize the approval record.")
    }
  )
  if (length(payload) > max_bytes) {
    approval_store_abort(
      "Approval revisions exceed the storage limit.",
      "size_limit"
    )
  }
  envelope <- list(
    format_version = 1L,
    revision = as.numeric(revision),
    max_bytes = max_bytes,
    checksum = digest::digest(payload, algo = "sha256", serialize = FALSE),
    payload = payload
  )
  target <- file.path(path, sprintf("revision-%010.0f.rds", revision))
  temporary <- tempfile(".pending-", tmpdir = path)
  on.exit(unlink(temporary), add = TRUE)
  tryCatch(
    {
      connection <- file(temporary, open = "wb")
      tryCatch(
        {
          Sys.chmod(temporary, mode = "0600")
          saveRDS(envelope, connection, version = 3)
        },
        finally = close(connection)
      )
      files <- list.files(
        path,
        all.files = TRUE,
        full.names = TRUE,
        no.. = TRUE
      )
      sizes <- file.info(files)$size
      if (anyNA(sizes) || sum(sizes) > max_bytes) {
        approval_store_abort(
          "Approval revisions exceed the storage limit.",
          "size_limit"
        )
      }
      if (file.exists(target) || !approval_store_rename(temporary, target)) {
        approval_store_abort(
          "Cannot commit the approval revision.",
          "commit_failed"
        )
      }
    },
    error = function(e) {
      if (inherits(e, "deputy_approval_error")) {
        rlang::cnd_signal(e)
      }
      approval_store_abort(
        "Cannot commit the approval revision.",
        "commit_failed"
      )
    }
  )
  invisible(path)
}

approval_store_rename <- function(from, to) {
  file.rename(from, to)
}

approval_store_create <- function(directory, record, max_bytes = 50 * 1024^2) {
  approval_store_record(record)
  max_bytes <- approval_store_limit(max_bytes)
  directory <- approval_store_path(directory)
  path <- file.path(directory, record$id)
  if (!dir.create(path, mode = "0700", showWarnings = FALSE)) {
    approval_store_abort(
      "Approval directory already exists or cannot be created.",
      "create_failed"
    )
  }
  committed <- FALSE
  lock <- NULL
  on.exit(
    {
      if (!is.null(lock)) {
        approval_store_unlock(lock)
      }
      if (!committed) unlink(path, recursive = TRUE)
    },
    add = TRUE
  )
  path <- approval_store_path(path)
  lock <- approval_store_lock(path)
  approval_store_commit(path, record, 1, max_bytes)
  committed <- TRUE
  path
}

approval_store_write <- function(path, record, lock, max_bytes = 50 * 1024^2) {
  path <- approval_store_path(path)
  approval_store_locked(path, lock)
  envelope <- approval_store_envelope(path)
  approval_store_decode(envelope, path)
  max_bytes <- min(approval_store_limit(max_bytes), envelope$max_bytes)
  if (envelope$revision >= 9999999999) {
    approval_store_abort("Approval revision limit reached.")
  }
  approval_store_commit(path, record, envelope$revision + 1, max_bytes)
}
