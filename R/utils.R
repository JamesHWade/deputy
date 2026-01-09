# Internal utility functions for deputy

#' Check if a path is within a directory (secure)
#'
#' This function handles both existing and non-existing paths correctly.
#' For non-existing paths, it normalizes the existing portion to handle
#' symlinks properly (important on macOS where /var -> /private/var).
#'
#' @param path Path to check
#' @param dir Directory to check against
#' @return Logical indicating if path is within dir
#' @noRd
is_path_within <- function(path, dir) {
  # First check for path traversal attempts in the raw path
  if (grepl("\\.\\.", path)) {
    # Path contains .. which could be a traversal attempt
    # Even if it resolves to within dir, this is suspicious
    return(FALSE)
  }

  # Helper: normalize a path, resolving symlinks for the existing portion
  normalize_path <- function(p) {
    # First try direct normalization (works if path exists)
    normalized <- tryCatch(
      normalizePath(p, mustWork = FALSE, winslash = "/"),
      error = function(e) NA_character_
    )

    # If the path doesn't exist, normalizePath won't resolve symlinks
    # in the non-existing portion. Find the longest existing prefix.
    if (!file.exists(p)) {
      parts <- strsplit(p, "/")[[1]]
      # Reconstruct path piece by piece to find existing prefix
      for (i in seq_along(parts)) {
        prefix <- paste(parts[1:i], collapse = "/")
        if (nchar(prefix) == 0) {
          prefix <- "/"
        }
        if (!file.exists(prefix)) {
          # Previous prefix was the last existing one
          if (i > 1) {
            existing <- paste(parts[1:(i - 1)], collapse = "/")
            if (nchar(existing) == 0) {
              existing <- "/"
            }
            remaining <- paste(parts[i:length(parts)], collapse = "/")
            existing_normalized <- tryCatch(
              normalizePath(existing, mustWork = TRUE, winslash = "/"),
              error = function(e) existing
            )
            return(paste(existing_normalized, remaining, sep = "/"))
          }
          break
        }
      }
    }
    normalized
  }

  # Normalize both paths
  path <- normalize_path(path)
  dir <- normalize_path(dir)

  # If normalization failed, deny access
  if (is.na(path) || is.na(dir)) {
    return(FALSE)
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

#' Format cost as dollars
#'
#' @param cost Numeric cost value
#' @return Formatted string
#' @noRd
format_cost <- function(cost) {
  if (is.null(cost) || is.na(cost)) {
    return("$0.00")
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
  if (!inherits(tool, "ToolDef")) {
    return(default)
  }

  annotations <- tool@annotations
  if (is.null(annotations)) {
    return(default)
  }

  annotations[[annotation]] %||% default
}

#' Check if a tool is read-only based on annotations
#'
#' @param tool A tool definition
#' @return Logical indicating if tool is read-only
#' @noRd
is_tool_readonly <- function(tool) {
  get_tool_annotation(tool, "read_only_hint", default = FALSE)
}

#' Check if a tool is destructive based on annotations
#'
#' @param tool A tool definition
#' @return Logical indicating if tool is destructive
#' @noRd
is_tool_destructive <- function(tool) {
  get_tool_annotation(tool, "destructive_hint", default = FALSE)
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

#' Safe list access with default
#'
#' @param x List to access
#' @param name Name of element
#' @param default Default value if not found
#' @return The element or default
#' @noRd
list_get <- function(x, name, default = NULL) {
  if (is.null(x) || !name %in% names(x)) {
    return(default)
  }
  x[[name]]
}
