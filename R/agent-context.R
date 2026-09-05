clone_compaction_chat <- function(chat) {
  summary_chat <- clone_governed_chat(chat)
  if (identical(summary_chat, chat)) {
    cli::cli_abort("Chat cloning returned the original mutable object")
  }
  validate_chat(summary_chat)

  callback_names <- c(
    "callback_on_tool_request",
    "callback_on_tool_result",
    "callback_on_request_start",
    "callback_on_request_end"
  )
  live_private <- chat$.__enclos_env__$private
  summary_private <- summary_chat$.__enclos_env__$private

  callback_names <- Filter(
    function(name) {
      !is.null(summary_private[[name]]) || startsWith(name, "callback_on_tool")
    },
    callback_names
  )
  for (callback_name in callback_names) {
    live_manager <- live_private[[callback_name]]
    summary_manager <- summary_private[[callback_name]]
    if (is.null(summary_manager) || !is.function(summary_manager$clear)) {
      cli::cli_abort(
        "The summary chat does not expose an isolated {callback_name} manager"
      )
    }
    if (identical(summary_manager, live_manager)) {
      cli::cli_abort(
        "The summary chat shares its {callback_name} manager with the live chat"
      )
    }
  }

  for (callback_name in callback_names) {
    summary_private[[callback_name]]$clear()
  }
  summary_chat$set_turns(list())
  summary_chat$set_system_prompt(NULL)
  summary_chat$set_tools(list())

  summary_chat
}

# Internal R6 methods for agent context.
# R6 binds these methods to the same self/private environments as the facade.
deputy_agent_context_methods <- function(self = NULL, private = NULL) {
  list(
    compaction_prompt_parts = function(prompt) {
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
      after_start <- end_end + 1
      after <- if (after_start > nchar(prompt)) {
        ""
      } else {
        substr(prompt, after_start, nchar(prompt))
      }
      list(before = before, summary = summary, after = after)
    },

    compaction_prompt_block = function(summary) {
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
    },

    system_prompt_without_compaction = function() {
      prompt <- private$.chat$get_system_prompt() %||% ""
      if (is.null(private$.compaction_summary)) {
        return(prompt)
      }
      parts <- private$compaction_prompt_parts(prompt)
      if (
        is.null(parts) ||
          !identical(parts$summary, private$.compaction_summary)
      ) {
        return(prompt)
      }
      paste0(parts$before, parts$after)
    },

    context_token_count = function(messages, turns = NULL) {
      chat <- private$.chat
      if (!is.null(turns)) {
        chat <- tryCatch(clone_governed_chat(chat), error = function(e) NULL)
        if (is.null(chat) || identical(chat, private$.chat)) {
          return(NULL)
        }
        turns_set <- tryCatch(
          {
            chat$set_turns(turns)
            TRUE
          },
          error = function(e) FALSE
        )
        if (!isTRUE(turns_set)) {
          return(NULL)
        }
      }

      count <- tryCatch(
        do.call(
          chat$token_count,
          c(messages, list(include = "complete"))
        ),
        error = function(e) NULL
      )
      if (is.null(count)) {
        count <- context_count_after_unpaired_result(chat, messages)
      }
      if (!is.numeric(count) || length(count) == 0L || anyNA(count)) {
        return(NULL)
      }
      as.numeric(sum(count))
    },

    is_human_turn = function(turn) {
      if (!inherits(turn, "ellmer::UserTurn")) {
        return(FALSE)
      }
      contents <- tryCatch(turn@contents, error = function(e) list())
      !any(vapply(
        contents,
        inherits,
        logical(1),
        what = "ellmer::ContentToolResult"
      ))
    },

    has_tool_request = function(turn) {
      if (!inherits(turn, "ellmer::AssistantTurn")) {
        return(FALSE)
      }
      contents <- tryCatch(turn@contents, error = function(e) list())
      any(vapply(
        contents,
        inherits,
        logical(1),
        what = "ellmer::ContentToolRequest"
      ))
    },

    compaction_keep_last = function(messages, target_tokens) {
      turns <- private$.chat$get_turns()
      if (length(turns) == 0L) {
        return(0L)
      }

      starts <- which(vapply(turns, private$is_human_turn, logical(1)))
      minimum_keep <- 0L
      if (
        isTRUE(private$run_active) &&
          private$has_tool_request(tail(turns, 1L)[[1L]])
      ) {
        recent_human <- tail(starts, 1L)
        minimum_keep <- if (length(recent_human) == 0L) {
          1L
        } else {
          length(turns) - recent_human + 1L
        }
      }
      candidates <- unique(c(starts, length(turns) + 1L))
      for (start in candidates) {
        kept <- if (start > length(turns)) {
          list()
        } else {
          turns[start:length(turns)]
        }
        if (length(kept) < minimum_keep) {
          next
        }
        count <- private$context_token_count(messages, turns = kept)
        if (!is.null(count) && count <= target_tokens) {
          return(as.integer(length(kept)))
        }
      }

      # A conservative fallback for providers that cannot estimate cloned
      # contexts. Keep a complete recent user/assistant exchange when possible.
      recent <- tail(starts, 1L)
      if (length(recent) == 0L) {
        return(as.integer(minimum_keep))
      }
      as.integer(max(minimum_keep, length(turns) - recent + 1L))
    },

    maybe_auto_compact = function(messages) {
      governed_compaction(self, messages)
    },

    prepare_compaction = function(
      keep_last,
      summary,
      fallback,
      automatic,
      estimated_tokens
    ) {
      turns <- private$.chat$get_turns()
      fallback <- match.arg(fallback, c("error", "text"))

      if (is.null(keep_last)) {
        max_tokens <- self$context_policy$max_tokens
        keep_last <- if (is.null(max_tokens)) {
          min(4L, length(turns))
        } else {
          private$compaction_keep_last(
            messages = list(),
            target_tokens = floor(
              max_tokens * self$context_policy$compact_to
            )
          )
        }
      }
      keep_last <- validate_usage_limit(keep_last, "keep_last", integer = TRUE)
      if (is.null(keep_last)) {
        keep_last <- 0L
      }

      if (length(turns) <= keep_last) {
        result <- new_compaction_result(
          method = "none",
          automatic = automatic,
          turns_compacted = 0L,
          turns_kept = length(turns),
          run_id = private$active_run_id(),
          estimated_tokens = estimated_tokens
        )
        private$.last_compaction <- result
        return(list(result = result))
      }

      # Determine which turns to compact
      compact_count <- length(turns) - keep_last
      turns_to_compact <- turns[1:compact_count]
      turns_to_keep <- if (keep_last == 0L) {
        list()
      } else {
        tail(turns, keep_last)
      }

      # Fire PreCompact hook
      hook_result <- private$fire_hook(
        "PreCompact",
        turns_to_compact = turns_to_compact,
        turns_to_keep = turns_to_keep,
        context = private$hook_context(
          total_turns = length(turns),
          compact_count = compact_count
        )
      )

      # Check if hook wants to cancel compaction
      if (!is.null(hook_result) && isFALSE(hook_result$continue)) {
        result <- new_compaction_result(
          method = "cancelled",
          automatic = automatic,
          turns_compacted = 0L,
          turns_kept = length(turns),
          run_id = private$active_run_id(),
          estimated_tokens = estimated_tokens
        )
        private$.last_compaction <- result
        return(list(result = result))
      }

      list(
        chat = private$.chat,
        system_prompt = private$.chat$get_system_prompt(),
        previous_summary = private$.compaction_summary,
        turns = turns,
        turns_to_compact = turns_to_compact,
        turns_to_keep = turns_to_keep,
        summary = summary %||% hook_result$summary,
        method = if (!is.null(summary)) "custom" else "hook",
        automatic = automatic,
        estimated_tokens = estimated_tokens
      )
    },

    install_compaction = function(
      plan,
      summary,
      method,
      summary_usage,
      attempts = list()
    ) {
      if (
        isTRUE(plan$automatic) &&
          (!identical(private$.chat, plan$chat) ||
            !identical(private$.chat$get_turns(), plan$turns) ||
            !identical(private$.chat$get_system_prompt(), plan$system_prompt) ||
            !identical(private$.compaction_summary, plan$previous_summary))
      ) {
        abort_deputy(
          "Conversation changed while compaction was preparing its replacement.",
          class = c("compaction_conflict", "compaction_error")
        )
      }
      summary <- paste(as.character(summary), collapse = "\n")
      current_system <- private$system_prompt_without_compaction()
      new_system <- paste0(
        current_system,
        private$compaction_prompt_block(summary)
      )

      usage <- if (isTRUE(private$run_active)) private$current_run_usage()
      old_prompt <- private$.chat$get_system_prompt()
      tryCatch(
        {
          private$.chat$set_system_prompt(new_system)
          private$.chat$set_turns(plan$turns_to_keep)
        },
        error = function(error) {
          private$.chat$set_system_prompt(old_prompt)
          private$.chat$set_turns(plan$turns)
          rlang::cnd_signal(error)
        }
      )
      private$.compaction_summary <- summary
      if (!is.null(usage)) {
        preserve_run_usage(self, usage)
        state <- private$current_run_state
        state$turns_before <- max(
          0L,
          state$turns_before - length(plan$turns_to_compact)
        )
        if (!isTRUE(state$response_seen) && private$current_tool_calls == 0L) {
          state$dispatch_turns <- private$.chat$get_turns()
          state$request_turns_before <- length(state$dispatch_turns)
        }
      }

      result <- new_compaction_result(
        method = method,
        automatic = plan$automatic,
        turns_compacted = length(plan$turns_to_compact),
        turns_kept = length(plan$turns_to_keep),
        estimated_tokens = plan$estimated_tokens,
        usage = summary_usage,
        attempts = attempts,
        run_id = private$active_run_id(),
        summary = summary
      )
      private$.last_compaction <- result
      private$record_run_event(private$agent_event(
        "compaction",
        method = method,
        automatic = plan$automatic,
        turns_compacted = length(plan$turns_to_compact),
        turns_kept = length(plan$turns_to_keep),
        usage = summary_usage,
        attempts = attempts
      ))
      private$fire_hook(
        "PostCompact",
        result = result,
        context = private$hook_context(
          total_turns = length(plan$turns),
          compact_count = length(plan$turns_to_compact),
          automatic = isTRUE(plan$automatic)
        )
      )
      result
    },

    compaction_content_text = function(content) {
      if (
        !inherits(content, "ellmer::ContentToolResult") ||
          !is.null(content@error)
      ) {
        return(paste(format(content), collapse = "\n"))
      }
      # ellmer's result formatter expects scalar text, while its public result
      # class also permits atomic vectors and Content objects. Format those
      # payloads through their public interfaces; never include display `extra`.
      value <- content@value
      if (inherits(value, "ellmer::Content")) {
        value <- list(value)
      }
      text <- if (is.list(value)) {
        paste(
          vapply(value, private$compaction_content_text, character(1)),
          collapse = "\n"
        )
      } else if (is.character(value)) {
        paste(value, collapse = "\n")
      } else {
        as.character(jsonlite::toJSON(value, auto_unbox = TRUE, null = "null"))
      }
      paste(format(content, show = "header"), text, sep = "\n")
    },

    compaction_turn_text = function(turn) {
      # `turn@text` intentionally omits tool content. Model and degraded text
      # summaries use the same public evidence projection.
      cli::ansi_strip(paste(
        vapply(
          turn@contents,
          private$compaction_content_text,
          character(1)
        ),
        collapse = "\n"
      ))
    },

    # Generate a summary of turns using the LLM
    compaction_summary_prompt = function(turns) {
      # Format turns for compaction
      turn_texts <- vapply(
        turns,
        function(turn) {
          role <- if (inherits(turn, "ellmer::UserTurn")) {
            "User"
          } else if (inherits(turn, "ellmer::AssistantTurn")) {
            "Assistant"
          } else {
            cli_warn(c(
              "Unknown turn type in compaction summary",
              "i" = "Got class: {.cls {class(turn)}}",
              "i" = "Defaulting to 'Unknown'"
            ))
            "Unknown"
          }
          text <- private$compaction_turn_text(turn)
          paste0(role, ": ", text)
        },
        character(1)
      )

      conversation_text <- paste(turn_texts, collapse = "\n\n")
      prior_summary <- private$.compaction_summary
      prior_summary_text <- if (is.null(prior_summary)) {
        ""
      } else {
        paste0(
          "Existing summary from earlier compactions:\n",
          prior_summary,
          "\n\n"
        )
      }

      # Create the compaction prompt
      paste0(
        "Summarize the following conversation excerpt concisely. ",
        "Focus on:\n",
        "1. Key decisions made\n",
        "2. Important findings or results\n",
        "3. Files created, modified, or discussed\n",
        "4. Any errors encountered and how they were resolved\n",
        "5. Current state/progress of the task\n\n",
        "Keep the summary under 500 words. Be factual and specific.\n\n",
        prior_summary_text,
        "Conversation excerpt to merge into the summary:\n",
        "---\n",
        conversation_text,
        "\n---\n\n",
        "Summary:"
      )
    },

    generate_compaction_summary = function(turns, fallback = "error") {
      fallback <- match.arg(fallback, c("error", "text"))
      compaction_prompt <- private$compaction_summary_prompt(turns)
      temp_chat <- tryCatch(
        clone_compaction_chat(private$.chat),
        error = function(e) e
      )
      response <- if (inherits(temp_chat, "error")) {
        temp_chat
      } else {
        tryCatch(
          temp_chat$chat(compaction_prompt, echo = "none"),
          error = function(e) e
        )
      }

      if (!inherits(response, "error")) {
        return(list(
          summary = response,
          method = "llm",
          usage = agent_usage_snapshot(temp_chat)
        ))
      }

      if (identical(fallback, "error")) {
        cli_abort(
          c(
            "Conversation compaction failed.",
            "x" = response$message,
            "i" = "Set ContextPolicy(fallback = 'text') to permit degraded compaction."
          ),
          class = c("deputy_compaction_error", "deputy_error"),
          parent = response
        )
      }

      private$notify(
        "Compaction used the configured deterministic text fallback.",
        level = "warning",
        code = "compact_fallback",
        error = response$message
      )
      list(
        summary = private$generate_fallback_summary(turns),
        method = "text",
        usage = AgentUsage()
      )
    },

    # Fallback summary when LLM is unavailable
    generate_fallback_summary = function(turns) {
      summary_parts <- vapply(
        turns,
        function(turn) {
          role <- if (inherits(turn, "ellmer::UserTurn")) {
            "User"
          } else if (inherits(turn, "ellmer::AssistantTurn")) {
            "Assistant"
          } else {
            cli_warn(c(
              "Unknown turn type in fallback summary",
              "i" = "Got class: {.cls {class(turn)}}",
              "i" = "Defaulting to 'Unknown'"
            ))
            "Unknown"
          }
          text <- private$compaction_turn_text(turn)
          if (nchar(text) > 200) {
            text <- paste0(substr(text, 1, 197), "...")
          }
          paste0(role, ": ", text)
        },
        character(1)
      )

      excerpt_summary <- paste0(
        "[Compacted ",
        length(turns),
        " earlier turns - LLM summary unavailable]\n\n",
        paste(summary_parts, collapse = "\n\n")
      )
      if (is.null(private$.compaction_summary)) {
        return(excerpt_summary)
      }
      paste0(
        "[Prior compacted conversation]\n",
        private$.compaction_summary,
        "\n\n",
        excerpt_summary
      )
    }
  )
}
