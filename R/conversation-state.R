# Internal conversation state.  The Chat is deliberately not retained here:
# callers pass the current Chat to every operation, which keeps this object
# usable when a run moves between provider Chats.

conversation_state_prompt_parts <- function(prompt) {
  if (
    !is.character(prompt) ||
      length(prompt) != 1L ||
      is.na(prompt)
  ) {
    return(NULL)
  }

  start_pattern <- paste0(
    "\\n\\n<!-- deputy-compaction-summary:v1 chars=([0-9]+) ",
    "sha256=([a-f0-9]{64}) -->\\n",
    "## Previous Conversation Summary\\n"
  )
  start <- regexec(start_pattern, prompt, perl = TRUE)[[1L]]
  captured <- regmatches(prompt, list(start))[[1L]]
  if (length(captured) != 3L) {
    return(NULL)
  }

  summary_chars <- suppressWarnings(as.numeric(captured[[2L]]))
  if (
    length(summary_chars) != 1L ||
      is.na(summary_chars) ||
      !is.finite(summary_chars) ||
      summary_chars < 0 ||
      summary_chars != floor(summary_chars)
  ) {
    return(NULL)
  }

  summary_start <- start[[1L]] + attr(start, "match.length")[[1L]]
  summary_end <- summary_start + summary_chars - 1
  summary <- if (summary_chars == 0) {
    ""
  } else {
    substr(prompt, summary_start, summary_end)
  }
  if (
    !identical(
      digest::digest(summary, algo = "sha256", serialize = FALSE),
      captured[[3L]]
    )
  ) {
    return(NULL)
  }

  end_marker <- paste0(
    "\n\n## End Previous Conversation Summary\n",
    "<!-- deputy-compaction-summary:v1:end -->"
  )
  end_start <- summary_start + summary_chars
  end_end <- end_start + nchar(end_marker, type = "chars") - 1
  if (!identical(substr(prompt, end_start, end_end), end_marker)) {
    return(NULL)
  }

  before <- substr(prompt, 1L, start[[1L]] - 1L)
  after_start <- end_end + 1L
  after <- if (after_start > nchar(prompt)) {
    ""
  } else {
    substr(prompt, after_start, nchar(prompt))
  }
  list(before = before, summary = summary, after = after)
}

conversation_state_prompt_block <- function(summary) {
  paste0(
    "\n\n<!-- deputy-compaction-summary:v1 chars=",
    nchar(summary, type = "chars"),
    " sha256=",
    digest::digest(summary, algo = "sha256", serialize = FALSE),
    " -->\n## Previous Conversation Summary\n",
    summary,
    "\n\n## End Previous Conversation Summary\n",
    "<!-- deputy-compaction-summary:v1:end -->"
  )
}

# Internal helpers for the conversation state representation.  They do not
# retain a Chat or an Agent.
cleared_result_key <- function(turn, content) {
  paste0(turn, ":", content)
}

restore_cleared_tool_results <- function(
  turns,
  originals,
  positions = seq_along(turns)
) {
  if (length(originals) == 0L) {
    return(turns)
  }
  for (i in seq_along(turns)) {
    if (is.na(positions[[i]])) {
      next
    }
    contents <- turns[[i]]@contents
    changed <- FALSE
    for (j in seq_along(contents)) {
      entry <- originals[[cleared_result_key(positions[[i]], j)]]
      content <- contents[[j]]
      if (
        !is.null(entry) &&
          S7::S7_inherits(content, ellmer::ContentToolResult) &&
          identical(content@value, entry$marker) &&
          is.null(content@error)
      ) {
        contents[[j]] <- entry$content
        changed <- TRUE
      }
    }
    if (changed) {
      turns[[i]]@contents <- contents
    }
  }
  turns
}

# Saved as positions and markers plus one user turn holding the originals in
# the same order, so the originals share the turn serializers.
cleared_tool_results_turns <- function(originals) {
  if (length(originals) == 0L) {
    return(list())
  }
  list(
    keys = names(originals),
    markers = vapply(
      originals,
      function(x) x$marker,
      character(1),
      USE.NAMES = FALSE
    ),
    turns = portable_session_turns(list(ellmer::UserTurn(
      contents = unname(lapply(originals, function(x) x$content))
    )))
  )
}

# Older schema 3 snapshots have no field, which means nothing was cleared.
cleared_tool_results_from_turns <- function(saved) {
  if (is.null(saved) || length(saved) == 0L) {
    return(list())
  }
  keys <- saved$keys
  markers <- saved$markers
  turns <- saved$turns
  if (
    !is.character(keys) ||
      !is.character(markers) ||
      length(keys) != length(markers) ||
      anyDuplicated(keys) ||
      !is.list(turns) ||
      length(turns) != 1L ||
      !S7::S7_inherits(turns[[1L]], ellmer::UserTurn)
  ) {
    cli_abort("Expected positions, markers and one user turn.")
  }
  contents <- turns[[1L]]@contents
  if (
    length(contents) != length(keys) ||
      !all(vapply(
        contents,
        function(x) S7::S7_inherits(x, ellmer::ContentToolResult),
        logical(1)
      ))
  ) {
    cli_abort("Expected one tool result per saved position.")
  }
  stats::setNames(
    Map(
      function(marker, content) {
        list(marker = marker, content = content)
      },
      markers,
      contents
    ),
    keys
  )
}

# Microcompact originals are keyed by the position in the complete
# conversation: retained prefix first, then the current Chat context.
remap_cleared_tool_results <- function(originals, kept, offset) {
  if (length(originals) == 0L) {
    return(originals)
  }
  parts <- strsplit(names(originals), ":", fixed = TRUE)
  turn <- as.integer(vapply(parts, `[[`, character(1), 1L))
  content <- vapply(parts, `[[`, character(1), 2L)
  context <- turn > offset
  moved <- match(turn[context] - offset, kept)
  turn[context] <- offset + moved
  keep <- !is.na(turn)
  originals <- originals[keep]
  names(originals) <- cleared_result_key(turn[keep], content[keep])
  originals
}

conversation_state_valid_turns <- function(value) {
  is.list(value) &&
    all(vapply(
      value,
      function(turn) {
        S7::S7_inherits(turn, ellmer::UserTurn) ||
          S7::S7_inherits(turn, ellmer::AssistantTurn)
      },
      logical(1)
    ))
}

# Map the conversation part of a session-shaped value while retaining all
# control-plane and session fields. `context` maps the current turns;
# `retained` maps compacted turns and the nested originals turn payload. The
# mappers are functions so approval replay can attach the current tool set.
map_conversation_snapshot <- function(
  snapshot,
  context,
  retained = context
) {
  if (!is.list(snapshot)) {
    cli::cli_abort("snapshot must be a named list.")
  }
  if (!is.function(context) || !is.function(retained)) {
    cli::cli_abort("context and retained must be mapping functions.")
  }
  mapped <- snapshot
  mapped$turns <- context(mapped$turns)
  mapped$compacted_turns <- retained(mapped$compacted_turns)
  originals <- mapped$cleared_tool_results
  if (
    is.list(originals) &&
      !is.null(names(originals)) &&
      "turns" %in% names(originals)
  ) {
    originals$turns <- retained(originals$turns)
    mapped$cleared_tool_results <- originals
  }
  mapped
}

ConversationState <- R6::R6Class(
  "ConversationState",

  public = list(
    transcript = function(chat) {
      restore_cleared_tool_results(
        c(private$.retained_turns, chat$get_turns()),
        private$.originals
      )
    },

    last_turn = function(chat, role = c("assistant", "user", "system")) {
      role <- match.arg(role)
      current <- chat$last_turn(role = role)
      if (!is.null(current)) {
        context <- chat$get_turns()
        matches <- which(vapply(
          context,
          function(turn) identical(turn, current),
          logical(1)
        ))
        position <- if (length(matches)) {
          length(private$.retained_turns) + max(matches)
        } else {
          NA_integer_
        }
        turn <- restore_cleared_tool_results(
          list(current),
          private$.originals,
          positions = position
        )[[1L]]
        return(list(turn = turn, position = position))
      }

      retained <- Filter(
        function(turn) identical(turn@role, role),
        private$.retained_turns
      )
      if (!length(retained)) {
        return(NULL)
      }
      roles <- vapply(
        private$.retained_turns,
        function(turn) turn@role,
        character(1)
      )
      position <- max(which(roles == role))
      turn <- restore_cleared_tool_results(
        list(tail(retained, 1L)[[1L]]),
        private$.originals,
        positions = position
      )[[1L]]
      list(turn = turn, position = position)
    },

    retained_turns = function() {
      private$.retained_turns
    },

    summary = function() {
      private$.summary
    },

    snapshot = function(chat) {
      list(
        turns = portable_session_turns(chat$get_turns()),
        compacted_turns = portable_session_turns(private$.retained_turns),
        cleared_tool_results = cleared_tool_results_turns(private$.originals),
        system_prompt = chat$get_system_prompt(),
        compaction_summary = private$.summary
      )
    },

    replace = function(chat, turns) {
      previous_prompt <- chat$get_system_prompt()
      prompt <- self$prompt_without_summary(chat)
      commit <- function() {
        private$.retained_turns <- list()
        private$.originals <- list()
        private$.summary <- NULL
      }
      if (identical(previous_prompt, prompt)) {
        private$transaction(chat, turns = turns, commit = commit)
      } else {
        private$transaction(
          chat,
          turns = turns,
          prompt = prompt,
          commit = commit
        )
      }
      invisible(NULL)
    },

    set_prompt = function(chat, value, reconcile = TRUE) {
      if (
        !is.logical(reconcile) || length(reconcile) != 1L || is.na(reconcile)
      ) {
        cli::cli_abort("{.arg reconcile} must be TRUE or FALSE.")
      }
      private$transaction(
        chat,
        prompt = value,
        commit = function() {
          if (!isTRUE(reconcile)) {
            return(invisible(NULL))
          }
          parts <- conversation_state_prompt_parts(chat$get_system_prompt())
          private$.summary <- if (
            is.null(private$.summary) ||
              is.null(parts) ||
              !identical(parts$summary, private$.summary)
          ) {
            NULL
          } else {
            parts$summary
          }
          invisible(NULL)
        }
      )
      invisible(NULL)
    },

    prompt_without_summary = function(chat) {
      prompt <- chat$get_system_prompt() %||% ""
      if (is.null(private$.summary)) {
        return(prompt)
      }
      parts <- conversation_state_prompt_parts(prompt)
      if (is.null(parts) || !identical(parts$summary, private$.summary)) {
        return(prompt)
      }
      paste0(parts$before, parts$after)
    },

    microcompact = function(
      chat,
      keep_last = 2L,
      keep_tools = character(),
      marker = "[Old tool result cleared to save context.]"
    ) {
      if (
        !is.numeric(keep_last) ||
          length(keep_last) != 1L ||
          is.na(keep_last) ||
          keep_last < 0 ||
          (is.finite(keep_last) && keep_last != floor(keep_last))
      ) {
        cli::cli_abort(
          "{.arg keep_last} must be a whole number of turns, 0 or more."
        )
      }
      if (!is.character(keep_tools) || anyNA(keep_tools)) {
        cli::cli_abort("{.arg keep_tools} must be a character vector.")
      }
      if (!is_nonempty_string(marker)) {
        cli::cli_abort("{.arg marker} must be one non-empty string.")
      }

      turns <- chat$get_turns()
      upto <- if (keep_last >= length(turns)) {
        0L
      } else {
        length(turns) - as.integer(keep_last)
      }
      offset <- length(private$.retained_turns)
      originals <- private$.originals
      cleared <- 0L
      if (upto > 0L) {
        for (i in seq_len(upto)) {
          contents <- turns[[i]]@contents
          changed <- FALSE
          for (j in seq_along(contents)) {
            content <- contents[[j]]
            if (!S7::S7_inherits(content, ellmer::ContentToolResult)) {
              next
            }
            name <- tryCatch(content@request@name, error = function(e) NULL)
            if (!is.null(name) && name %in% keep_tools) {
              next
            }
            key <- cleared_result_key(offset + i, j)
            # Already cleared: retain the first original and marker.
            if (!is.null(originals[[key]])) {
              next
            }
            originals[[key]] <- list(marker = marker, content = content)
            content@value <- marker
            content@error <- NULL
            contents[[j]] <- content
            changed <- TRUE
            cleared <- cleared + 1L
          }
          if (changed) {
            turns[[i]]@contents <- contents
          }
        }
      }

      if (cleared > 0L) {
        private$transaction(
          chat,
          turns = turns,
          commit = function() {
            private$.originals <- originals
          }
        )
      }
      list(cleared = as.integer(cleared))
    },

    prepare_compaction = function(chat, keep_last) {
      keep_last <- validate_usage_limit(keep_last, "keep_last", integer = TRUE)
      if (is.null(keep_last)) {
        keep_last <- 0L
      }
      turns <- chat$get_turns()
      compact_count <- max(0L, length(turns) - keep_last)
      turns_to_compact <- if (compact_count == 0L) {
        list()
      } else {
        turns[seq_len(compact_count)]
      }
      turns_to_keep <- if (keep_last == 0L) {
        list()
      } else {
        tail(turns, keep_last)
      }
      list(
        chat = chat,
        system_prompt = chat$get_system_prompt(),
        previous_summary = private$.summary,
        turns = turns,
        turns_to_compact = turns_to_compact,
        turns_to_keep = turns_to_keep
      )
    },

    compact = function(chat, plan, summary, install = NULL) {
      if (!is.null(install) && !is.function(install)) {
        cli::cli_abort("{.arg install} must be a function or NULL.")
      }
      if (
        isTRUE(plan$automatic) &&
          (is.null(plan$chat) ||
            !identical(chat, plan$chat) ||
            !identical(chat$get_turns(), plan$turns) ||
            !identical(chat$get_system_prompt(), plan$system_prompt) ||
            !identical(private$.summary, plan$previous_summary))
      ) {
        abort_deputy(
          "Conversation changed while compaction was preparing its replacement.",
          class = c("compaction_conflict", "compaction_error")
        )
      }

      summary <- paste(as.character(summary), collapse = "\n")
      current_system <- self$prompt_without_summary(chat)
      new_system <- paste0(
        current_system %||% "",
        conversation_state_prompt_block(summary)
      )
      compacted <- c(
        private$.retained_turns,
        portable_session_turns(plan$turns_to_compact)
      )
      private$transaction(
        chat,
        turns = plan$turns_to_keep,
        prompt = new_system,
        callback = install,
        prompt_first = TRUE,
        commit = function() {
          private$.retained_turns <- compacted
          private$.summary <- summary
        }
      )
      invisible(NULL)
    },

    prepare_restore = function(snapshot, source = NULL) {
      fail <- function(message, parent = NULL) {
        abort_session_load(message, path = source, parent = parent)
      }
      if (!is.list(snapshot)) {
        fail("Invalid session file - expected a named list")
      }
      required <- c(
        "turns",
        "compacted_turns",
        "system_prompt",
        "compaction_summary"
      )
      missing <- setdiff(required, names(snapshot))
      if (length(missing)) {
        fail(c(
          "Invalid session file - missing required fields",
          "x" = "Missing: {.val {missing}}"
        ))
      }
      if (!is.list(snapshot$turns)) {
        fail(
          "Invalid session file - turns must be a list"
        )
      }
      if (!conversation_state_valid_turns(snapshot$compacted_turns)) {
        fail(
          "Invalid session file - compacted_turns must be a list of conversation turns"
        )
      }
      if (
        !is.null(snapshot$system_prompt) &&
          (!is.character(snapshot$system_prompt) ||
            length(snapshot$system_prompt) != 1L ||
            is.na(snapshot$system_prompt))
      ) {
        fail("Invalid session file - system_prompt must be one string or NULL")
      }
      if (
        !is.null(snapshot$compaction_summary) &&
          (!is.character(snapshot$compaction_summary) ||
            length(snapshot$compaction_summary) != 1L ||
            is.na(snapshot$compaction_summary))
      ) {
        fail(
          "Invalid session file - compaction_summary must be one string or NULL"
        )
      }

      cleared <- if ("cleared_tool_results" %in% names(snapshot)) {
        tryCatch(
          cleared_tool_results_from_turns(snapshot$cleared_tool_results),
          error = function(error) {
            fail(
              c(
                "Invalid session file - cleared tool results are malformed",
                "x" = conditionMessage(error)
              ),
              parent = error
            )
          }
        )
      } else {
        list()
      }

      turns <- snapshot$turns
      retained <- portable_session_turns(snapshot$compacted_turns)
      list(
        turns = turns,
        system_prompt = snapshot$system_prompt,
        retained_turns = retained,
        originals = cleared,
        summary = snapshot$compaction_summary
      )
    },

    restore = function(chat, prepared, install = NULL) {
      if (!is.null(install) && !is.function(install)) {
        cli::cli_abort("{.arg install} must be a function or NULL.")
      }
      retained <- prepared$retained_turns
      originals <- prepared$originals
      summary <- prepared$summary
      private$transaction(
        chat,
        turns = prepared$turns,
        prompt = prepared$system_prompt,
        callback = install,
        commit = function() {
          private$.retained_turns <- retained %||% list()
          private$.originals <- originals %||% list()
          private$.summary <- summary
        }
      )
      invisible(NULL)
    },

    remap_context = function(kept) {
      private$.originals <- remap_cleared_tool_results(
        private$.originals,
        kept,
        offset = length(private$.retained_turns)
      )
      invisible(NULL)
    }
  ),

  private = list(
    .retained_turns = list(),
    .originals = list(),
    .summary = NULL,

    transaction = function(
      chat,
      turns = NULL,
      prompt = NULL,
      callback = NULL,
      commit = function() invisible(NULL),
      prompt_first = FALSE
    ) {
      has_turns <- !missing(turns)
      has_prompt <- !missing(prompt)
      previous_turns <- chat$get_turns()
      previous_prompt <- chat$get_system_prompt()

      failure <- tryCatch(
        {
          set_prompt <- function() {
            if (has_prompt) {
              chat$set_system_prompt(prompt)
            }
          }
          set_turns <- function() {
            if (has_turns) {
              chat$set_turns(turns)
            }
          }
          if (isTRUE(prompt_first)) {
            set_prompt()
            set_turns()
          } else {
            set_turns()
            set_prompt()
          }
          if (!is.null(callback)) {
            callback()
          }
          commit()
          NULL
        },
        error = function(error) error
      )
      if (!is.null(failure)) {
        # The setters can fail after partially changing a Chat. Restore both
        # fields best-effort, then surface the original condition.
        try(chat$set_turns(previous_turns), silent = TRUE)
        try(chat$set_system_prompt(previous_prompt), silent = TRUE)
        rlang::cnd_signal(failure)
      }
      invisible(NULL)
    }
  )
)
