compaction_tool_result_reference_pattern <- paste0(
  "deputy://tool-result/result_[a-f0-9]{64}",
  "\\?text_sha256=[a-f0-9]{64}"
)

compaction_tool_result_references <- function(text) {
  unique(unlist(
    regmatches(
      text,
      gregexpr(
        compaction_tool_result_reference_pattern,
        text
      )
    ),
    use.names = FALSE
  ))
}

compaction_evidence_exceeds_limit <- function(value, limit) {
  if (is.null(limit)) {
    return(FALSE)
  }
  estimate <- function(value, budget) {
    if (is.null(value)) {
      return(4)
    }
    if (budget < 2 || length(value) > budget) {
      return(budget + 1)
    }
    size <- 2
    if (!is.null(names(value))) {
      repetitions <- if (is.data.frame(value)) nrow(value) else 1
      size <- size + repetitions * estimate(names(value), budget)
    }
    if (is.data.frame(value)) {
      size <- size + 2 * nrow(value)
    }
    if (size > budget) {
      return(size)
    }
    if (is.factor(value)) {
      value <- as.character(value)
    } else if (is.object(value) && !is.data.frame(value)) {
      # Other class-specific JSON methods do not have a generic size bound.
      return(budget + 1)
    }
    if (is.character(value)) {
      for (index in seq_along(value)) {
        # JSON can expand one control byte to six characters. Count repeated
        # strings separately even when R shares their underlying storage.
        bytes <- if (is.na(value[[index]])) {
          4
        } else {
          nchar(value[[index]], "bytes")
        }
        size <- size + 6 * bytes + 3
        if (size > budget) return(size)
      }
    } else if (is.list(value)) {
      for (index in seq_along(value)) {
        size <- size + estimate(value[[index]], budget - size) + 1
        if (size > budget) return(size)
      }
    } else if (is.atomic(value)) {
      # Includes expanded ALTREP sequences without allocating their JSON.
      size <- size + 32 * length(value)
    } else {
      size <- budget + 1
    }
    size
  }
  estimate(value, limit) > limit
}

compaction_reference_handles <- function(
  references,
  policy,
  session_id,
  agent_id
) {
  catalog_ids <- character()
  references <- unique(unlist(
    lapply(references, function(reference) {
      envelope <- tryCatch(
        read_tool_result_envelope(reference, policy, session_id),
        error = function(error) NULL
      )
      if (
        !is.null(envelope) &&
          identical(envelope$tool_name, "deputy_compaction_catalog") &&
          inherits(envelope$value, "deputy_compaction_catalog")
      ) {
        catalog_ids <<- c(catalog_ids, envelope$id)
        unclass(envelope$value)
      } else {
        reference
      }
    }),
    use.names = FALSE
  ))
  if (length(references) <= 8L) {
    return(list(
      text = paste(references, collapse = "\n"),
      catalogs = catalog_ids
    ))
  }
  record <- offload_tool_result(
    structure(references, class = "deputy_compaction_catalog"),
    tool_name = "deputy_compaction_catalog",
    policy = policy,
    session_id = session_id,
    agent_id = agent_id,
    force = TRUE
  )
  list(
    text = paste(
      paste0("Catalog of ", length(references), " tool results: ", record$uri),
      "Call deputy_read_tool_result on this catalog for individual references.",
      sep = "\n"
    ),
    catalogs = unique(c(catalog_ids, record$id)),
    record = record
  )
}

compaction_catalog_registries <- new.env(parent = emptyenv())

new_compaction_catalog_registry <- function(owner, policy, session_id) {
  directory <- tool_result_offload_dir(policy, session_id)
  key <- file.path(
    normalizePath(dirname(directory), winslash = "/", mustWork = FALSE),
    basename(directory)
  )
  # Keep only weak registry references globally: neither finished sessions nor
  # discarded Agents should be retained by this process-local ownership index.
  for (name in ls(compaction_catalog_registries, all.names = TRUE)) {
    if (is.null(rlang::wref_key(compaction_catalog_registries[[name]]))) {
      rm(list = name, envir = compaction_catalog_registries)
    }
  }
  existing <- compaction_catalog_registries[[key]]
  registry <- if (!is.null(existing)) rlang::wref_key(existing)
  if (is.null(registry)) {
    registry <- new.env(parent = emptyenv())
    registry$owners <- list()
    registry$catalogs <- character()
    registry$provisional <- list()
    registry$transactions <- list()
    compaction_catalog_registries[[key]] <- rlang::new_weakref(registry)
  }
  register_compaction_catalog_owner(registry, owner)
  registry
}

register_compaction_catalog_owner <- function(registry, owner) {
  registry$owners <- c(registry$owners, list(rlang::new_weakref(owner)))
  invisible(NULL)
}

compaction_embedded_references <- function(value) {
  if (is.character(value) || is.factor(value)) {
    return(compaction_tool_result_references(as.character(value)))
  }
  if (inherits(value, "ellmer::Content")) {
    value <- S7::props(value)
  }
  if (is.list(value)) {
    return(unique(unlist(
      lapply(value, compaction_embedded_references),
      use.names = FALSE
    )))
  }
  character()
}

retire_compaction_catalogs <- function(
  catalogs,
  references,
  policy,
  session_id,
  registry
) {
  registry$catalogs <- unique(c(registry$catalogs, catalogs))
  owners <- lapply(registry$owners, rlang::wref_key)
  alive <- !vapply(owners, is.null, logical(1))
  registry$owners <- registry$owners[alive]
  # Agents sharing session storage may have independent live contexts. Weak
  # references check those contexts without retaining discarded clients.
  for (owner in owners[alive]) {
    references <- c(
      references,
      compaction_tool_result_references(owner$get_system_prompt()),
      compaction_embedded_references(lapply(owner$get_turns(), function(turn) {
        turn@contents
      }))
    )
  }
  retained <- vapply(references, parse_tool_result_reference, character(1))
  directory <- tool_result_offload_dir(policy, session_id)
  for (id in setdiff(registry$catalogs, retained)) {
    envelope <- tryCatch(
      read_tool_result_envelope(
        paste0("deputy://tool-result/", id),
        policy,
        session_id
      ),
      error = function(error) NULL
    )
    # Never reclaim ordinary result artifacts, including on a metadata mismatch.
    if (
      is.null(envelope) ||
        !identical(envelope$tool_name, "deputy_compaction_catalog") ||
        !inherits(envelope$value, "deputy_compaction_catalog")
    ) {
      next
    }
    paths <- file.path(directory, paste0(id, c(".rds", ".txt", ".meta.rds")))
    if (unlink(paths) != 0L) {
      cli_warn("Could not remove a superseded compaction catalog.")
    } else {
      registry$catalogs <- setdiff(registry$catalogs, id)
    }
  }
  invisible(NULL)
}

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
    begin_compaction_artifacts = function() {
      transaction <- new.env(parent = emptyenv())
      transaction$ids <- character()
      transaction$installed <- FALSE
      private$.compaction_artifacts <- transaction
      registry <- private$.compaction_catalog_registry
      registry$transactions <- c(registry$transactions, list(transaction))
      transaction
    },

    track_compaction_artifact = function(record) {
      transaction <- private$.compaction_artifacts
      if (!is.null(transaction) && !is.null(record)) {
        transaction$ids <- unique(c(transaction$ids, record$id))
        if (isTRUE(record$created)) {
          private$.compaction_catalog_registry$provisional[[
            record$id
          ]] <- record
        }
      }
      invisible(NULL)
    },

    finish_compaction_artifacts = function(transaction) {
      if (identical(private$.compaction_artifacts, transaction)) {
        private$.compaction_artifacts <- NULL
      }
      registry <- private$.compaction_catalog_registry
      registry$transactions <- Filter(
        function(other) {
          !identical(other, transaction)
        },
        registry$transactions
      )
      if (isTRUE(transaction$installed)) {
        registry$provisional[transaction$ids] <- NULL
      }
      pending <- unlist(lapply(registry$transactions, function(other) {
        other$ids
      }))
      # A sibling transaction may still be using the same content-addressed
      # artifact. Its eventual install or abort decides that artifact's fate.
      for (id in setdiff(names(registry$provisional), pending)) {
        record <- registry$provisional[[id]]
        paths <- file.path(
          dirname(record$path),
          paste0(record$id, c(".rds", ".txt", ".meta.rds"))
        )
        if (unlink(paths) != 0L) {
          cli_warn("Could not remove an aborted compaction artifact.")
        } else {
          registry$provisional[[id]] <- NULL
        }
      }
      invisible(NULL)
    },

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
      catalogs <- character()
      needs_reader <- FALSE
      if (method %in% c("llm", "text")) {
        # The summary provider may omit every reference. Preserve the handles
        # from both newly compacted evidence and the prior accepted summary.
        references <- compaction_tool_result_references(c(
          plan$previous_summary,
          vapply(
            plan$turns_to_compact,
            private$compaction_turn_text,
            character(1)
          )
        ))
        if (length(references)) {
          handles <- compaction_reference_handles(
            references,
            private$.context_policy,
            private$.session_id,
            private$.agent_id
          )
          catalogs <- handles$catalogs
          private$track_compaction_artifact(handles$record)
          needs_reader <- TRUE
          summary <- trimws(gsub(
            compaction_tool_result_reference_pattern,
            "",
            summary
          ))
          summary <- paste(
            summary,
            "Recoverable tool results:",
            handles$text,
            sep = "\n\n"
          )
        }
      }
      current_system <- private$system_prompt_without_compaction()
      new_system <- paste0(
        current_system,
        private$compaction_prompt_block(summary)
      )
      retire_catalogs <- function(prompt, turns) {
        if (!length(catalogs)) {
          return(invisible(NULL))
        }
        references <- unique(c(
          compaction_tool_result_references(prompt),
          compaction_embedded_references(lapply(turns, function(turn) {
            turn@contents
          }))
        ))
        retire_compaction_catalogs(
          catalogs,
          references,
          private$.context_policy,
          private$.session_id,
          private$.compaction_catalog_registry
        )
      }

      usage <- if (isTRUE(private$run_active)) private$current_run_usage()
      old_prompt <- private$.chat$get_system_prompt()
      old_tools <- if (needs_reader) private$.chat$get_tools()
      had_reader <- private$.tool_result_reader_registered
      tryCatch(
        {
          private$.chat$set_system_prompt(new_system)
          private$.chat$set_turns(plan$turns_to_keep)
          if (needs_reader) private$ensure_tool_result_reader()
        },
        error = function(error) {
          private$.chat$set_system_prompt(old_prompt)
          private$.chat$set_turns(plan$turns)
          if (needs_reader) {
            private$.chat$set_tools(old_tools)
            private$.tool_result_reader_registered <- had_reader
          }
          retire_catalogs(old_prompt, plan$turns)
          rlang::cnd_signal(error)
        }
      )
      private$.compaction_summary <- summary
      if (!is.null(private$.compaction_artifacts)) {
        private$.compaction_artifacts$installed <- TRUE
      }
      retire_catalogs(new_system, plan$turns_to_keep)
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

    compaction_evidence_record = function(value, tool_name) {
      record <- offload_tool_result(
        value = value,
        tool_name = tool_name,
        policy = private$.context_policy,
        session_id = private$.session_id,
        agent_id = private$.agent_id,
        force = compaction_evidence_exceeds_limit(
          value,
          private$.context_policy$max_tool_result_bytes
        )
      )
      private$track_compaction_artifact(record)
      record
    },

    compaction_content_text = function(content) {
      if (inherits(content, "ellmer::ContentToolRequest")) {
        record <- private$compaction_evidence_record(
          list(arguments = content@arguments),
          paste0(content@name, " arguments")
        )
        if (!is.null(record)) {
          return(paste(
            paste0("Tool request: ", content@name, " (", content@id, ")"),
            tool_result_reference_text(record),
            sep = "\n"
          ))
        }
      }
      if (!inherits(content, "ellmer::ContentToolResult")) {
        return(paste(format(content), collapse = "\n"))
      }
      # Keep ordinary structured results intact. Project Content objects through
      # their public formatter, including inside named/nested payloads, without
      # including tool-result display `extra`.
      project_content <- function(value, for_json = FALSE) {
        if (inherits(value, "ellmer::Content")) {
          return(private$compaction_content_text(value))
        }
        if (for_json && is.atomic(value) && !is.null(names(value))) {
          value <- as.list(value)
        }
        if (is.list(value)) {
          value[] <- lapply(value, project_content, for_json = for_json)
        }
        value
      }
      # Serialize public evidence, not S7 class environments: those can be
      # large and their bytes need not survive a save/load round trip.
      is_error <- !is.null(content@error)
      diagnostic <- if (is_error) {
        if (inherits(content@error, "condition")) {
          conditionMessage(content@error)
        } else {
          content@error
        }
      }
      value <- if (is_error) {
        list(error = diagnostic)
      } else {
        project_content(content@value)
      }
      header <- format(content, show = "header")
      if (is_error) {
        header <- paste(header, "Error:")
      }
      # Results supplied as ContentToolResult, including restored turns, can
      # bypass runtime offloading. Bound them before paste/JSON allocates the
      # summary evidence, while keeping public evidence recoverable.
      record <- private$compaction_evidence_record(
        value = value,
        tool_name = if (is.null(content@request)) {
          "compaction_evidence"
        } else {
          content@request@name
        }
      )
      if (!is.null(record)) {
        return(paste(
          header,
          tool_result_reference_text(record),
          sep = "\n"
        ))
      }
      if (is_error) {
        return(paste(header, paste(diagnostic, collapse = "\n")))
      }
      text <- if (
        is.list(content@value) &&
          is.null(names(content@value)) &&
          length(content@value) > 0L &&
          all(vapply(
            content@value,
            inherits,
            logical(1),
            what = "ellmer::Content"
          ))
      ) {
        paste(value, collapse = "\n")
      } else if (is.character(value) && is.null(names(value))) {
        paste(value, collapse = "\n")
      } else {
        as.character(jsonlite::toJSON(
          project_content(value, for_json = TRUE),
          auto_unbox = TRUE,
          digits = NA,
          null = "null"
        ))
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
            references <- compaction_tool_result_references(text)
            text <- paste(
              c(paste0(substr(text, 1, 197), "..."), references),
              collapse = "\n"
            )
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
