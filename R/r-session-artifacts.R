# Keep producer documents out of saved turns and out of the tool's model
# content. The host stores the bytes under its tenant/Agent/session scope.
r_session_artifact_limit <- 8L * 1024L^2

r_session_artifact_abort <- function(message, parent = NULL) {
  abort_deputy(
    message,
    class = "r_session_artifact",
    parent = parent,
    .envir = parent.frame()
  )
}

r_session_artifact_config <- function(directory, owner_id, owner) {
  if (is.null(directory) && is.null(owner_id)) {
    return(NULL)
  }
  if (!is_nonempty_string(directory) || !dir.exists(directory)) {
    r_session_artifact_abort(
      "{.arg artifact_dir} must be an existing directory."
    )
  }
  if (!is_nonempty_string(owner_id) || nchar(owner_id, "bytes") > 4096L) {
    r_session_artifact_abort(
      "{.arg artifact_owner_id} must be one nonempty string of at most 4096 bytes."
    )
  }
  identity <- jsonlite::toJSON(unname(c(
    owner_id,
    owner$agent_id,
    owner$session_id
  )))
  list(
    directory = normalizePath(directory, winslash = "/", mustWork = TRUE),
    scope = r_session_artifact_digest(as.character(identity))
  )
}

r_session_artifact_digest <- function(bytes) {
  digest::digest(bytes, algo = "sha256", serialize = FALSE)
}

r_session_artifact_path <- function(config, id) {
  if (is.null(config)) {
    r_session_artifact_abort(
      "Configure {.arg artifact_dir} and {.arg artifact_owner_id} to use R session artifacts."
    )
  }
  if (!is_nonempty_string(id) || !grepl("^r_artifact_[0-9a-f]{64}$", id)) {
    r_session_artifact_abort("The R session artifact ID is invalid.")
  }
  directory <- normalizePath(config$directory, winslash = "/", mustWork = FALSE)
  if (!dir.exists(directory) || !identical(directory, config$directory)) {
    r_session_artifact_abort("The R session artifact directory has changed.")
  }
  file.path(directory, paste0(config$scope, "-", id, ".html"))
}

r_session_artifact_read <- function(config, id) {
  path <- r_session_artifact_path(config, id)
  if (!utils::file_test("-f", path) || nzchar(read_symlink_target(path))) {
    r_session_artifact_abort(
      "The R session artifact is unavailable to this owner."
    )
  }
  html <- tryCatch(
    suppressWarnings(read_file_raw_bounded(path, r_session_artifact_limit)),
    error = function(error) {
      r_session_artifact_abort("Could not read the R session artifact.", error)
    }
  )
  if (!identical(id, paste0("r_artifact_", r_session_artifact_digest(html)))) {
    r_session_artifact_abort(
      "The R session artifact failed its integrity check."
    )
  }
  html
}

r_session_artifact_write <- function(config, html) {
  if (
    !is.raw(html) || !length(html) || length(html) > r_session_artifact_limit
  ) {
    r_session_artifact_abort("The R session artifact exceeds its byte bounds.")
  }
  sha256 <- r_session_artifact_digest(html)
  id <- paste0("r_artifact_", sha256)
  path <- r_session_artifact_path(config, id)
  if (!file.exists(path) && !nzchar(read_symlink_target(path))) {
    write_file_atomic(
      path,
      write_fn = function(temporary) {
        connection <- file(temporary, "wb")
        tryCatch(writeBin(html, connection), finally = close(connection))
      },
      prefix = ".r-artifact-",
      allow_existing = TRUE,
      on_write_error = function(error) {
        r_session_artifact_abort(
          "Could not write the R session artifact.",
          error
        )
      },
      on_commit_error = function() {
        r_session_artifact_abort("Could not publish the R session artifact.")
      }
    )
  }
  r_session_artifact_read(config, id)
  list(id = id, media_type = "text/html", bytes = length(html), sha256 = sha256)
}

r_session_commit_artifacts <- function(segments, config) {
  lapply(segments, function(segment) {
    if (!identical(segment$type, "artifact")) {
      return(segment)
    }
    receipt <- tryCatch(
      r_session_artifact_write(config, segment$html),
      error = identity
    )
    segment$html <- NULL
    if (inherits(receipt, "error")) {
      segment$text <- paste(
        segment$text,
        "Interactive document could not be stored.",
        sep = "\n"
      )
      segment$artifact$storage <- "failed"
    } else {
      segment$artifact <- c(receipt, segment$artifact)
    }
    segment
  })
}

r_session_artifact_document <- function(html) {
  # The policy comes before the producer's scripts. The host frame gives
  # the document an opaque origin even when it appears in a Shiny app.
  policy <- paste(
    "default-src 'none'; script-src 'unsafe-inline' data: blob:;",
    "style-src 'unsafe-inline' data:; img-src data: blob:; font-src data:;",
    "base-uri 'none'; form-action 'none'"
  )
  html <- sub("^[[:space:]]*<!doctype[^>]*>", "", html, ignore.case = TRUE)
  paste0(
    '<!doctype html><meta http-equiv="Content-Security-Policy" content="',
    policy,
    '">',
    html
  )
}

r_session_artifact_frame <- function(config, id) {
  html <- rawToChar(r_session_artifact_read(config, id))
  Encoding(html) <- "UTF-8"
  htmltools::tags$iframe(
    title = "Interactive R result",
    sandbox = "allow-scripts",
    referrerpolicy = "no-referrer",
    srcdoc = r_session_artifact_document(html),
    style = "width: 100%; min-height: 28rem; border: 0;"
  )
}
