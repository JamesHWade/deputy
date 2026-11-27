#' @include value-properties.R delegation-input.R delegation-content-records.R
NULL

delegation_settled_statuses <- c(
  "completed",
  "failed",
  "stopped",
  "not_started",
  "suspended"
)

delegation_disclosure_abort <- function() {
  cli::cli_abort(
    "Delegation disclosure is not authorized.",
    class = c("deputy_delegation_disclosure", "deputy_error")
  )
}

#' Control who can inspect subagents
#'
#' Decides who may read subagent results and history, through the inspection
#' methods of [Agent] and [LeadAgent] or [delegation_history()]. Pass it as
#' `delegation_disclosure`. `authorize` is where your application checks
#' access; `redact` removes what the requester shouldn't see. By default every
#' request is denied. Authenticate the requester first: a delegation ID alone
#' never grants access.
#' @param authorize A `function(requester, scope)`. Only an exact `TRUE`
#'   allows access; anything else, including an error, denies it. `scope`
#'   holds the agent's `delegation_scope`, `agent_id` and `session_id`, or the
#'   `scope` given to [delegation_history()].
#' @param redact A `function(view, requester)` that returns `view`, as a list,
#'   without anything the requester shouldn't see. The default returns it
#'   unchanged.
#' @param max_bytes Maximum size, in bytes, of one disclosed result; defaults
#'   to 16 MiB. Larger results are an error, so ask for fewer subagents or no
#'   transcripts. Separately, data frames in tool results are replaced by a
#'   placeholder above an estimated 16 MiB.
#' @return A `DelegationDisclosure` object.
#' @export
DelegationDisclosure <- S7::new_class(
  "DelegationDisclosure",
  package = "deputy",
  properties = list(
    authorize = readonly_property("authorize", S7::class_function),
    redact = readonly_property("redact", S7::class_function),
    max_bytes = readonly_property("max_bytes", S7::class_double)
  ),
  constructor = function(
    authorize = function(requester, scope) FALSE,
    redact = function(view, requester) view,
    max_bytes = 16 * 1024^2
  ) {
    if (!is.function(authorize) || !is.function(redact)) {
      cli::cli_abort("Disclosure callbacks must be functions.")
    }
    max_bytes <- validate_positive_int(max_bytes, "max_bytes")
    if (is.null(max_bytes)) {
      cli::cli_abort("max_bytes must be finite.")
    }
    value <- S7::new_object(
      S7::S7_object(),
      authorize = authorize,
      redact = redact,
      max_bytes = as.double(max_bytes)
    )
    freeze_value(value)
  }
)

#' Result of a delegation
#'
#' How one delegation ended. The runtime's record (IDs, `status`,
#' `stop_reason`) is kept apart from what the subagent's model said (`answer`
#' and `claims`). A `"completed"` status means the run ended normally, not
#' that the task succeeded. `finish_reason` is the provider's finish reason for
#' the subagent's final response, and `cut_off` is `TRUE` when the provider cut
#' that response short, so a `"completed"` delegation can still carry a
#' truncated `answer`. [LeadAgent] returns outcomes from
#' `$parallel_delegate()` and, as JSON, from the `delegate_to_agent` tool.
#' Fields are read with `$`.
#' @param runtime List of IDs, `status`, `stop_reason`, `finish_reason`,
#'   `cut_off` and other facts
#'   recorded by the runtime.
#' @param answer The subagent's final reply, cut to 8 KiB. A longer reply is
#'   saved in full in `references`.
#' @param references Saved artifacts, such as the full answer or large tool
#'   results, with their origin and whether they are still available.
#' @param claims The subagent's report of `missing_evidence` and
#'   `unresolved_work` from its structured output. `NULL` means it didn't
#'   report, not that nothing is missing.
#' @return A `DelegationOutcome` object.
#' @export
DelegationOutcome <- S7::new_class(
  "DelegationOutcome",
  package = "deputy",
  properties = list(
    runtime = readonly_property("runtime", S7::class_list),
    answer = readonly_property("answer", S7::class_character),
    references = readonly_property("references", S7::class_list),
    claims = readonly_property("claims", S7::class_list)
  ),
  constructor = function(
    runtime,
    answer = "",
    references = list(),
    claims = list()
  ) {
    inspection_portable(list(runtime, answer, references, claims))
    if (!is.character(answer) || length(answer) != 1L || is.na(answer)) {
      cli::cli_abort("answer must be one text string.")
    }
    value <- S7::new_object(
      S7::S7_object(),
      runtime = runtime,
      answer = answer,
      references = references,
      claims = claims
    )
    freeze_value(value)
  }
)

register_dollar_prop(DelegationDisclosure)
register_dollar_prop(DelegationOutcome)

lead_disclosure <- function(lead) {
  agent_private(lead)$.delegation_disclosure
}

lead_delegation_scope <- function(lead) {
  agent_private(lead)$delegation_scope
}

inspection_bound <- function(x, disclosure) {
  # Replayed S7 turns carry shared class/method metadata. Measure their public
  # data payload, including each replayed copy, without serializing runtime
  # method environments whose size depends on the host R session.
  payload <- function(value) {
    if (inherits(value, "ellmer::Turn")) {
      return(inspection_record_turn(value))
    }
    if (is.list(value)) {
      return(lapply(value, payload))
    }
    value
  }
  if (length(serialize(payload(x), NULL, version = 3)) > disclosure$max_bytes) {
    cli::cli_abort(
      "Delegation disclosure exceeds max_bytes; narrow the selection.",
      class = "deputy_disclosure_bound"
    )
  }
  x
}

inspection_authorize <- function(disclosure, requester, scope) {
  if (!S7::S7_inherits(disclosure, DelegationDisclosure)) {
    delegation_disclosure_abort()
  }
  allowed <- tryCatch(
    disclosure$authorize(requester, scope),
    error = function(e) FALSE
  )
  if (!identical(allowed, TRUE)) {
    delegation_disclosure_abort()
  }
  invisible(NULL)
}

inspection_is_authorized <- function(disclosure, requester, scope) {
  isTRUE(tryCatch(
    {
      inspection_authorize(disclosure, requester, scope)
      TRUE
    },
    deputy_delegation_disclosure = function(error) FALSE
  ))
}

inspection_redact <- function(disclosure, view, requester) {
  redacted <- disclosure$redact(view, requester)
  if (!is.list(redacted)) {
    cli::cli_abort("Disclosure redaction must return a list.")
  }
  inspection_portable(redacted)
  redacted
}

inspection_scope <- function(lead) {
  c(
    lead_delegation_scope(lead),
    list(agent_id = lead$agent_id, session_id = lead$session_id())
  )
}

lead_artifact_storage <- function(lead, record, reference) {
  route <- record$artifact_routing
  if (!is.null(route) && !identical(reference$source, "delegation_answer")) {
    return(list(
      policy = ContextPolicy(offload_dir = route$offload_dir),
      session_id = reference$storage_session_id %||% route$session_id
    ))
  }
  list(
    policy = lead$context_policy,
    session_id = reference$storage_session_id %||% lead$session_id()
  )
}

lead_prepare_outcome <- function(lead, id) {
  private <- agent_private(lead)
  record <- private$subagent_runs[[id]]
  text <- enc2utf8(record$result %||% "")
  record$answer <- inspection_text(text)
  record$answer_truncated <- nchar(text, type = "bytes") > 8192L
  record$references <- lapply(record$artifacts, function(ref) {
    ref$scope <- private$delegation_scope
    ref
  })
  # A policy that saves no tool results saves no long answers either: the
  # outcome keeps the bounded answer without a reference to the rest.
  keep <- record$answer_truncated &&
    !is.null(lead$context_policy$max_tool_result_bytes)
  if (keep) {
    ref <- tryCatch(
      offload_tool_result(
        text,
        "delegate_to_agent",
        lead$context_policy,
        lead$session_id(),
        lead$agent_id,
        force = TRUE
      ),
      error = function(e) NULL
    )
    if (is.null(ref)) {
      record$outcome_error <- "The full answer could not be retained as an artifact."
    } else {
      record$references <- c(
        record$references,
        list(list(
          reference = ref$uri,
          source = "delegation_answer",
          bytes = ref$bytes,
          sha256 = ref$sha256,
          agent_id = record$agent_id,
          run_id = record$run_id,
          delegation_id = id,
          tool_call_id = record$tool_call_id,
          storage_session_id = lead$session_id(),
          scope = private$delegation_scope,
          verification = "not_assessed",
          approval = "not_granted"
        ))
      )
      # Publishing the answer claims shared bytes independently of compaction.
      private$.compaction_catalog_registry$provisional[[ref$id]] <- NULL
      private$ensure_tool_result_reader()
    }
  }
  private$subagent_runs[[id]] <- record
  invisible(NULL)
}

delegation_outcome <- function(record, compact = FALSE) {
  structured <- record$agent_result$structured_output
  claim_omissions <- list()
  claim <- function(name) {
    value <- if (is.list(structured)) structured[[name]]
    if (!is.character(value) || anyNA(value)) {
      return(NULL)
    }
    retained <- utils::head(value, 16L)
    bytes <- sum(nchar(enc2utf8(retained), type = "bytes")) +
      max(0L, length(retained) - 1L)
    claim_omissions[[name]] <<- list(
      omitted_entries = max(0L, length(value) - 16L),
      text_truncated = bytes > 2048L
    )
    inspection_text(
      paste(
        vapply(
          retained,
          inspection_text,
          character(1),
          bytes = 2048L
        ),
        collapse = "\n"
      ),
      2048L
    )
  }
  claims <- list(
    missing_evidence = claim("missing_evidence"),
    unresolved_work = claim("unresolved_work")
  )
  references <- record$references %||% list()
  if (compact && isTRUE(record$answer_truncated)) {
    answer <- vapply(
      references,
      function(ref) identical(ref$source, "delegation_answer"),
      logical(1)
    )
    references <- c(references[answer], references[!answer])
  }
  runtime_fields <- c(
    "delegation_id",
    "agent_id",
    "agent_name",
    "session_id",
    "run_id",
    "parent_agent_id",
    "parent_run_id",
    "parent_delegation_id",
    "depth",
    "root_agent_id",
    "tool_call_id",
    "conversation_handle",
    "previous_delegation_id",
    "host_conversation_id",
    "status",
    "stop_reason",
    "finish_reason"
  )
  runtime <- stats::setNames(
    lapply(runtime_fields, function(field) record[[field]]),
    runtime_fields
  )
  compact_fields <- function(fields) {
    fields$omitted_fields <- names(Filter(
      function(value) {
        is.character(value) &&
          (length(value) != 1L ||
            anyNA(value) ||
            nchar(enc2utf8(value), type = "bytes") > 1024L)
      },
      fields
    ))
    fields[fields$omitted_fields] <- NULL
    fields
  }
  runtime$cut_off <- isTRUE(record$cut_off)
  if (compact) {
    # Display labels may be shortened; opaque correlations must stay exact.
    runtime$agent_name <- inspection_text(runtime$agent_name, 512L)
    # The host's conversation identity is not model context.
    runtime$host_conversation_id <- NULL
    runtime <- compact_fields(runtime)
  }
  DelegationOutcome(
    runtime = c(
      runtime,
      list(
        conversation_id = runtime$session_id,
        task_success = "not_assessed",
        answer_truncated = isTRUE(record$answer_truncated),
        claim_omissions = claim_omissions,
        omitted_references = if (compact) {
          max(0L, length(record$references) - 8L)
        } else {
          0L
        },
        missing_answer = record$outcome_error,
        error = if (!is.null(record$error)) inspection_text(record$error, 1024L)
      )
    ),
    answer = record$answer %||% inspection_text(record$result),
    references = if (compact) {
      lapply(utils::head(references, 8L), function(ref) {
        # Host ownership and storage routing are not model context.
        ref[c("scope", "storage_session_id")] <- NULL
        compact_fields(ref)
      })
    } else {
      record$references %||% list()
    },
    claims = claims
  )
}

# Serialize a settled delegation record into the model-facing tool result,
# rejecting with a bounded diagnostic header when the subagent failed.
delegation_tool_result_payload <- function(
  record,
  failed = FALSE,
  agent_name = record$agent_name %||% "specialist"
) {
  payload <- delegation_json(S7::props(delegation_outcome(
    record,
    compact = TRUE
  )))
  if (isTRUE(failed)) {
    # Preserve the diagnostic label without repeating an unbounded provider
    # error; the bounded payload contains that message.
    ellmer::tool_reject(paste0(
      "Subagent '",
      inspection_text(agent_name, 512L),
      "' failed.\n",
      payload
    ))
  }
  payload
}

lead_inspection_records <- function(lead, delegation_id, transcript) {
  records <- lead_delegation_records(lead, messages = transcript, usage = TRUE)
  if (!is.null(delegation_id)) {
    delegation_id <- delegation_text(delegation_id, "delegation_id")
    records <- Filter(
      function(x) identical(x$delegation_id, delegation_id),
      records
    )
  }
  lapply(records, function(record) {
    lead_inspection_view(lead, record, transcript)
  })
}

# One delegation as a disclosure view. `turns` lets a reader record only part
# of the transcript, such as the turns one continuation added.
lead_inspection_view <- function(
  lead,
  record,
  transcript,
  turns = record$turns
) {
  outcome <- delegation_outcome(record)
  references <- lapply(outcome$references, function(ref) {
    storage <- lead_artifact_storage(lead, record, ref)
    available <- tryCatch(
      {
        read_tool_result_manifest(
          ref$reference,
          storage$policy,
          storage$session_id
        )
        TRUE
      },
      error = function(e) FALSE
    )
    c(ref, list(availability = if (available) "available" else "missing"))
  })
  outcome <- DelegationOutcome(
    outcome$runtime,
    outcome$answer,
    references,
    outcome$claims
  )
  list(
    task = record$task,
    outcome = S7::props(outcome),
    manifest = if (!is.null(record$manifest)) S7::props(record$manifest),
    usage = if (!is.null(record$usage)) S7::props(record$usage),
    cumulative_usage = if (
      !is.null(record$cumulative_usage %||% record$usage)
    ) {
      S7::props(record$cumulative_usage %||% record$usage)
    },
    errors = record[c(
      "error",
      "hook_error",
      "cleanup_error",
      "outcome_error",
      "observation_error"
    )],
    transcript = if (transcript) {
      lapply(turns, inspection_record_turn)
    } else {
      NULL
    },
    retention = list(
      transcript = if (transcript) "included" else "not_requested",
      execution = "read_only",
      continuation = if (is.null(record$conversation_handle)) {
        "unsupported"
      } else {
        "explicit_owner_call"
      }
    )
  )
}

lead_inspect_subagents <- function(
  lead,
  requester,
  delegation_id,
  transcript,
  settled_only = FALSE
) {
  disclosure <- lead_disclosure(lead)
  inspection_authorize(disclosure, requester, inspection_scope(lead))
  if (
    !is.logical(transcript) || length(transcript) != 1L || is.na(transcript)
  ) {
    cli::cli_abort("transcript must be TRUE or FALSE.")
  }
  views <- lead_inspection_records(lead, delegation_id, transcript)
  if (
    settled_only &&
      any(vapply(
        views,
        function(view) {
          !view$outcome$runtime$status %in% delegation_settled_statuses
        },
        logical(1)
      ))
  ) {
    cli::cli_abort("Only settled children can be exported.")
  }
  views <- lapply(views, function(view) {
    inspection_redact(disclosure, view, requester)
  })
  inspection_bound(views, disclosure)
}

#' Replay saved subagent history
#'
#' Turns a snapshot from `$export_subagents()` back into ellmer turns for
#' display, for example in [subagent_chat_server()]. Replaying never runs
#' tools, calls a model or restores a chat. Access is checked again with
#' `disclosure`; the IDs and scope stored in `history` grant nothing. Tool
#' results get back the card they showed, after a check that the saved card
#' holds only the fields and sizes an export can contain; a snapshot that
#' fails the check is an error.
#' @param history A snapshot from `$export_subagents()`.
#' @param requester Who is asking, passed to `disclosure`. Authenticate it
#'   first.
#' @param disclosure A [DelegationDisclosure] for this request.
#' @param scope The scope the history belongs to, from your own records rather
#'   than from `history`. It must match the saved scope exactly.
#' @return A list with one redacted view per subagent, each with ellmer
#'   `turns`. Artifact references are marked `availability = "unresolved"`,
#'   since the saved status may be stale.
#' @export
delegation_history <- function(history, requester, disclosure, scope) {
  inspection_authorize(disclosure, requester, scope)
  inspection_portable(history)
  inspection_bound(history, disclosure)
  if (
    !identical(history$schema_version, 1L) ||
      !identical(history$scope, scope) ||
      !is.list(history$children) ||
      !identical(history$settled, TRUE)
  ) {
    delegation_disclosure_abort()
  }
  views <- lapply(history$children, function(view) {
    if (
      !is.list(view) ||
        (!is.null(view$outcome$runtime$status) &&
          !isTRUE(view$outcome$runtime$status %in% delegation_settled_statuses))
    ) {
      cli::cli_abort("Only settled child history can be replayed.")
    }
    view <- inspection_unresolved_references(view)
    view <- inspection_redact(disclosure, view, requester)
    view$turns <- lapply(view$transcript, inspection_replay)
    view
  })
  inspection_bound(views, disclosure)
}

# A saved artifact's availability may be stale, so replay marks every
# reference "unresolved".
inspection_unresolved_references <- function(view) {
  if (!is.null(view$outcome$references)) {
    view$outcome$references <- lapply(view$outcome$references, function(ref) {
      ref$availability <- "unresolved"
      ref
    })
  }
  view
}

agent_list_subagents <- function(self) {
  runs <- lead_delegation_records(self)
  if (length(runs) == 0) {
    return(data.frame(
      agent_name = character(),
      agent_id = character(),
      parent_agent_id = character(),
      parent_delegation_id = character(),
      depth = integer(),
      root_agent_id = character(),
      session_id = character(),
      run_id = character(),
      parent_run_id = character(),
      delegation_id = character(),
      tool_call_id = character(),
      task = character(),
      status = character(),
      stop_reason = character(),
      input_error = character(),
      admitted_at = as.POSIXct(character()),
      hook_error = character(),
      cleanup_error = character(),
      observation_error = character(),
      started_at = as.POSIXct(character()),
      completed_at = as.POSIXct(character()),
      error = character(),
      stringsAsFactors = FALSE
    ))
  }

  do.call(
    rbind,
    lapply(runs, function(run) {
      data.frame(
        agent_name = run$agent_name,
        agent_id = run$agent_id %||% NA_character_,
        parent_agent_id = run$parent_agent_id %||% NA_character_,
        parent_delegation_id = run$parent_delegation_id %||% NA_character_,
        depth = run$depth %||% NA_integer_,
        root_agent_id = run$root_agent_id %||% NA_character_,
        session_id = run$session_id %||% NA_character_,
        run_id = run$run_id %||% NA_character_,
        parent_run_id = run$parent_run_id %||% NA_character_,
        delegation_id = run$delegation_id %||% NA_character_,
        tool_call_id = run$tool_call_id %||% NA_character_,
        task = run$task,
        status = run$status,
        stop_reason = run$stop_reason %||% NA_character_,
        input_error = run$input_error %||% NA_character_,
        admitted_at = as.POSIXct(run$admitted_at, tz = "UTC"),
        hook_error = run$hook_error %||% NA_character_,
        cleanup_error = run$cleanup_error %||% NA_character_,
        observation_error = run$observation_error %||% NA_character_,
        started_at = as.POSIXct(run$started_at, tz = "UTC"),
        completed_at = as.POSIXct(run$completed_at, tz = "UTC"),
        error = run$error %||% NA_character_,
        stringsAsFactors = FALSE
      )
    })
  )
}

agent_read_subagent_result <- function(
  self,
  private,
  requester,
  delegation_id,
  reference,
  offset = 0L
) {
  views <- lead_inspect_subagents(self, requester, delegation_id, FALSE)
  references <- unlist(
    lapply(views, function(view) view$outcome$references),
    recursive = FALSE
  )
  selected <- Filter(
    function(ref) identical(ref$reference, reference),
    references
  )
  if (
    !is.character(reference) ||
      length(reference) != 1L ||
      is.na(reference) ||
      !length(selected)
  ) {
    delegation_disclosure_abort()
  }
  # Disclosure authorizes the public reference. Storage routing remains
  # host-owned even when the redactor removes or replaces private metadata.
  records <- Filter(
    function(record) identical(record$delegation_id, delegation_id),
    lead_delegation_records(self)
  )
  stored <- if (length(records) == 1L) {
    Filter(
      function(ref) identical(ref$reference, reference),
      records[[1L]]$references
    )
  } else {
    list()
  }
  if (!length(stored)) {
    delegation_disclosure_abort()
  }
  record <- records[[1L]]
  storage <- lead_artifact_storage(self, record, stored[[1L]])
  chunk <- read_tool_result_chunk(
    reference,
    offset = offset,
    max_chars = 8192L,
    policy = storage$policy,
    session_id = storage$session_id
  )
  disclosure <- lead_disclosure(self)
  view <- inspection_redact(
    disclosure,
    list(kind = "artifact", reference = reference, result = chunk),
    requester
  )
  inspection_bound(view, disclosure)
}
