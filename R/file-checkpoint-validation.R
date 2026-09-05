# Internal R6 methods for file checkpoint validation.
# R6 binds these methods to the same self/private environments as the facade.
deputy_file_checkpoint_validation_methods <- function(
  self = NULL,
  private = NULL
) {
  list(
    validate_state = function(state) {
      if (!is.list(state) || !identical(state$version, 3L)) {
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
          !is.character(entry$tool_call_id) ||
          length(entry$tool_call_id) != 1L ||
          !nzchar(entry$tool_call_id) ||
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
  )
}
