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
  grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)
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
  compare_path <- path
  compare_root <- root
  if (.Platform$OS.type == "windows") {
    compare_path <- tolower(compare_path)
    compare_root <- tolower(compare_root)
  }

  if (identical(compare_path, compare_root)) {
    return(TRUE)
  }

  root_prefix <- if (endsWith(compare_root, "/")) {
    compare_root
  } else {
    paste0(compare_root, "/")
  }
  startsWith(compare_path, root_prefix)
}

file_checkpoint_relative_path <- function(path, root) {
  if (file_checkpoint_path_equal(path, root)) {
    return("")
  }

  root_prefix <- if (endsWith(root, "/")) root else paste0(root, "/")
  substring(path, nchar(root_prefix) + 1L)
}

file_checkpoint_link_target <- function(path) {
  target <- tryCatch(
    suppressWarnings(Sys.readlink(path)),
    error = function(e) ""
  )
  if (length(target) != 1L || is.na(target)) "" else target
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
  aliases <- c(
    write_file = "write",
    tool_write_file = "write",
    Write = "write",
    edit_file = "edit",
    tool_edit_file = "edit",
    Edit = "edit",
    multi_edit = "multi_edit",
    tool_multi_edit = "multi_edit",
    MultiEdit = "multi_edit",
    todo_write = "todo_write",
    tool_todo_write = "todo_write",
    TodoWrite = "todo_write"
  )

  match <- unname(aliases[tool_name])
  if (length(match) == 0L || is.na(match)) NULL else match
}

file_checkpoint_read_raw <- function(path, max_bytes = Inf, limit_path = path) {
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)

  chunks <- list()
  bytes_read <- 0
  repeat {
    chunk_size <- 1024L * 1024L
    if (is.finite(max_bytes)) {
      # Read at most one byte beyond the limit, which detects growth between
      # the initial file size check and the capture without buffering it all.
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
      file_checkpoint_abort(
        sprintf(
          "Checkpoint preimage for %s exceeds its configured byte limit.",
          limit_path
        ),
        limit_error = TRUE
      )
    }
    chunks[[length(chunks) + 1L]] <- chunk
  }

  if (length(chunks) == 0L) raw() else do.call(c, chunks)
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

FileCheckpointStore <- R6::R6Class(
  "FileCheckpointStore",

  public = list(
    initialize = function(
      root,
      max_file_bytes = 50 * 1024^2,
      max_journal_bytes = 250 * 1024^2
    ) {
      if (
        !is.character(root) ||
          length(root) != 1L ||
          is.na(root) ||
          !nzchar(root)
      ) {
        file_checkpoint_abort("`root` must be a non-empty path.")
      }
      if (!dir.exists(root)) {
        file_checkpoint_abort(sprintf(
          "Checkpoint root does not exist or is not a directory: %s",
          root
        ))
      }

      normalized <- tryCatch(
        normalizePath(root, mustWork = TRUE, winslash = "/"),
        error = function(e) NA_character_
      )
      if (is.na(normalized) || !dir.exists(normalized)) {
        file_checkpoint_abort(sprintf(
          "Could not resolve checkpoint root: %s",
          root
        ))
      }

      private$.root <- file_checkpoint_lexical_path(normalized)
      private$.max_file_bytes <- file_checkpoint_byte_limit(
        max_file_bytes,
        "max_file_bytes"
      )
      private$.max_journal_bytes <- file_checkpoint_byte_limit(
        max_journal_bytes,
        "max_journal_bytes"
      )
      private$.journal <- list()
      private$.checkpoints <- list()
      private$.pending <- new.env(parent = emptyenv())
      private$.next_checkpoint_id <- 1L
      private$.next_capture_sequence <- 1L

      invisible(self)
    },

    checkpoint = function(name, metadata = list()) {
      private$assert_no_pending("create a checkpoint")
      if (
        !is.character(name) ||
          length(name) != 1L ||
          is.na(name) ||
          !nzchar(trimws(name))
      ) {
        file_checkpoint_abort("Checkpoint `name` must be a non-empty string.")
      }
      if (is.null(metadata)) {
        metadata <- list()
      }
      if (!is.list(metadata)) {
        file_checkpoint_abort("Checkpoint `metadata` must be a list or NULL.")
      }

      existing_ids <- vapply(
        private$.checkpoints,
        function(checkpoint) checkpoint$checkpoint_id,
        character(1)
      )
      next_checkpoint_id <- private$.next_checkpoint_id
      repeat {
        if (next_checkpoint_id >= .Machine$integer.max) {
          file_checkpoint_abort(
            "Checkpoint identifier space is exhausted."
          )
        }
        checkpoint_id <- sprintf(
          "checkpoint-%06d",
          next_checkpoint_id
        )
        next_checkpoint_id <- next_checkpoint_id + 1L
        if (!checkpoint_id %in% existing_ids) {
          break
        }
      }

      checkpoint <- list(
        checkpoint_id = checkpoint_id,
        name = name,
        metadata = file_checkpoint_deep_copy(metadata),
        created_at = Sys.time(),
        event_index = length(private$.journal)
      )
      checkpoints <- c(private$.checkpoints, list(checkpoint))
      private$assert_state_within_limit(
        journal = private$.journal,
        checkpoints = checkpoints,
        pending = private$pending_entries(),
        action = sprintf("Creating checkpoint %s", checkpoint_id)
      )
      private$.checkpoints <- checkpoints
      private$.next_checkpoint_id <- next_checkpoint_id

      checkpoint_id
    },

    before_tool = function(tool_name, tool_input, tool_use_id) {
      if (
        !is.character(tool_name) || length(tool_name) != 1L || is.na(tool_name)
      ) {
        file_checkpoint_abort("`tool_name` must be a length-1 string.")
      }

      tool_kind <- file_checkpoint_mutating_tool(tool_name)
      if (is.null(tool_kind) || length(private$.checkpoints) == 0L) {
        return(invisible(FALSE))
      }

      private$validate_tool_use_id(tool_use_id)
      if (exists(tool_use_id, envir = private$.pending, inherits = FALSE)) {
        file_checkpoint_abort(sprintf(
          "A checkpoint capture is already pending for tool use %s.",
          tool_use_id
        ))
      }
      if (private$.next_capture_sequence >= .Machine$integer.max) {
        file_checkpoint_abort(
          "Checkpoint capture sequence is exhausted for this store."
        )
      }
      if (!is.list(tool_input)) {
        file_checkpoint_abort("`tool_input` must be a list.")
      }

      supplied_paths <- Filter(
        function(path) !is.null(path),
        list(path = tool_input$path, file_path = tool_input$file_path)
      )
      if (length(supplied_paths) > 1L) {
        path_values <- vapply(supplied_paths, as.character, character(1))
        if (length(unique(path_values)) > 1L) {
          file_checkpoint_abort(
            "Tool input contains conflicting `path` and `file_path` values."
          )
        }
      }

      path <- tool_input$path %||% tool_input$file_path
      if (is.null(path) && identical(tool_kind, "todo_write")) {
        path <- ".deputy/todos.json"
      }
      if (is.null(path)) {
        file_checkpoint_abort(sprintf(
          "Mutating tool %s did not provide `path` or `file_path`.",
          tool_name
        ))
      }

      resolved <- private$secure_path(path)
      if (dir.exists(resolved)) {
        file_checkpoint_abort(
          sprintf("Checkpoint target must be a file: %s", path),
          path_error = TRUE
        )
      }

      relative_path <- file_checkpoint_relative_path(resolved, private$.root)
      pending_ids <- ls(private$.pending, all.names = TRUE)
      if (length(pending_ids) > 0L) {
        pending_entries <- mget(
          pending_ids,
          envir = private$.pending,
          inherits = FALSE
        )
        pending_paths <- vapply(
          pending_entries,
          function(entry) entry$path,
          character(1)
        )
        if (relative_path %in% pending_paths) {
          file_checkpoint_abort(sprintf(
            paste0(
              "A checkpoint capture is already pending for target %s; ",
              "concurrent writes to one file are not supported."
            ),
            path
          ))
        }
      }

      existed <- file.exists(resolved)
      bytes <- if (existed) {
        size <- tryCatch(
          file.info(resolved)$size,
          error = function(e) NA_real_
        )
        if (length(size) != 1L || is.na(size) || size < 0) {
          file_checkpoint_abort(sprintf(
            "Could not determine checkpoint preimage size: %s",
            path
          ))
        }
        private$assert_capture_within_limits(path, size)

        tryCatch(
          file_checkpoint_read_raw(
            resolved,
            max_bytes = private$.max_file_bytes,
            limit_path = path
          ),
          error = function(e) {
            if (inherits(e, "deputy_file_checkpoint_error")) {
              stop(e)
            }
            file_checkpoint_abort(c(
              sprintf("Could not capture checkpoint preimage: %s", path),
              "x" = conditionMessage(e)
            ))
          }
        )
      } else {
        private$assert_capture_within_limits(path, 0)
        raw()
      }
      private$assert_capture_within_limits(path, length(bytes))

      entry <- list(
        tool_use_id = tool_use_id,
        tool_name = tool_name,
        path = relative_path,
        existed = existed,
        bytes = bytes,
        capture_sequence = private$.next_capture_sequence,
        captured_at = Sys.time()
      )
      pending <- c(private$pending_entries(), list(entry))
      names(pending)[[length(pending)]] <- tool_use_id
      private$assert_state_within_limit(
        journal = private$.journal,
        checkpoints = private$.checkpoints,
        pending = pending,
        action = sprintf("Capturing checkpoint preimage for %s", path)
      )
      assign(tool_use_id, entry, envir = private$.pending)
      private$.next_capture_sequence <- private$.next_capture_sequence + 1L

      invisible(TRUE)
    },

    after_tool = function(tool_use_id, success) {
      private$validate_tool_use_id(tool_use_id)
      if (!is.logical(success) || length(success) != 1L || is.na(success)) {
        file_checkpoint_abort("`success` must be TRUE or FALSE.")
      }
      if (!exists(tool_use_id, envir = private$.pending, inherits = FALSE)) {
        return(invisible(FALSE))
      }

      entry <- get(tool_use_id, envir = private$.pending, inherits = FALSE)
      changed <- isTRUE(success)
      if (!changed) {
        verification_error <- NULL
        changed <- tryCatch(
          private$entry_changed(entry),
          error = function(error) {
            verification_error <<- error
            TRUE
          }
        )
        if (!is.null(verification_error)) {
          entry$verification_error <- conditionMessage(verification_error)
          entry$verification_error_class <- class(verification_error)
        }
      }

      pending <- private$pending_entries(exclude = tool_use_id)

      # Validate and append before releasing the pending capture. If allocation
      # or limit enforcement fails, the original remains recoverable in
      # `.pending`.
      if (changed) {
        journal <- c(private$.journal, list(entry))
        private$assert_state_within_limit(
          journal = journal,
          checkpoints = private$.checkpoints,
          pending = pending,
          action = sprintf("Finalizing checkpoint capture %s", tool_use_id)
        )
        private$.journal <- journal
      }
      rm(list = tool_use_id, envir = private$.pending)

      invisible(changed)
    },

    finalize_pending = function() {
      pending_ids <- ls(private$.pending, all.names = TRUE)
      if (length(pending_ids) == 0L) {
        return(invisible(0L))
      }

      finalized <- 0L
      for (tool_use_id in pending_ids) {
        self$after_tool(tool_use_id, success = FALSE)
        finalized <- finalized + 1L
      }

      invisible(finalized)
    },

    rewind = function(checkpoint_id) {
      private$assert_no_pending("rewind files")
      if (
        !is.character(checkpoint_id) ||
          length(checkpoint_id) != 1L ||
          is.na(checkpoint_id) ||
          !nzchar(checkpoint_id)
      ) {
        file_checkpoint_abort("`checkpoint_id` must be a non-empty string.")
      }

      checkpoint_ids <- vapply(
        private$.checkpoints,
        function(checkpoint) checkpoint$checkpoint_id,
        character(1)
      )
      checkpoint_position <- match(checkpoint_id, checkpoint_ids)
      if (is.na(checkpoint_position)) {
        file_checkpoint_abort(sprintf(
          "Unknown or invalidated checkpoint: %s",
          checkpoint_id
        ))
      }

      checkpoint <- private$.checkpoints[[checkpoint_position]]
      event_count <- length(private$.journal)
      event_indices <- if (checkpoint$event_index < event_count) {
        seq.int(checkpoint$event_index + 1L, event_count)
      } else {
        integer()
      }

      rewind_indices <- if (length(event_indices) > 0L) {
        capture_sequences <- vapply(
          event_indices,
          function(index) private$.journal[[index]]$capture_sequence,
          integer(1)
        )
        event_indices[order(capture_sequences, decreasing = TRUE)]
      } else {
        integer()
      }

      restore_paths <- lapply(rewind_indices, function(index) {
        private$validated_entry_path(private$.journal[[index]])
      })

      for (i in seq_along(rewind_indices)) {
        entry <- private$.journal[[rewind_indices[[i]]]]
        private$restore_entry(entry, restore_paths[[i]])
      }

      if (checkpoint$event_index == 0L) {
        private$.journal <- list()
      } else {
        private$.journal <- private$.journal[
          seq_len(checkpoint$event_index)
        ]
      }
      private$.checkpoints <- private$.checkpoints[
        seq_len(checkpoint_position)
      ]

      list(
        checkpoint_id = checkpoint_id,
        name = checkpoint$name,
        restored_changes = length(event_indices)
      )
    },

    list_checkpoints = function() {
      if (length(private$.checkpoints) == 0L) {
        return(data.frame(
          checkpoint_id = character(),
          name = character(),
          created_at = as.POSIXct(character(), tz = "UTC"),
          event_index = integer(),
          metadata = I(list()),
          stringsAsFactors = FALSE
        ))
      }

      data.frame(
        checkpoint_id = vapply(
          private$.checkpoints,
          function(checkpoint) checkpoint$checkpoint_id,
          character(1)
        ),
        name = vapply(
          private$.checkpoints,
          function(checkpoint) checkpoint$name,
          character(1)
        ),
        created_at = as.POSIXct(
          vapply(
            private$.checkpoints,
            function(checkpoint) as.numeric(checkpoint$created_at),
            numeric(1)
          ),
          origin = "1970-01-01",
          tz = "UTC"
        ),
        event_index = vapply(
          private$.checkpoints,
          function(checkpoint) as.integer(checkpoint$event_index),
          integer(1)
        ),
        metadata = I(lapply(
          private$.checkpoints,
          function(checkpoint) file_checkpoint_deep_copy(checkpoint$metadata)
        )),
        stringsAsFactors = FALSE
      )
    },

    export_state = function() {
      private$assert_no_pending("export checkpoint state")
      file_checkpoint_deep_copy(list(
        version = 2L,
        root = private$.root,
        journal = private$.journal,
        checkpoints = private$.checkpoints,
        next_checkpoint_id = private$.next_checkpoint_id,
        next_capture_sequence = private$.next_capture_sequence
      ))
    },

    restore_state = function(state) {
      private$assert_no_pending("restore checkpoint state")
      private$validate_state(state)

      private$.journal <- file_checkpoint_deep_copy(state$journal)
      private$.checkpoints <- file_checkpoint_deep_copy(state$checkpoints)
      private$.next_checkpoint_id <- as.integer(state$next_checkpoint_id)
      private$.next_capture_sequence <- as.integer(
        state$next_capture_sequence
      )
      private$.pending <- new.env(parent = emptyenv())

      invisible(self)
    }
  ),

  private = list(
    .root = NULL,
    .journal = NULL,
    .checkpoints = NULL,
    .pending = NULL,
    .next_checkpoint_id = NULL,
    .next_capture_sequence = NULL,
    .max_file_bytes = NULL,
    .max_journal_bytes = NULL,

    pending_entries = function(exclude = character()) {
      pending_ids <- ls(private$.pending, all.names = TRUE)
      pending_ids <- setdiff(pending_ids, exclude)
      if (length(pending_ids) == 0L) {
        return(list())
      }
      mget(pending_ids, envir = private$.pending, inherits = FALSE)
    },

    record_storage_bytes = function(record) {
      as.double(length(serialize(record, NULL, xdr = FALSE)))
    },

    state_storage_bytes = function(journal, checkpoints, pending) {
      records <- c(journal, checkpoints, unname(pending))
      if (length(records) == 0L) {
        return(0)
      }
      sum(vapply(records, private$record_storage_bytes, numeric(1)))
    },

    assert_state_within_limit = function(
      journal,
      checkpoints,
      pending,
      action
    ) {
      total <- private$state_storage_bytes(journal, checkpoints, pending)
      if (total > private$.max_journal_bytes) {
        file_checkpoint_abort(
          sprintf(
            paste0(
              "%s would grow serialized checkpoint state to %s bytes, ",
              "exceeding `max_journal_bytes` (%s)."
            ),
            action,
            format(total, scientific = FALSE, trim = TRUE),
            format(
              private$.max_journal_bytes,
              scientific = FALSE,
              trim = TRUE
            )
          ),
          limit_error = TRUE
        )
      }
      invisible(NULL)
    },

    assert_capture_within_limits = function(path, bytes) {
      bytes <- as.double(bytes)
      if (bytes > private$.max_file_bytes) {
        file_checkpoint_abort(
          sprintf(
            paste0(
              "Checkpoint preimage for %s is %s bytes, exceeding ",
              "`max_file_bytes` (%s)."
            ),
            path,
            format(bytes, scientific = FALSE, trim = TRUE),
            format(
              private$.max_file_bytes,
              scientific = FALSE,
              trim = TRUE
            )
          ),
          limit_error = TRUE
        )
      }

      projected <- private$state_storage_bytes(
        private$.journal,
        private$.checkpoints,
        private$pending_entries()
      ) +
        bytes
      if (projected > private$.max_journal_bytes) {
        file_checkpoint_abort(
          sprintf(
            paste0(
              "Capturing %s would grow checkpoint state beyond %s bytes, ",
              "exceeding `max_journal_bytes` (%s)."
            ),
            path,
            format(projected, scientific = FALSE, trim = TRUE),
            format(
              private$.max_journal_bytes,
              scientific = FALSE,
              trim = TRUE
            )
          ),
          limit_error = TRUE
        )
      }

      invisible(NULL)
    },

    assert_journal_within_limits = function(journal, checkpoints) {
      sizes <- vapply(
        journal,
        function(entry) {
          if (!is.list(entry) || !is.raw(entry$bytes)) {
            return(NA_real_)
          }
          length(entry$bytes)
        },
        numeric(1)
      )
      oversized <- which(!is.na(sizes) & sizes > private$.max_file_bytes)
      if (length(oversized) > 0L) {
        entry <- journal[[oversized[[1]]]]
        file_checkpoint_abort(
          sprintf(
            paste0(
              "Checkpoint preimage for %s is %s bytes, exceeding ",
              "`max_file_bytes` (%s)."
            ),
            entry$path %||% "an unknown path",
            format(
              sizes[[oversized[[1]]]],
              scientific = FALSE,
              trim = TRUE
            ),
            format(
              private$.max_file_bytes,
              scientific = FALSE,
              trim = TRUE
            )
          ),
          limit_error = TRUE
        )
      }

      private$assert_state_within_limit(
        journal = journal,
        checkpoints = checkpoints,
        pending = list(),
        action = "Restoring checkpoint state"
      )

      invisible(NULL)
    },

    validate_tool_use_id = function(tool_use_id) {
      if (
        !is.character(tool_use_id) ||
          length(tool_use_id) != 1L ||
          is.na(tool_use_id) ||
          !nzchar(tool_use_id)
      ) {
        file_checkpoint_abort("`tool_use_id` must be a non-empty string.")
      }
      invisible(NULL)
    },

    assert_no_pending = function(action) {
      pending_ids <- ls(private$.pending, all.names = TRUE)
      if (length(pending_ids) > 0L) {
        file_checkpoint_abort(sprintf(
          "Cannot %s while tool captures are pending: %s",
          action,
          paste(pending_ids, collapse = ", ")
        ))
      }
      invisible(NULL)
    },

    secure_path = function(path) {
      if (
        !is.character(path) ||
          length(path) != 1L ||
          is.na(path) ||
          !nzchar(path)
      ) {
        file_checkpoint_abort(
          "Checkpoint path must be a non-empty string.",
          path_error = TRUE
        )
      }

      if (
        .Platform$OS.type == "windows" &&
          grepl("^[A-Za-z]:", path) &&
          !file_checkpoint_is_absolute(path)
      ) {
        file_checkpoint_abort(
          sprintf("Drive-relative checkpoint paths are not allowed: %s", path),
          path_error = TRUE
        )
      }

      candidate <- if (file_checkpoint_is_absolute(path)) {
        path
      } else {
        file.path(private$.root, path)
      }
      candidate <- file_checkpoint_existing_prefix(candidate)

      if (!file_checkpoint_path_within(candidate, private$.root)) {
        file_checkpoint_abort(
          sprintf(
            "Checkpoint path is outside the configured root: %s",
            path
          ),
          path_error = TRUE
        )
      }

      relative <- file_checkpoint_relative_path(candidate, private$.root)
      components <- if (nzchar(relative)) {
        strsplit(relative, "/", fixed = TRUE)[[1]]
      } else {
        character()
      }
      private$resolve_components(components)
    },

    resolve_components = function(components, seen = character()) {
      resolved <- private$.root
      for (component in components) {
        next_path <- file_checkpoint_lexical_path(file.path(
          resolved,
          component
        ))
        if (!file_checkpoint_path_within(next_path, private$.root)) {
          file_checkpoint_abort(
            sprintf("Checkpoint path escaped its root at: %s", next_path),
            path_error = TRUE
          )
        }

        link_target <- file_checkpoint_link_target(next_path)

        if (nzchar(link_target)) {
          if (next_path %in% seen || length(seen) >= 40L) {
            file_checkpoint_abort(
              sprintf("Symlink cycle in checkpoint path: %s", next_path),
              path_error = TRUE
            )
          }

          target <- if (file_checkpoint_is_absolute(link_target)) {
            link_target
          } else {
            file.path(dirname(next_path), link_target)
          }
          target <- file_checkpoint_existing_prefix(target)
          if (!file_checkpoint_path_within(target, private$.root)) {
            file_checkpoint_abort(
              sprintf(
                "Checkpoint path follows a symlink outside its root: %s",
                next_path
              ),
              path_error = TRUE
            )
          }

          target_relative <- file_checkpoint_relative_path(
            target,
            private$.root
          )
          target_components <- if (nzchar(target_relative)) {
            strsplit(target_relative, "/", fixed = TRUE)[[1]]
          } else {
            character()
          }
          resolved <- private$resolve_components(
            target_components,
            seen = c(seen, next_path)
          )
        } else {
          resolved <- next_path
        }
      }

      resolved
    },

    validated_entry_path = function(entry) {
      resolved <- private$secure_path(entry$path)
      resolved_relative <- file_checkpoint_relative_path(
        resolved,
        private$.root
      )
      if (!identical(resolved_relative, entry$path)) {
        file_checkpoint_abort(
          sprintf(
            "Checkpoint path now resolves to a different file: %s",
            entry$path
          ),
          path_error = TRUE
        )
      }
      if (dir.exists(resolved)) {
        file_checkpoint_abort(
          sprintf("Checkpoint target became a directory: %s", entry$path),
          path_error = TRUE
        )
      }
      resolved
    },

    entry_changed = function(entry) {
      path <- private$validated_entry_path(entry)
      exists_now <- file.exists(path)
      if (!identical(exists_now, isTRUE(entry$existed))) {
        return(TRUE)
      }
      if (!exists_now) {
        return(FALSE)
      }

      current_size <- tryCatch(
        file.info(path)$size,
        error = function(e) NA_real_
      )
      if (length(current_size) != 1L || is.na(current_size)) {
        file_checkpoint_abort(sprintf(
          "Could not determine failed tool checkpoint size: %s",
          entry$path
        ))
      }
      if (!identical(as.double(current_size), as.double(length(entry$bytes)))) {
        return(TRUE)
      }

      current_bytes <- tryCatch(
        file_checkpoint_read_raw(
          path,
          max_bytes = length(entry$bytes),
          limit_path = entry$path
        ),
        error = function(e) {
          file_checkpoint_abort(c(
            sprintf(
              "Could not verify failed tool checkpoint: %s",
              entry$path
            ),
            "x" = conditionMessage(e)
          ))
        }
      )
      !identical(current_bytes, entry$bytes)
    },

    restore_entry = function(entry, path) {
      if (isTRUE(entry$existed)) {
        tryCatch(
          file_checkpoint_write_raw(path, entry$bytes),
          error = function(e) {
            if (inherits(e, "deputy_file_checkpoint_error")) {
              stop(e)
            }
            file_checkpoint_abort(c(
              sprintf("Could not restore checkpoint file: %s", entry$path),
              "x" = conditionMessage(e)
            ))
          }
        )
      } else if (
        file.exists(path) || nzchar(file_checkpoint_link_target(path))
      ) {
        status <- unlink(path, recursive = FALSE, force = FALSE)
        if (
          status != 0L ||
            file.exists(path) ||
            nzchar(file_checkpoint_link_target(path))
        ) {
          file_checkpoint_abort(sprintf(
            "Could not remove file created after checkpoint: %s",
            entry$path
          ))
        }
      }

      invisible(NULL)
    },

    validate_state = function(state) {
      if (!is.list(state) || !identical(state$version, 2L)) {
        file_checkpoint_abort("Unsupported or malformed checkpoint state.")
      }
      if (
        !is.character(state$root) ||
          length(state$root) != 1L ||
          !file_checkpoint_path_equal(
            file_checkpoint_lexical_path(state$root),
            private$.root
          )
      ) {
        file_checkpoint_abort(
          "Checkpoint state belongs to a different filesystem root.",
          path_error = TRUE
        )
      }
      if (!is.list(state$journal) || !is.list(state$checkpoints)) {
        file_checkpoint_abort("Checkpoint state journal is malformed.")
      }
      if (
        !is.numeric(state$next_checkpoint_id) ||
          length(state$next_checkpoint_id) != 1L ||
          is.na(state$next_checkpoint_id) ||
          state$next_checkpoint_id < 1 ||
          state$next_checkpoint_id > .Machine$integer.max ||
          state$next_checkpoint_id != as.integer(state$next_checkpoint_id)
      ) {
        file_checkpoint_abort("Checkpoint state counter is malformed.")
      }
      if (
        !is.numeric(state$next_capture_sequence) ||
          length(state$next_capture_sequence) != 1L ||
          is.na(state$next_capture_sequence) ||
          state$next_capture_sequence < 1 ||
          state$next_capture_sequence > .Machine$integer.max ||
          state$next_capture_sequence != as.integer(state$next_capture_sequence)
      ) {
        file_checkpoint_abort(
          "Checkpoint state capture counter is malformed."
        )
      }

      for (entry in state$journal) {
        private$validate_state_entry(entry)
      }
      capture_sequences <- vapply(
        state$journal,
        function(entry) entry$capture_sequence,
        integer(1)
      )
      if (anyDuplicated(capture_sequences)) {
        file_checkpoint_abort(
          "Checkpoint state contains duplicate capture sequences."
        )
      }
      if (
        length(capture_sequences) > 0L &&
          max(capture_sequences) >= state$next_capture_sequence
      ) {
        file_checkpoint_abort(
          "Checkpoint state capture counter does not follow its journal."
        )
      }

      checkpoint_ids <- character()
      prior_event_index <- 0L
      for (checkpoint in state$checkpoints) {
        if (
          !is.list(checkpoint) ||
            !is.character(checkpoint$checkpoint_id) ||
            length(checkpoint$checkpoint_id) != 1L ||
            !nzchar(checkpoint$checkpoint_id) ||
            !is.character(checkpoint$name) ||
            length(checkpoint$name) != 1L ||
            !nzchar(checkpoint$name) ||
            !is.list(checkpoint$metadata) ||
            !inherits(checkpoint$created_at, "POSIXt") ||
            !is.numeric(checkpoint$event_index) ||
            length(checkpoint$event_index) != 1L ||
            is.na(checkpoint$event_index) ||
            checkpoint$event_index < prior_event_index ||
            checkpoint$event_index > length(state$journal) ||
            checkpoint$event_index != as.integer(checkpoint$event_index)
        ) {
          file_checkpoint_abort("Checkpoint state contains a malformed marker.")
        }
        if (checkpoint$checkpoint_id %in% checkpoint_ids) {
          file_checkpoint_abort("Checkpoint state contains duplicate IDs.")
        }

        event_index <- as.integer(checkpoint$event_index)
        if (event_index > 0L && event_index < length(capture_sequences)) {
          before_sequences <- capture_sequences[seq_len(event_index)]
          after_sequences <- capture_sequences[seq.int(
            event_index + 1L,
            length(capture_sequences)
          )]
          if (max(before_sequences) >= min(after_sequences)) {
            file_checkpoint_abort(
              paste0(
                "Checkpoint state capture order crosses a checkpoint ",
                "marker."
              )
            )
          }
        }

        checkpoint_ids <- c(checkpoint_ids, checkpoint$checkpoint_id)
        prior_event_index <- event_index
      }

      private$assert_journal_within_limits(
        state$journal,
        state$checkpoints
      )

      invisible(NULL)
    },

    validate_state_entry = function(entry) {
      if (
        !is.list(entry) ||
          !is.character(entry$tool_use_id) ||
          length(entry$tool_use_id) != 1L ||
          !nzchar(entry$tool_use_id) ||
          !is.character(entry$tool_name) ||
          length(entry$tool_name) != 1L ||
          !is.character(entry$path) ||
          length(entry$path) != 1L ||
          !nzchar(entry$path) ||
          file_checkpoint_is_absolute(entry$path) ||
          !is.logical(entry$existed) ||
          length(entry$existed) != 1L ||
          is.na(entry$existed) ||
          !is.raw(entry$bytes) ||
          !is.numeric(entry$capture_sequence) ||
          length(entry$capture_sequence) != 1L ||
          is.na(entry$capture_sequence) ||
          entry$capture_sequence < 1 ||
          entry$capture_sequence >= .Machine$integer.max ||
          entry$capture_sequence != as.integer(entry$capture_sequence) ||
          !inherits(entry$captured_at, "POSIXt")
      ) {
        file_checkpoint_abort(
          "Checkpoint state contains a malformed journal entry."
        )
      }

      lexical <- file_checkpoint_lexical_path(file.path(
        private$.root,
        entry$path
      ))
      expected_relative <- file_checkpoint_relative_path(
        lexical,
        private$.root
      )
      if (!identical(expected_relative, gsub("\\\\", "/", entry$path))) {
        file_checkpoint_abort(
          "Checkpoint state contains a non-canonical path.",
          path_error = TRUE
        )
      }
      private$validated_entry_path(entry)

      invisible(NULL)
    }
  ),

  cloneable = FALSE
)
