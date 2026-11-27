# Path normalization, symlink containment, bounded raw reads, and atomic writes.

# Read a symlink target safely, returning "" for non-links or absent paths.
read_symlink_target <- function(path) {
  target <- tryCatch(
    suppressWarnings(Sys.readlink(path)),
    error = function(e) ""
  )
  if (length(target) != 1L || is.na(target)) "" else target
}

#' Check whether a path is absolute
#'
#' Recognizes POSIX, Windows drive-letter and Windows UNC paths. It doesn't
#' expand or normalize the path, so check untrusted input for traversal
#' patterns before resolving it.
#'
#' @param path Path to inspect
#' @return A length-one logical
#' @noRd
is_absolute_path <- function(path) {
  is.character(path) &&
    length(path) == 1L &&
    !is.na(path) &&
    grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)
}

#' Expand home directory and normalize a path
#'
#' Expands `~` and `~user`, then normalizes the path with forward slashes, so
#' paths written in different ways compare equal.
#'
#' @param path Path to expand
#' @return The normalized path, or `NA_character_` if `path` is empty or can't
#'   be normalized
#' @noRd
expand_and_normalize <- function(path) {
  if (is.null(path) || !is.character(path) || nchar(path) == 0) {
    return(NA_character_)
  }

  # Expand ~ and ~user patterns
  expanded <- path.expand(path)

  # Normalize the path (handles . and ..)
  normalized <- tryCatch(
    normalizePath(expanded, mustWork = FALSE, winslash = "/"),
    error = function(e) NA_character_
  )

  # Explicitly convert any remaining backslashes to forward slashes
  # (Windows paths sometimes have mixed separators that normalizePath doesn't fix)
  if (!is.na(normalized)) {
    normalized <- gsub("\\\\", "/", normalized)
    if (.Platform$OS.type == "windows") {
      # `normalizePath(..., mustWork = FALSE)` can retain an 8.3 short-name
      # spelling for the existing parent of a new file while the same
      # directory normalizes to its long spelling when it exists. Resolve the
      # longest existing prefix with `mustWork = TRUE`, then append the missing
      # suffix so containment checks compare one canonical representation.
      probe <- normalized
      missing <- character()
      while (!file.exists(probe) && !dir.exists(probe)) {
        parent <- dirname(probe)
        if (identical(parent, probe)) {
          break
        }
        missing <- c(basename(probe), missing)
        probe <- parent
      }
      if (file.exists(probe) || dir.exists(probe)) {
        canonical_prefix <- tryCatch(
          normalizePath(probe, mustWork = TRUE, winslash = "/"),
          error = function(e) NA_character_
        )
        if (!is.na(canonical_prefix)) {
          normalized <- if (length(missing) > 0L) {
            do.call(file.path, as.list(c(canonical_prefix, missing)))
          } else {
            canonical_prefix
          }
          normalized <- gsub("\\\\", "/", normalized)
        }
      }
    } else {
      normalized <- sub("^//+", "/", normalized)
    }
  }

  normalized
}

# Resolve every symbolic-link component, including links whose final target
# does not exist yet. `normalizePath(..., mustWork = FALSE)` alone does not
# follow dangling links and can therefore misclassify a future write target.
resolve_path_components <- function(path, max_depth = 40L) {
  path <- expand_and_normalize(path)
  if (is.na(path)) {
    return(NA_character_)
  }

  seen <- character()
  depth <- 0L
  repeat {
    probe <- path
    components <- character()
    repeat {
      parent <- dirname(probe)
      if (identical(parent, probe)) {
        root <- probe
        break
      }
      components <- c(basename(probe), components)
      probe <- parent
    }

    resolved <- root
    restarted <- FALSE
    for (i in seq_along(components)) {
      candidate <- file.path(resolved, components[[i]])
      link_target <- read_symlink_target(candidate)

      if (nzchar(link_target)) {
        depth <- depth + 1L
        if (depth > max_depth) {
          return(NA_character_)
        }

        target <- if (is_absolute_path(link_target)) {
          link_target
        } else {
          file.path(dirname(candidate), link_target)
        }
        remaining <- if (i < length(components)) {
          components[seq.int(i + 1L, length(components))]
        } else {
          character()
        }
        path <- if (length(remaining) > 0L) {
          do.call(file.path, as.list(c(target, remaining)))
        } else {
          target
        }
        path <- expand_and_normalize(path)
        if (is.na(path) || path %in% seen) {
          return(NA_character_)
        }
        seen <- c(seen, path)
        restarted <- TRUE
        break
      }

      resolved <- candidate
    }

    if (!restarted) {
      return(expand_and_normalize(resolved))
    }
  }
}

# Check whether normalized `path` equals `root` or lies strictly beneath it,
# using a trailing separator guard so `/allowed` never matches `/allowed-other`.
path_prefix_within <- function(
  path,
  root,
  ignore_case = identical(.Platform$OS.type, "windows")
) {
  if (isTRUE(ignore_case)) {
    path <- tolower(path)
    root <- tolower(root)
  }
  root_with_sep <- if (endsWith(root, "/")) root else paste0(root, "/")
  path_with_sep <- if (endsWith(path, "/")) path else paste0(path, "/")
  startsWith(path_with_sep, root_with_sep) ||
    identical(path, sub("/$", "", root_with_sep))
}

#' Check for path traversal patterns
#'
#' Flags a `..` path segment and a leading `~`, which could reach outside a
#' directory. Dots inside a name, as in `notes..v2.md` or `..hidden`, are not
#' flagged. A segment of two or more dots followed only by dots or spaces is
#' flagged too, because Windows trims trailing dots and spaces from names.
#' Absolute paths are not flagged; the directory containment check handles
#' them.
#'
#' @param path Path to check
#' @return `TRUE` if the path contains a traversal pattern or isn't a
#'   character value
#' @noRd
has_path_traversal <- function(path) {
  if (is.null(path) || !is.character(path)) {
    return(TRUE) # Invalid input, treat as suspicious
  }
  # Check for traversal patterns that could escape directories
  # Note: Absolute paths are allowed and checked for containment separately
  grepl("(^|[/\\\\])\\.\\.[. ]*([/\\\\]|$)", path) || # ../escape.txt
    grepl("^~", path) # Home directory expansion (~user/escape.txt)
}

#' Check a path again, then run a file operation on it
#'
#' Checks that `path` is inside `allowed_dir` immediately before running
#' `operation`, with the containment test the permission policy uses
#' (`is_path_within_permission_root()`), so both checks agree. The permission
#' check and the write are separate steps and a symbolic link can change
#' between them. Checking again narrows that window; R can't open a file
#' without following links, so it doesn't close it.
#'
#' `allowed_dir` is the directory as the policy resolved it when it was
#' created, such as `Permissions@file_write`. It is not resolved again: only
#' `path` is, so replacing the directory itself with a link to somewhere else
#' doesn't move the boundary.
#'
#' @param path Path the operation will use
#' @param allowed_dir Resolved absolute directory the path must be within, as
#'   `canonical_permission_root()` returns it
#' @param operation Function run with `path` if the check passes
#' @param ... Additional arguments passed to operation
#' @return Result of `operation`. Signals `deputy_unsafe_path` if the path is
#'   empty, contains a `..` segment or a leading `~`, or doesn't resolve
#'   inside `allowed_dir`.
#' @noRd
validate_path_at_operation <- function(path, allowed_dir, operation, ...) {
  if (!is_nonempty_string(path)) {
    abort_deputy(
      c("Invalid path", "x" = "Path must be a non-empty string"),
      class = "unsafe_path"
    )
  }

  if (has_path_traversal(path)) {
    abort_deputy(
      c(
        "Path traversal detected",
        "x" = "Path contains potentially dangerous patterns (.. or ~)",
        "i" = "Use absolute paths within the allowed directory"
      ),
      class = "unsafe_path"
    )
  }

  if (
    !is_nonempty_string(allowed_dir) ||
      !is_path_within_permission_root(path, allowed_dir)
  ) {
    abort_deputy(
      c(
        "Path outside allowed directory",
        "x" = "Path {.path {path}} is not within {.path {allowed_dir}}",
        "i" = "File operations are restricted to the allowed directory"
      ),
      class = "unsafe_path"
    )
  }

  # Perform the operation immediately after validation
  operation(path, ...)
}

# Read raw bytes from a file in chunks while enforcing a hard byte ceiling.
read_file_raw_bounded <- function(path, max_bytes = Inf, on_limit = NULL) {
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)

  chunks <- list()
  bytes_read <- 0
  repeat {
    chunk_size <- 1024L * 1024L
    if (is.finite(max_bytes)) {
      # Read at most one byte beyond the limit so growth between a size check
      # and read is detected without buffering unbounded data.
      chunk_size <- min(chunk_size, max_bytes - bytes_read + 1)
    }
    chunk <- readBin(
      connection,
      what = "raw",
      n = as.integer(chunk_size)
    )
    if (length(chunk) == 0L) {
      break
    }
    bytes_read <- bytes_read + length(chunk)
    if (bytes_read > max_bytes) {
      if (is.function(on_limit)) {
        on_limit()
      }
      cli_abort("File {.path {path}} exceeds its configured byte limit.")
    }
    chunks[[length(chunks) + 1L]] <- chunk
  }

  if (length(chunks) == 0L) raw() else do.call(c, chunks)
}

# Write a private file atomically via a temporary file in the same directory.
write_file_atomic <- function(
  path,
  write_fn,
  prefix = ".tmp-",
  fileext = "",
  mode = "0600",
  fail_if_exists = FALSE,
  allow_existing = FALSE,
  on_write_error = NULL,
  on_commit_error = NULL
) {
  temporary <- tempfile(prefix, tmpdir = dirname(path), fileext = fileext)
  on.exit(unlink(temporary), add = TRUE)
  if (is.function(on_write_error)) {
    tryCatch(write_fn(temporary), error = on_write_error)
  } else {
    write_fn(temporary)
  }
  if (!is.null(mode)) {
    Sys.chmod(temporary, mode = mode)
  }
  blocked <- isTRUE(fail_if_exists) &&
    (file.exists(path) || nzchar(read_symlink_target(path)))
  renamed <- !blocked && suppressWarnings(file.rename(temporary, path))
  if (!renamed && !(isTRUE(allow_existing) && file.exists(path))) {
    if (is.function(on_commit_error)) {
      on_commit_error()
    }
    cli_abort("Could not commit atomic write to {.path {path}}.")
  }
  invisible(path)
}

# Write JSON to a mode-0600 temporary file and return its path.
write_private_json_tempfile <- function(
  data,
  prefix = "deputy-",
  auto_unbox = TRUE,
  null = "null"
) {
  path <- tempfile(prefix, fileext = ".json")
  file.create(path)
  Sys.chmod(path, "0600")
  jsonlite::write_json(
    data,
    path,
    auto_unbox = auto_unbox,
    null = null
  )
  path
}
