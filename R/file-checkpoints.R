#' @include file-checkpoint-validation.R
NULL

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

    before_tool = function(tool_name, tool_input, tool_call_id) {
      if (
        !is.character(tool_name) || length(tool_name) != 1L || is.na(tool_name)
      ) {
        file_checkpoint_abort("`tool_name` must be a length-1 string.")
      }

      tool_kind <- file_checkpoint_mutating_tool(tool_name)
      if (is.null(tool_kind) || length(private$.checkpoints) == 0L) {
        return(invisible(FALSE))
      }

      private$validate_tool_call_id(tool_call_id)
      if (exists(tool_call_id, envir = private$.pending, inherits = FALSE)) {
        file_checkpoint_abort(sprintf(
          "A checkpoint capture is already pending for tool call %s.",
          tool_call_id
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

      path <- tool_input$path
      if (is.null(path)) {
        file_checkpoint_abort(sprintf(
          "Mutating tool %s did not provide `path`.",
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
        tool_call_id = tool_call_id,
        tool_name = tool_name,
        path = relative_path,
        existed = existed,
        bytes = bytes,
        capture_sequence = private$.next_capture_sequence,
        captured_at = Sys.time()
      )
      pending <- c(private$pending_entries(), list(entry))
      names(pending)[[length(pending)]] <- tool_call_id
      private$assert_state_within_limit(
        journal = private$.journal,
        checkpoints = private$.checkpoints,
        pending = pending,
        action = sprintf("Capturing checkpoint preimage for %s", path)
      )
      assign(tool_call_id, entry, envir = private$.pending)
      private$.next_capture_sequence <- private$.next_capture_sequence + 1L

      invisible(TRUE)
    },

    after_tool = function(tool_call_id, success) {
      private$validate_tool_call_id(tool_call_id)
      if (!is.logical(success) || length(success) != 1L || is.na(success)) {
        file_checkpoint_abort("`success` must be TRUE or FALSE.")
      }
      if (!exists(tool_call_id, envir = private$.pending, inherits = FALSE)) {
        return(invisible(FALSE))
      }

      entry <- get(tool_call_id, envir = private$.pending, inherits = FALSE)
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

      pending <- private$pending_entries(exclude = tool_call_id)

      # Validate and append before releasing the pending capture. If allocation
      # or limit enforcement fails, the original remains recoverable in
      # `.pending`.
      if (changed) {
        journal <- c(private$.journal, list(entry))
        private$assert_state_within_limit(
          journal = journal,
          checkpoints = private$.checkpoints,
          pending = pending,
          action = sprintf("Finalizing checkpoint capture %s", tool_call_id)
        )
        private$.journal <- journal
      }
      rm(list = tool_call_id, envir = private$.pending)

      invisible(changed)
    },

    finalize_pending = function() {
      pending_ids <- ls(private$.pending, all.names = TRUE)
      if (length(pending_ids) == 0L) {
        return(invisible(0L))
      }

      finalized <- 0L
      for (tool_call_id in pending_ids) {
        self$after_tool(tool_call_id, success = FALSE)
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
        version = 3L,
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

  private = c(
    list(
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

      validate_tool_call_id = function(tool_call_id) {
        if (
          !is.character(tool_call_id) ||
            length(tool_call_id) != 1L ||
            is.na(tool_call_id) ||
            !nzchar(tool_call_id)
        ) {
          file_checkpoint_abort("`tool_call_id` must be a non-empty string.")
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
            sprintf(
              "Drive-relative checkpoint paths are not allowed: %s",
              path
            ),
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
        if (
          !identical(as.double(current_size), as.double(length(entry$bytes)))
        ) {
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
      }
    ),
    deputy_file_checkpoint_validation_methods()
  ),

  cloneable = FALSE
)
