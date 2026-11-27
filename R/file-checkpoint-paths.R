# File checkpoint journal used by agent tool callbacks.

file_checkpoint_abort <- function(
  message,
  path_error = FALSE,
  limit_error = FALSE
) {
  classes <- "deputy_file_checkpoint_error"
  if (isTRUE(path_error)) {
    classes <- c("deputy_file_checkpoint_path_error", classes)
  }
  if (isTRUE(limit_error)) {
    classes <- c("deputy_file_checkpoint_limit_error", classes)
  }

  cli::cli_abort(message, class = classes)
}

file_checkpoint_byte_limit <- function(value, argument) {
  if (
    !is.numeric(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.finite(value) ||
      value < 0
  ) {
    file_checkpoint_abort(sprintf(
      "`%s` must be one finite, non-negative number of bytes.",
      argument
    ))
  }

  as.double(value)
}

file_checkpoint_deep_copy <- function(x) {
  tryCatch(
    unserialize(serialize(x, NULL, version = 3)),
    error = function(e) {
      file_checkpoint_abort(c(
        "Checkpoint state must be serializable.",
        "x" = conditionMessage(e)
      ))
    }
  )
}

file_checkpoint_is_absolute <- function(path) {
  is_absolute_path(path)
}

# Normalize dot segments without requiring the target path to exist.
file_checkpoint_lexical_path <- function(path) {
  path <- path.expand(path)
  path <- gsub("\\\\", "/", path)

  prefix <- ""
  rest <- path
  if (grepl("^[A-Za-z]:/", rest)) {
    prefix <- paste0(toupper(substr(rest, 1L, 1L)), ":/")
    rest <- substring(rest, 4L)
  } else if (startsWith(rest, "//")) {
    prefix <- "//"
    rest <- sub("^/+", "", rest)
  } else if (startsWith(rest, "/")) {
    prefix <- "/"
    rest <- sub("^/+", "", rest)
  }

  parts <- strsplit(rest, "/", fixed = TRUE)[[1]]
  stack <- character()
  for (part in parts) {
    if (!nzchar(part) || identical(part, ".")) {
      next
    }

    if (identical(part, "..")) {
      if (
        length(stack) > 0L &&
          !identical(stack[[length(stack)]], "..")
      ) {
        stack <- stack[-length(stack)]
      } else if (!nzchar(prefix)) {
        stack <- c(stack, part)
      }
      next
    }

    stack <- c(stack, part)
  }

  body <- paste(stack, collapse = "/")
  if (identical(prefix, "/")) {
    return(if (nzchar(body)) paste0("/", body) else "/")
  }
  if (identical(prefix, "//")) {
    return(if (nzchar(body)) paste0("//", body) else "//")
  }
  if (nzchar(prefix)) {
    return(paste0(prefix, body))
  }
  if (nzchar(body)) body else "."
}

file_checkpoint_path_equal <- function(x, y) {
  if (.Platform$OS.type == "windows") {
    identical(tolower(x), tolower(y))
  } else {
    identical(x, y)
  }
}

file_checkpoint_path_within <- function(path, root) {
  path_prefix_within(path, root)
}

file_checkpoint_relative_path <- function(path, root) {
  if (file_checkpoint_path_equal(path, root)) {
    return("")
  }

  root_prefix <- if (endsWith(root, "/")) root else paste0(root, "/")
  substring(path, nchar(root_prefix) + 1L)
}

file_checkpoint_link_target <- function(path) {
  read_symlink_target(path)
}

# Resolve filesystem aliases in the longest existing prefix of a path.
file_checkpoint_existing_prefix <- function(path) {
  path <- file_checkpoint_lexical_path(path)
  probe <- path
  missing <- character()

  while (!file.exists(probe) && !dir.exists(probe)) {
    parent <- dirname(probe)
    if (identical(parent, probe)) {
      return(path)
    }
    missing <- c(basename(probe), missing)
    probe <- parent
  }

  resolved <- tryCatch(
    normalizePath(probe, mustWork = TRUE, winslash = "/"),
    error = function(e) probe
  )
  if (length(missing) > 0L) {
    resolved <- do.call(file.path, as.list(c(resolved, missing)))
  }
  file_checkpoint_lexical_path(resolved)
}

file_checkpoint_mutating_tool <- function(tool_name) {
  tool_kinds <- c(
    write_file = "write",
    edit_file = "edit",
    multi_edit = "multi_edit"
  )

  match <- unname(tool_kinds[tool_name])
  if (length(match) == 0L || is.na(match)) NULL else match
}

file_checkpoint_read_raw <- function(path, max_bytes = Inf, limit_path = path) {
  read_file_raw_bounded(
    path,
    max_bytes = max_bytes,
    on_limit = function() {
      file_checkpoint_abort(
        sprintf(
          "Checkpoint preimage for %s exceeds its configured byte limit.",
          limit_path
        ),
        limit_error = TRUE
      )
    }
  )
}

file_checkpoint_write_raw <- function(path, bytes) {
  parent <- dirname(path)
  if (!dir.exists(parent)) {
    created <- dir.create(parent, recursive = TRUE, showWarnings = FALSE)
    if (!isTRUE(created) && !dir.exists(parent)) {
      file_checkpoint_abort(sprintf(
        "Could not create checkpoint parent directory: %s",
        parent
      ))
    }
  }

  connection <- file(path, open = "wb")
  on.exit(close(connection), add = TRUE)
  if (length(bytes) > 0L) {
    writeBin(bytes, connection)
  }
  invisible(NULL)
}
