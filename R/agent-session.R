# Internal R6 methods for agent session.
# R6 binds these methods to the same self/private environments as the facade.
deputy_agent_session_methods <- function(self = NULL, private = NULL) {
  list(
    build_session_payload = function() {
      snapshot <- private$.conversation_state$snapshot(private$.chat)
      session <- c(
        list(schema_version = 3L),
        snapshot,
        list(
          tool_result_envelopes = collect_tool_result_envelopes(
            private$.context_policy,
            private$.session_id
          ),
          run_context = private$snapshot_run_context(),
          appended_hook_context_hashes = private$appended_hook_context_hashes,
          file_checkpoint_state = if (is.null(private$.file_checkpoints)) {
            NULL
          } else {
            private$.file_checkpoints$export_state()
          },
          metadata = list(
            saved_at = Sys.time(),
            deputy_version = as.character(utils::packageVersion("deputy")),
            provider = self$provider(),
            session_id = private$.session_id,
            agent_id = private$.agent_id,
            agent_name = private$.agent_name
          )
        )
      )
      # Subagent tool calls shown in the conversation, beside the turns the
      # model reads; a conversation that showed none has no field.
      session$activity <- activity_saved_entries(self)
      session
    },

    restore_session_payload = function(session, source = NULL) {
      if (!is.list(session)) {
        abort_session_load(
          "Invalid session file - expected a named list",
          path = source
        )
      }

      if (!"schema_version" %in% names(session)) {
        abort_session_load(
          c(
            "Invalid session file - missing required fields",
            "x" = "Missing: schema_version"
          ),
          path = source
        )
      }

      if (!identical(session$schema_version, 3L)) {
        abort_session_load(
          "Unsupported session schema - expected version 3",
          path = source
        )
      }

      # ConversationState$prepare_restore() checks the conversation fields.
      required_fields <- c(
        "tool_result_envelopes",
        "run_context",
        "appended_hook_context_hashes",
        "file_checkpoint_state",
        "metadata"
      )
      missing <- setdiff(required_fields, names(session))
      if (length(missing) > 0) {
        abort_session_load(
          c(
            "Invalid session file - missing required fields",
            "x" = "Missing: {.val {missing}}"
          ),
          path = source
        )
      }

      metadata <- session$metadata
      if (!is.list(metadata)) {
        abort_session_load(
          "Invalid session file - metadata must be a list",
          path = source
        )
      }
      prepared <- private$.conversation_state$prepare_restore(session, source)

      restored_tool_results <- tryCatch(
        validate_tool_result_envelopes(
          session$tool_result_envelopes,
          metadata$session_id
        ),
        error = function(error) {
          abort_session_load(
            c(
              "Invalid session file - saved tool results failed validation",
              "x" = error$message
            ),
            path = source,
            parent = error
          )
        }
      )

      restored_run_context <- tryCatch(
        {
          saved_context <- normalize_run_context(
            session$run_context,
            argument = "session$run_context"
          )
          merge_run_context(private$.run_context, saved_context)
        },
        deputy_run_context_error = function(error) {
          abort_session_load(
            c(
              "Invalid session file - run_context is unsafe",
              "x" = error$message
            ),
            path = source,
            parent = error
          )
        }
      )

      restored_hashes <- tryCatch(
        {
          as.character(session$appended_hook_context_hashes)
        },
        error = function(error) {
          abort_session_load(
            c(
              "Invalid session file - hook context hashes are malformed",
              "x" = error$message
            ),
            path = source,
            parent = error
          )
        }
      )
      # Checked against the turns being restored, before anything changes.
      restored_activity <- activity_session_overlay(session, source)
      # Validate recoverable filesystem state before mutating any conversation
      # state so a rejected cross-root or oversized journal leaves the receiver
      # unchanged.
      restored_checkpoints <- NULL
      if (!is.null(private$.file_checkpoints)) {
        restored_checkpoints <- private$new_file_checkpoint_store()
        if (!is.null(session$file_checkpoint_state)) {
          restored_checkpoints$restore_state(session$file_checkpoint_state)
        }
      }

      previous_tools <- private$.chat$get_tools()
      previous_reader_registered <- private$.tool_result_reader_registered
      tool_result_replacement <- NULL
      tryCatch(
        {
          tool_result_replacement <- begin_tool_result_envelope_replacement(
            restored_tool_results,
            policy = private$.context_policy,
            source_session_id = metadata$session_id,
            target_session_id = private$.session_id
          )
          private$.conversation_state$restore(
            private$.chat,
            prepared,
            install = function() {
              if (length(restored_tool_results) > 0L) {
                private$ensure_tool_result_reader()
              }
              commit_tool_result_envelope_replacement(
                tool_result_replacement
              )
              invisible(NULL)
            }
          )
        },
        error = function(error) {
          try(private$.chat$set_tools(previous_tools), silent = TRUE)
          private$.tool_result_reader_registered <- previous_reader_registered
          if (!is.null(tool_result_replacement)) {
            try(
              rollback_tool_result_envelope_replacement(
                tool_result_replacement
              ),
              silent = TRUE
            )
          }
          abort_session_load(
            c(
              "Failed to restore session conversation state",
              "x" = error$message
            ),
            path = source,
            parent = error
          )
        }
      )

      # Session data is conversational state, not control-plane authority.
      # Constructor permissions and the workspace root remain immutable even
      # when the payload came from outside the process. Checkpoint state is
      # restored only when the receiver explicitly enabled checkpointing;
      # FileCheckpointStore also requires an exact configured-root match.
      if (!is.null(restored_checkpoints)) {
        private$.file_checkpoints <- restored_checkpoints
      }

      private$.run_context <- restored_run_context
      private$last_run_context <- clone_run_context(restored_run_context)
      private$appended_hook_context_hashes <- restored_hashes
      # Saved usage describes the saving Agent's prompt, tools and any later
      # rewrite, none of which a load restores, so none of it is reused.
      private$.usage_stale_turns <- length(private$.chat$get_turns())
      private$reset_frame_snapshots()
      # Activity shown for the previous conversation doesn't belong to this
      # one.
      private$.activity_overlay <- restored_activity
      activity_reset(self)
    }
  )
}

# Executable ToolDefs can close over processes and host resources. Saved turns
# retain the request as evidence; hosts rebuild the executable registry.
portable_session_turns <- function(turns) {
  strip_tool <- function(content) {
    if (inherits(content, "ellmer::ContentToolRequest")) {
      content@tool <- NULL
    } else if (inherits(content, "ellmer::ContentToolResult")) {
      if (!is.null(content@request)) {
        content@request <- strip_tool(content@request)
      }
    }
    content
  }
  lapply(turns, function(turn) {
    turn@contents <- lapply(turn@contents, strip_tool)
    turn
  })
}

# Classes a plain tool error keeps: the base ones, whose message is the
# `message` field; ellmer's tool rejection; and Shiny's custom errors, which
# shinychat shows even when Shiny sanitizes error messages.
portable_error_classes <- c(
  "ellmer_tool_reject",
  "shiny.custom.error",
  "error",
  "warning",
  "message",
  "condition"
)

# Tool errors as plain conditions with their message. An error raised inside
# Shiny carries its call stacks as attributes, and rlang errors carry a
# backtrace; chat history stores turns as JSON and can't read those calls back,
# so a reopened conversation would lose the whole turn. Other classes go too,
# since their message methods may read fields a plain condition doesn't have.
portable_tool_errors <- function(turns) {
  plain <- function(content) {
    if (
      !inherits(content, "ellmer::ContentToolResult") ||
        !inherits(content@error, "condition")
    ) {
      return(content)
    }
    error <- content@error
    content@error <- structure(
      list(message = conditionMessage(error), call = NULL),
      class = union(
        intersect(class(error), portable_error_classes),
        "condition"
      )
    )
    content
  }
  lapply(turns, function(turn) {
    if (!inherits(turn, "ellmer::Turn")) {
      return(turn)
    }
    turn@contents <- lapply(turn@contents, plain)
    turn
  })
}
