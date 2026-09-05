clone_compaction_chat <- function(chat) {
  summary_chat <- clone_governed_chat(chat)
  if (identical(summary_chat, chat)) {
    cli::cli_abort("Chat cloning returned the original mutable object")
  }
  validate_chat(summary_chat)

  callback_names <- c(
    "callback_on_tool_request",
    "callback_on_tool_result"
  )
  live_private <- chat$.__enclos_env__$private
  summary_private <- summary_chat$.__enclos_env__$private

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

    maybe_auto_compact = function(messages, limits = NULL, usage = NULL) {
      policy <- private$.context_policy
      if (is.null(policy$max_tokens)) {
        return(NULL)
      }
      turns <- private$.chat$get_turns()
      if (length(turns) == 0L) {
        return(NULL)
      }

      if (is.null(limits) && isTRUE(private$run_active)) {
        limits <- private$current_usage_limits
      }
      if (!is.null(limits)) {
        if (is.null(usage)) {
          usage <- if (isTRUE(private$run_active)) {
            private$current_run_usage()
          } else {
            AgentUsage()
          }
        }
        limit_status <- usage_limit_status(
          usage,
          limits,
          require_followup = TRUE
        )
        if (!is.null(limit_status)) {
          if (isTRUE(private$run_active)) {
            private$mark_usage_limit(limit_status)
          }
          return(NULL)
        }
      }

      estimated <- private$context_token_count(messages)
      if (is.null(estimated) || estimated <= policy$max_tokens) {
        return(NULL)
      }

      keep_last <- private$compaction_keep_last(
        messages = messages,
        target_tokens = floor(policy$max_tokens * policy$compact_to)
      )
      result <- self$compact(
        keep_last = keep_last,
        fallback = policy$fallback,
        automatic = TRUE,
        estimated_tokens = estimated
      )
      if (isTRUE(private$run_active)) {
        private$add_external_usage(result$usage)
      }
      result
    },

    # Generate a summary of turns using the LLM
    generate_compaction_summary = function(turns, fallback = "error") {
      fallback <- match.arg(fallback, c("error", "text"))
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
          text <- turn@text %||% "[no text]"

          # Include tool information if present
          tool_info <- ""
          if (inherits(turn, "ellmer::AssistantTurn")) {
            contents <- turn@contents %||% list()
            tool_requests <- Filter(
              function(c) inherits(c, "ellmer::ContentToolRequest"),
              contents
            )
            if (length(tool_requests) > 0) {
              tool_names <- vapply(
                tool_requests,
                function(tool) tool@name %||% "unknown",
                character(1)
              )
              tool_info <- paste0(
                " [Tools: ",
                paste(tool_names, collapse = ", "),
                "]"
              )
            }
          }

          paste0(role, tool_info, ": ", text)
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
      compaction_prompt <- paste0(
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
          text <- turn@text %||% "[no text]"
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
