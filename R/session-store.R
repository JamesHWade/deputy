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

# Generate a UUID-like session identifier without adding a hard dependency.
generate_session_id <- function() {
  random_hex <- function(n) {
    paste(sample(c(0:9, letters[1:6]), n, replace = TRUE), collapse = "")
  }

  paste(
    random_hex(8),
    random_hex(4),
    random_hex(4),
    random_hex(4),
    random_hex(12),
    sep = "-"
  )
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
  file.path(ensure_session_store_dir(root), session_id)
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
