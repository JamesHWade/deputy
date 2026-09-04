# Internal utility functions for deputy

# Read an optional value without collapsing absence and read failures.
#
# @param reader Zero-argument function that reads the value.
# @param validator Optional predicate for validating a present value.
# @return A list with `status`, `value`, and `error`. Status is one of
#   `"present"`, `"absent"`, `"invalid"`, or `"unreadable"`.
# @noRd
read_optional_value <- function(reader, validator = NULL) {
  attempt <- tryCatch(
    list(value = reader(), error = NULL),
    error = function(error) list(value = NULL, error = error)
  )

  if (!is.null(attempt$error)) {
    return(list(
      status = "unreadable",
      value = NULL,
      error = attempt$error
    ))
  }

  if (is.null(attempt$value)) {
    return(list(status = "absent", value = NULL, error = NULL))
  }

  if (!is.null(validator) && !isTRUE(validator(attempt$value))) {
    return(list(
      status = "invalid",
      value = attempt$value,
      error = NULL
    ))
  }

  list(status = "present", value = attempt$value, error = NULL)
}

# @noRd
is_nonempty_string <- function(value) {
  is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    nzchar(trimws(value))
}

# Read an optional provider tool call ID and report malformed values.
# @noRd
read_provider_tool_call_id <- function(reader, source, object) {
  id <- read_optional_value(reader, validator = is_nonempty_string)

  if (identical(id$status, "present")) {
    return(id$value)
  }
  if (identical(id$status, "absent")) {
    return(NULL)
  }

  if (identical(id$status, "unreadable")) {
    cli_warn(c(
      "Failed to read provider tool call ID from {source}.",
      "i" = "Source class: {.cls {class(object)}}.",
      "x" = conditionMessage(id$error)
    ))
  } else {
    cli_warn(c(
      "Ignoring invalid provider tool call ID from {source}.",
      "i" = "Expected one non-empty string; got {.cls {class(id$value)}}."
    ))
  }

  NULL
}

#' Resolve symlinks in a path (follows symlink chains)
#'
#' Recursively resolves symlinks to get the final target path.
#' Handles symlink chains up to a maximum depth to prevent infinite loops.
#'
#' @param path Path to resolve
#' @param max_depth Maximum recursion depth (default 20)
#' @return Resolved path, or `NA_character_` if path doesn't exist or resolution
#'   fails. Callers should check for NA before using the result.
#' @noRd
resolve_symlinks <- function(path, max_depth = 20) {
  if (max_depth <= 0) {
    # Prevent infinite loops in circular symlinks
    return(NA_character_)
  }

  # Return NA if path doesn't exist - don't return unverified paths
  if (!file.exists(path)) {
    return(NA_character_)
  }

  info <- tryCatch(
    file.info(path),
    error = function(e) NULL
  )

  # Return NA on any failure (permission denied, network issues, etc.)
  if (is.null(info) || is.na(info$isdir)) {
    return(NA_character_)
  }

  # Use Sys.readlink to check if it's a symlink
  link_target <- tryCatch(
    Sys.readlink(path),
    error = function(e) ""
  )

  if (is.na(link_target) || nchar(link_target) == 0) {
    # Not a symlink, return the path
    return(path)
  }

  # It's a symlink - resolve the target
  # If target is relative, make it absolute relative to the symlink's directory
  if (!startsWith(link_target, "/")) {
    parent_dir <- dirname(path)
    link_target <- file.path(parent_dir, link_target)
  }

  # Recursively resolve the target (may be another symlink)
  resolve_symlinks(link_target, max_depth - 1)
}

#' Expand home directory and normalize a path
#'
#' Expands ~ and ~user patterns, then normalizes the path.
#' This prevents bypass attempts using home directory references.
#'
#' @param path Path to expand
#' @return Expanded and normalized path
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
      link_target <- tryCatch(
        suppressWarnings(Sys.readlink(candidate)),
        error = function(e) ""
      )
      if (length(link_target) != 1L) {
        return(NA_character_)
      }
      if (is.na(link_target)) {
        # Sys.readlink() reports NA for an ordinary nonexistent component.
        # Once a component is absent, later components cannot be links yet.
        link_target <- ""
      }

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

#' Check if a path is within a directory (secure)
#'
#' This function handles both existing and non-existing paths correctly.
#' It resolves symlinks, expands home directory references, and normalizes
#' paths before comparison.
#'
#' **Security Note:** This function is subject to TOCTOU (time-of-check-time-of-use)
#' race conditions. The filesystem state may change between the check and actual
#' file operations. For critical security:
#' 1. Use `validate_path_at_operation()` which performs check immediately before I/O
#' 2. Call this function as close to the file operation as possible
#' 3. Consider sandboxed execution environments for high-security scenarios
#'
#' @param path Path to check
#' @param dir Directory to check against
#' @return Logical indicating if path is within dir
#' @noRd
is_path_within <- function(path, dir) {
  # Early validation
  if (is.null(path) || !is.character(path) || nchar(path) == 0) {
    return(FALSE)
  }
  if (is.null(dir) || !is.character(dir) || nchar(dir) == 0) {
    return(FALSE)
  }

  # First check for path traversal patterns in the raw path
  # This catches attempts even if they would resolve to within dir
  if (grepl("\\.\\.", path)) {
    return(FALSE)
  }

  # Normalize both paths while resolving every link component, including a
  # dangling final link whose target may be created by the pending operation.
  path <- resolve_path_components(path)
  dir <- resolve_path_components(dir)

  # If normalization failed, deny access
  if (is.na(path) || is.na(dir)) {
    return(FALSE)
  }

  if (.Platform$OS.type == "windows") {
    path <- tolower(path)
    dir <- tolower(dir)
  }

  # Ensure directory has trailing separator for accurate prefix matching
  # This prevents /allowed matching /allowed-other
  if (!endsWith(dir, "/")) {
    dir <- paste0(dir, "/")
  }

  # Check if path starts with dir, or path equals dir (without trailing /)
  path_with_sep <- if (!endsWith(path, "/")) paste0(path, "/") else path
  startsWith(path_with_sep, dir) || identical(path, sub("/$", "", dir))
}

#' Check for path traversal attempts
#'
#' Detects patterns that might be used to escape from a restricted directory.
#' Note: This does NOT block absolute paths - those are handled by is_path_within().
#'
#' @param path Path to check
#' @return Logical indicating if path contains traversal patterns
#' @noRd
has_path_traversal <- function(path) {
  if (is.null(path) || !is.character(path)) {
    return(TRUE) # Invalid input, treat as suspicious
  }
  # Check for traversal patterns that could escape directories
  # Note: Absolute paths are allowed and checked by is_path_within()
  grepl("\\.\\.", path) || # Parent directory references (../escape.txt)
    grepl("^~", path) # Home directory expansion (~user/escape.txt)
}

#' Check whether a path is absolute
#'
#' Recognizes POSIX, Windows drive-letter, and Windows UNC paths. This helper
#' deliberately does not expand or normalize the path; callers that accept
#' untrusted input should reject traversal syntax before resolving it.
#'
#' @param path Path to inspect
#' @return A length-one logical
#' @noRd
is_absolute_path <- function(path) {
  is.character(path) &&
    length(path) == 1 &&
    !is.na(path) &&
    grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)
}

#' Validate path and perform operation atomically (TOCTOU mitigation)
#'
#' This function reduces the TOCTOU window by performing the path validation
#' immediately before the file operation. It should be used instead of
#' separating the check from the operation.
#'
#' @param path Path to validate
#' @param allowed_dir Directory the path must be within (NULL to skip check)
#' @param operation Function to perform if validation passes. Receives the
#'   normalized path as its first argument.
#' @param ... Additional arguments passed to operation
#' @return Result of operation, or throws error if validation fails
#' @noRd
validate_path_at_operation <- function(path, allowed_dir, operation, ...) {
  # Validate path format

  if (is.null(path) || !is.character(path) || nchar(path) == 0) {
    cli_abort(c(
      "Invalid path",
      "x" = "Path must be a non-empty string"
    ))
  }

  # Check for path traversal patterns
  if (has_path_traversal(path)) {
    cli_abort(c(
      "Path traversal detected",
      "x" = "Path contains potentially dangerous patterns (.. or ~)",
      "i" = "Use absolute paths within the allowed directory"
    ))
  }

  # Expand and normalize the path
  normalized <- expand_and_normalize(path)
  if (is.na(normalized)) {
    cli_abort(c(
      "Path normalization failed",
      "x" = "Could not normalize path: {.path {path}}"
    ))
  }

  # If allowed_dir is specified, validate containment
  if (!is.null(allowed_dir)) {
    # Re-resolve symlinks RIGHT BEFORE the check (minimize TOCTOU window)
    if (file.exists(normalized)) {
      resolved <- resolve_symlinks(normalized)
      if (!is.na(resolved)) {
        normalized <- resolved
      }
    }

    if (!is_path_within(normalized, allowed_dir)) {
      cli_abort(c(
        "Path outside allowed directory",
        "x" = "Path {.path {path}} is not within {.path {allowed_dir}}",
        "i" = "File operations are restricted to the allowed directory"
      ))
    }
  }

  # Perform the operation immediately after validation
  operation(normalized, ...)
}

#' Secure file write with atomic path validation
#'
#' Writes content to a file with path validation performed immediately
#' before the write operation to minimize TOCTOU window.
#'
#' @param path Path to write to
#' @param content Content to write
#' @param allowed_dir Directory the path must be within (NULL to skip check)
#' @param append Whether to append to existing file
#' @return Invisible NULL on success, throws error on failure
#' @noRd
secure_write_file <- function(
  path,
  content,
  allowed_dir = NULL,
  append = FALSE
) {
  validate_path_at_operation(
    path = path,
    allowed_dir = allowed_dir,
    operation = function(normalized_path) {
      # Create directory if needed
      dir <- dirname(normalized_path)
      if (!dir.exists(dir)) {
        dir.create(dir, recursive = TRUE)
      }

      # Perform the write immediately after validation
      if (append) {
        cat(content, file = normalized_path, append = TRUE)
      } else {
        writeLines(content, normalized_path)
      }
      invisible(NULL)
    }
  )
}

#' Secure file read with atomic path validation
#'
#' Reads content from a file with path validation performed immediately
#' before the read operation to minimize TOCTOU window.
#'
#' @param path Path to read from
#' @param allowed_dir Directory the path must be within (NULL to skip check)
#' @return File contents as character vector
#' @noRd
secure_read_file <- function(path, allowed_dir = NULL) {
  validate_path_at_operation(
    path = path,
    allowed_dir = allowed_dir,
    operation = function(normalized_path) {
      if (!file.exists(normalized_path)) {
        cli_abort(c(
          "File not found",
          "x" = "File does not exist: {.path {normalized_path}}"
        ))
      }
      paste(readLines(normalized_path, warn = FALSE), collapse = "\n")
    }
  )
}

#' Format cost as dollars
#'
#' @param cost Numeric cost value
#' @return Formatted string
#' @noRd
format_cost <- function(cost) {
  if (is.null(cost) || is.na(cost)) {
    return("unknown")
  }
  sprintf("$%.4f", cost)
}

#' Get tool annotation value safely
#'
#' @param tool A tool definition
#' @param annotation Name of the annotation
#' @param default Default value if not found
#' @return The annotation value or default
#' @noRd
get_tool_annotation <- function(tool, annotation, default = NULL) {
  if (!inherits(tool, "ellmer::ToolDef")) {
    return(default)
  }

  annotations <- tryCatch(
    tool@annotations,
    error = function(e) {
      cli::cli_warn(c(
        "Failed to access tool annotations",
        "i" = "Tool class: {.cls {class(tool)}}",
        "x" = e$message
      ))
      NULL
    }
  )

  if (is.null(annotations)) {
    return(default)
  }

  annotations[[annotation]] %||% default
}

#' Truncate a string to a maximum length
#'
#' @param x String to truncate
#' @param max_length Maximum length
#' @param suffix Suffix to add if truncated
#' @return Truncated string
#' @noRd
truncate_string <- function(x, max_length = 100, suffix = "...") {
  if (is.null(x) || nchar(x) <= max_length) {
    return(x)
  }
  paste0(substr(x, 1, max_length - nchar(suffix)), suffix)
}

#' Validate that an object is an ellmer Chat
#'
#' @param x Object to validate
#' @param arg_name Name of the argument (for error messages)
#' @noRd
validate_chat <- function(x, arg_name = "chat") {
  if (!inherits(x, "Chat")) {
    cli_abort(c(
      "Invalid {.arg {arg_name}} argument",
      "x" = "Expected an ellmer Chat object",
      "i" = "Create one with {.fn ellmer::chat} or provider-specific functions like {.fn ellmer::chat_openai}"
    ))
  }
  invisible(x)
}

#' Parse Markdown frontmatter
#'
#' @param path Path to a Markdown file
#' @return List with `meta` (list) and `body` (character)
#' @keywords internal
parse_markdown_frontmatter <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (length(lines) == 0) {
    return(list(meta = list(), body = ""))
  }

  if (trimws(lines[1]) != "---") {
    return(list(meta = list(), body = paste(lines, collapse = "\n")))
  }

  end_idx <- which(trimws(lines[-1]) == "---")
  if (length(end_idx) == 0) {
    return(list(meta = list(), body = paste(lines, collapse = "\n")))
  }

  # Adjust for offset (lines[-1])
  end_idx <- end_idx[1] + 1
  meta_lines <- lines[2:(end_idx - 1)]
  body_lines <- lines[(end_idx + 1):length(lines)]

  rlang::check_installed("yaml", reason = "to parse skill YAML frontmatter")
  meta <- tryCatch(
    yaml::read_yaml(text = paste(meta_lines, collapse = "\n")),
    error = function(e) {
      cli::cli_warn(c(
        "Failed to parse YAML frontmatter in {.path {path}}",
        "x" = e$message
      ))
      list()
    }
  )

  list(
    meta = meta %||% list(),
    body = paste(body_lines, collapse = "\n")
  )
}
