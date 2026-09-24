# Internal R6 methods for agent session.
# R6 binds these methods to the same self/private environments as the facade.
deputy_agent_session_methods <- function(self = NULL, private = NULL) {
  list(
    build_session_payload = function() {
      list(
        schema_version = 3L,
        turns = portable_session_turns(private$.chat$get_turns()),
        compacted_turns = portable_session_turns(private$.compacted_turns),
        # Optional: originals of results cleared by microcompact(), stored as
        # one user turn so they share the turn serializers.
        cleared_tool_results = cleared_tool_results_turns(
          private$.cleared_tool_results
        ),
        system_prompt = private$.chat$get_system_prompt(),
        compaction_summary = private$.compaction_summary,
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

      required_fields <- c(
        "turns",
        "compacted_turns",
        "system_prompt",
        "compaction_summary",
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
      if (!is.list(session$turns)) {
        abort_session_load(
          "Invalid session file - turns must be a list",
          path = source
        )
      }
      if (
        !is.list(session$compacted_turns) ||
          !all(vapply(
            session$compacted_turns,
            function(turn) {
              S7::S7_inherits(turn, ellmer::UserTurn) ||
                S7::S7_inherits(turn, ellmer::AssistantTurn)
            },
            logical(1)
          ))
      ) {
        abort_session_load(
          "Invalid session file - compacted_turns must be a list of conversation turns",
          path = source
        )
      }
      restored_compacted_turns <- portable_session_turns(
        session$compacted_turns
      )
      restored_cleared <- tryCatch(
        cleared_tool_results_from_turns(session$cleared_tool_results),
        error = function(error) {
          abort_session_load(
            c(
              "Invalid session file - cleared tool results are malformed",
              "x" = conditionMessage(error)
            ),
            path = source,
            parent = error
          )
        }
      )
      if (
        !is.null(session$system_prompt) &&
          (!is.character(session$system_prompt) ||
            length(session$system_prompt) != 1L ||
            is.na(session$system_prompt))
      ) {
        abort_session_load(
          "Invalid session file - system_prompt must be one string or NULL",
          path = source
        )
      }
      if (
        !is.null(session$compaction_summary) &&
          (!is.character(session$compaction_summary) ||
            length(session$compaction_summary) != 1L ||
            is.na(session$compaction_summary))
      ) {
        abort_session_load(
          "Invalid session file - compaction_summary must be one string or NULL",
          path = source
        )
      }

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

      previous_turns <- private$.chat$get_turns()
      previous_prompt <- private$.chat$get_system_prompt()
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
          private$.chat$set_turns(session$turns)
          private$.chat$set_system_prompt(session$system_prompt)
          if (length(restored_tool_results) > 0L) {
            private$ensure_tool_result_reader()
          }
          commit_tool_result_envelope_replacement(tool_result_replacement)
        },
        error = function(error) {
          try(private$.chat$set_turns(previous_turns), silent = TRUE)
          try(private$.chat$set_system_prompt(previous_prompt), silent = TRUE)
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
      private$.compaction_summary <- session$compaction_summary
      private$.compacted_turns <- restored_compacted_turns
      private$.cleared_tool_results <- restored_cleared
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

cleared_tool_results_turns <- function(originals) {
  if (length(originals) == 0L) {
    return(list())
  }
  portable_session_turns(list(ellmer::UserTurn(contents = unname(originals))))
}

# Older schema 3 snapshots have no field, which means nothing was cleared.
cleared_tool_results_from_turns <- function(turns) {
  if (is.null(turns) || length(turns) == 0L) {
    return(list())
  }
  if (!is.list(turns)) {
    cli_abort("Expected a list of turns.")
  }
  originals <- list()
  for (turn in turns) {
    if (!S7::S7_inherits(turn, ellmer::UserTurn)) {
      cli_abort("Expected user turns.")
    }
    for (content in turn@contents) {
      id <- tryCatch(content@request@id, error = function(e) NULL)
      if (
        !S7::S7_inherits(content, ellmer::ContentToolResult) ||
          !is_nonempty_string(id)
      ) {
        cli_abort("Expected tool results with tool call IDs.")
      }
      originals[[id]] <- content
    }
  }
  originals
}
