# Compaction evidence references, payload size bounds, catalog registries, and
# shared summary fallback helpers.

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

compaction_embedded_references <- function(value, public_only = FALSE) {
  if (is.character(value) || is.factor(value)) {
    return(compaction_tool_result_references(as.character(value)))
  }
  if (inherits(value, "ellmer::Content")) {
    value <- if (!public_only) {
      S7::props(value)
    } else if (inherits(value, "ellmer::ContentToolResult")) {
      list(
        value = value@value,
        error = if (inherits(value@error, "condition")) {
          conditionMessage(value@error)
        } else {
          value@error
        }
      )
    } else if (inherits(value, "ellmer::ContentToolRequest")) {
      value@arguments
    } else {
      public_content_text(value)
    }
    return(compaction_embedded_references(value, public_only))
  }
  if (is.list(value)) {
    return(unique(unlist(
      lapply(value, compaction_embedded_references, public_only = public_only),
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
      compaction_embedded_references(lapply(
        owner$get_context_turns(),
        function(turn) {
          turn@contents
        }
      ))
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

compaction_turn_role <- function(turn, context_label) {
  if (inherits(turn, "ellmer::UserTurn")) {
    return("User")
  }
  if (inherits(turn, "ellmer::AssistantTurn")) {
    return("Assistant")
  }
  cli_warn(c(
    paste0("Unknown turn type in ", context_label),
    "i" = "Got class: {.cls {class(turn)}}",
    "i" = "Defaulting to 'Unknown'"
  ))
  "Unknown"
}

compaction_handle_failure <- function(
  private,
  turns,
  fallback,
  condition,
  usage = AgentUsage(),
  attempts = NULL
) {
  error_message <- conditionMessage(condition)
  if (identical(fallback, "error")) {
    abort_deputy(
      c(
        "Conversation compaction failed.",
        "x" = error_message,
        "i" = "Set ContextPolicy(fallback = 'text') to permit degraded compaction."
      ),
      class = "compaction_error",
      parent = condition
    )
  }
  private$notify(
    "Compaction used the configured deterministic text fallback.",
    level = "warning",
    code = "compact_fallback",
    error = error_message
  )
  result <- list(
    summary = private$generate_fallback_summary(turns),
    method = "text",
    usage = usage
  )
  if (!is.null(attempts)) {
    result$attempts <- attempts
  }
  result
}
