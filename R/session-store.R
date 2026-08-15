# Session store helpers for Claude SDK compatibility.

# Default on-disk location for persisted compat sessions.
session_store_default_dir <- function() {
  file.path(tools::R_user_dir("deputy", which = "cache"), "sessions")
}

# Normalize a session store root without requiring it to exist yet.
normalize_session_store_dir <- function(path = NULL) {
  normalizePath(path %||% session_store_default_dir(), mustWork = FALSE)
}

# Ensure the session store root exists.
ensure_session_store_dir <- function(path = NULL) {
  dir <- normalize_session_store_dir(path)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dir
}

# Process-local counter used to make identifiers unique without consuming the
# caller's random-number stream.
deputy_id_state <- new.env(parent = emptyenv())
deputy_id_state$counter <- 0L

# Generate a UUID-like session identifier without adding a hard dependency or
# changing R's global RNG state.
generate_session_id <- function() {
  deputy_id_state$counter <- deputy_id_state$counter + 1L
  entropy <- paste(
    Sys.getpid(),
    format(Sys.time(), "%Y%m%d%H%M%OS9", tz = "UTC"),
    deputy_id_state$counter,
    sep = ":"
  )
  hex <- substr(
    digest::digest(entropy, algo = "sha256", serialize = FALSE),
    1L,
    32L
  )

  paste(
    substr(hex, 1L, 8L),
    substr(hex, 9L, 12L),
    substr(hex, 13L, 16L),
    substr(hex, 17L, 20L),
    substr(hex, 21L, 32L),
    sep = "-"
  )
}

validate_session_id <- function(session_id, argument = "session_id") {
  if (
    !is.character(session_id) ||
      length(session_id) != 1L ||
      is.na(session_id) ||
      !nzchar(session_id) ||
      !grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", session_id)
  ) {
    cli::cli_abort(
      paste0(
        "{.arg ",
        argument,
        "} must be one non-empty identifier containing only letters, ",
        "numbers, dots, underscores, or hyphens"
      ),
      class = c(
        "deputy_session_id_error",
        "deputy_session",
        "deputy_error"
      )
    )
  }
  session_id
}

#' Create an in-memory SDK-compatible session store
#'
#' @description
#' Creates a lightweight session store adapter with `append()`, `load()`,
#' `list_sessions()`, `list_session_summaries()`, and `delete()` methods. This
#' mirrors the Claude Agent SDK store shape while preserving deputy's R-native
#' session payloads.
#'
#' @return A `DeputySessionStore` adapter
#' @export
session_store_memory <- function() {
  sessions <- new.env(parent = emptyenv())

  structure(
    list(
      append = function(session_id, payload, metadata = list()) {
        session_id <- validate_session_id(session_id)
        records <- sessions[[session_id]] %||% list()
        records <- c(
          records,
          list(list(
            payload = payload,
            metadata = metadata,
            appended_at = Sys.time()
          ))
        )
        sessions[[session_id]] <- records
        invisible(TRUE)
      },
      load = function(session_id) {
        session_id <- validate_session_id(session_id)
        records <- sessions[[session_id]]
        if (is.null(records) || length(records) == 0) {
          abort_session_load(
            "Session not found in memory store: {.val {session_id}}",
            path = session_id
          )
        }
        records[[length(records)]]$payload
      },
      list_sessions = function() {
        sort(ls(sessions, all.names = TRUE))
      },
      list_session_summaries = function() {
        ids <- sort(ls(sessions, all.names = TRUE))
        if (length(ids) == 0) {
          return(data.frame(
            session_id = character(),
            records = integer(),
            updated_at = as.POSIXct(character()),
            stringsAsFactors = FALSE
          ))
        }
        do.call(
          rbind,
          lapply(ids, function(id) {
            records <- sessions[[id]]
            data.frame(
              session_id = id,
              records = length(records),
              updated_at = as.POSIXct(
                records[[length(records)]]$appended_at,
                tz = "UTC"
              ),
              stringsAsFactors = FALSE
            )
          })
        )
      },
      delete = function(session_id) {
        session_id <- validate_session_id(session_id)
        if (exists(session_id, envir = sessions, inherits = FALSE)) {
          rm(list = session_id, envir = sessions)
        }
        invisible(TRUE)
      },
      list_subkeys = function(session_id) {
        validate_session_id(session_id)
        character()
      }
    ),
    class = "DeputySessionStore"
  )
}

session_store_call <- function(store, method, ...) {
  if (is.null(store)) {
    return(NULL)
  }

  fun <- tryCatch(store[[method]], error = function(e) NULL)
  if (!is.function(fun)) {
    return(NULL)
  }

  fun(...)
}

session_store_append_external <- function(
  store,
  session_id,
  payload,
  metadata = list()
) {
  session_store_call(
    store,
    "append",
    session_id = session_id,
    payload = payload,
    metadata = metadata
  )
}

session_store_load_external <- function(store, session_id) {
  session_store_call(store, "load", session_id = session_id)
}

session_store_list_external <- function(store) {
  out <- session_store_call(store, "list_sessions")
  out %||% character()
}

session_store_summaries_external <- function(store) {
  out <- session_store_call(store, "list_session_summaries")
  out %||%
    data.frame(
      session_id = character(),
      records = integer(),
      updated_at = as.POSIXct(character()),
      stringsAsFactors = FALSE
    )
}

session_store_delete_external <- function(store, session_id) {
  session_store_call(store, "delete", session_id = session_id)
}

# Parse a resume timestamp from character or POSIXt input.
parse_session_resume_at <- function(at) {
  if (is.null(at)) {
    return(NULL)
  }

  if (inherits(at, "POSIXt")) {
    return(as.POSIXct(at, tz = "UTC"))
  }

  if (!is.character(at) || length(at) != 1) {
    cli::cli_abort(
      "{.arg at} must be NULL, a POSIXt value, or a length-1 character timestamp"
    )
  }

  parsed <- as.POSIXct(
    at,
    tz = "UTC",
    tryFormats = c(
      "%Y-%m-%d %H:%M:%S",
      "%Y-%m-%dT%H:%M:%S",
      "%Y-%m-%dT%H:%M:%SZ",
      "%Y-%m-%d"
    )
  )

  if (is.na(parsed)) {
    cli::cli_abort(
      "Could not parse {.arg at} as a timestamp: {.val {at}}"
    )
  }

  parsed
}

# Session-specific directory for snapshots.
session_store_session_dir <- function(root, session_id) {
  session_id <- validate_session_id(session_id)
  store_dir <- normalizePath(
    ensure_session_store_dir(root),
    mustWork = TRUE,
    winslash = "/"
  )
  session_dir <- file.path(store_dir, session_id)

  link_target <- suppressWarnings(Sys.readlink(session_dir))
  if (length(link_target) == 1L && !is.na(link_target) && nzchar(link_target)) {
    cli::cli_abort(
      "Session directory must not be a symbolic link: {.path {session_dir}}",
      class = c(
        "deputy_session_id_error",
        "deputy_session",
        "deputy_error"
      )
    )
  }
  if (file.exists(session_dir) || dir.exists(session_dir)) {
    resolved <- normalizePath(session_dir, mustWork = TRUE, winslash = "/")
    if (!is_path_within(resolved, store_dir)) {
      cli::cli_abort(
        "Session directory resolves outside its configured store",
        class = c(
          "deputy_session_id_error",
          "deputy_session",
          "deputy_error"
        )
      )
    }
  }

  session_dir
}

# List snapshot files for a session in chronological order.
session_store_snapshot_files <- function(root, session_id) {
  session_dir <- session_store_session_dir(root, session_id)
  if (!dir.exists(session_dir)) {
    return(character())
  }

  sort(
    list.files(
      session_dir,
      pattern = "\\.rds$",
      full.names = TRUE
    )
  )
}

# Build a stable snapshot filename using an incrementing index and UTC stamp.
session_store_snapshot_name <- function(index, timestamp = Sys.time()) {
  stamp <- format(
    as.POSIXct(timestamp, tz = "UTC"),
    "%Y%m%dT%H%M%SZ",
    tz = "UTC"
  )
  sprintf("%04d-%s.rds", as.integer(index), stamp)
}

# Extract the best timestamp available from a saved payload.
session_store_payload_time <- function(payload, path = NULL) {
  metadata <- payload$metadata %||% list()
  metadata$snapshot_at %||%
    metadata$saved_at %||%
    if (!is.null(path) && file.exists(path)) {
      file.info(path)$mtime[[1]]
    } else {
      NULL
    }
}

# Save a payload as the next snapshot for a session.
session_store_save_payload <- function(payload, root, session_id) {
  session_dir <- session_store_session_dir(root, session_id)
  dir.create(session_dir, recursive = TRUE, showWarnings = FALSE)

  existing <- session_store_snapshot_files(root, session_id)
  snapshot_path <- file.path(
    session_dir,
    session_store_snapshot_name(length(existing) + 1L)
  )

  tryCatch(
    {
      saveRDS(payload, snapshot_path)
      snapshot_path
    },
    error = function(e) {
      abort_session_save(
        c(
          "Failed to write compat session snapshot",
          "x" = e$message
        ),
        path = snapshot_path,
        parent = e
      )
    }
  )
}

# Choose the latest snapshot, optionally at or before a requested time.
session_store_select_snapshot <- function(root, session_id, at = NULL) {
  files <- session_store_snapshot_files(root, session_id)
  if (length(files) == 0) {
    abort_session_load(
      c(
        "Compat session not found",
        "x" = "No snapshots stored for session {.val {session_id}}"
      ),
      path = file.path(normalize_session_store_dir(root), session_id)
    )
  }

  requested_at <- parse_session_resume_at(at)

  payloads <- lapply(files, function(path) {
    payload <- tryCatch(
      readRDS(path),
      error = function(e) {
        abort_session_load(
          c(
            "Failed to read compat session snapshot",
            "x" = e$message
          ),
          path = path,
          parent = e
        )
      }
    )

    list(
      path = path,
      payload = payload,
      snapshot_at = as.POSIXct(
        session_store_payload_time(payload, path),
        tz = "UTC"
      )
    )
  })

  if (is.null(requested_at)) {
    return(payloads[[length(payloads)]])
  }

  eligible <- Filter(
    function(x) {
      !is.na(x$snapshot_at) && x$snapshot_at <= requested_at
    },
    payloads
  )

  if (length(eligible) == 0) {
    abort_session_load(
      c(
        "Compat session snapshot not found",
        "x" = paste0(
          "No snapshot for session ",
          session_id,
          " exists at or before ",
          format(requested_at, "%Y-%m-%d %H:%M:%S %Z")
        )
      ),
      path = file.path(normalize_session_store_dir(root), session_id)
    )
  }

  eligible[[length(eligible)]]
}

# Enumerate the latest snapshot per stored compat session.
session_store_list_sessions <- function(root = NULL) {
  store_dir <- normalize_session_store_dir(root)
  if (!dir.exists(store_dir)) {
    return(data.frame(
      session_id = character(),
      snapshots = integer(),
      turns = integer(),
      updated_at = as.POSIXct(character()),
      latest_snapshot = character(),
      stringsAsFactors = FALSE
    ))
  }

  session_dirs <- sort(list.dirs(
    store_dir,
    recursive = FALSE,
    full.names = TRUE
  ))
  if (length(session_dirs) == 0) {
    return(data.frame(
      session_id = character(),
      snapshots = integer(),
      turns = integer(),
      updated_at = as.POSIXct(character()),
      latest_snapshot = character(),
      stringsAsFactors = FALSE
    ))
  }

  records <- lapply(session_dirs, function(session_dir) {
    session_id <- basename(session_dir)
    files <- session_store_snapshot_files(store_dir, session_id)
    if (length(files) == 0) {
      return(NULL)
    }

    latest <- session_store_select_snapshot(store_dir, session_id)
    turns <- latest$payload$turns %||% list()

    data.frame(
      session_id = session_id,
      snapshots = length(files),
      turns = length(turns),
      updated_at = as.POSIXct(latest$snapshot_at, tz = "UTC"),
      latest_snapshot = latest$path,
      stringsAsFactors = FALSE
    )
  })

  records <- Filter(Negate(is.null), records)
  if (length(records) == 0) {
    return(data.frame(
      session_id = character(),
      snapshots = integer(),
      turns = integer(),
      updated_at = as.POSIXct(character()),
      latest_snapshot = character(),
      stringsAsFactors = FALSE
    ))
  }

  do.call(rbind, records)
}

session_store_delete_session <- function(root = NULL, session_id) {
  session_dir <- session_store_session_dir(root, session_id)
  if (dir.exists(session_dir)) {
    unlink(session_dir, recursive = TRUE, force = TRUE)
  }
  invisible(TRUE)
}
