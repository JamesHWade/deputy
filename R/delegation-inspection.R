#' @include value-properties.R delegation-input.R
NULL

delegation_disclosure_abort <- function() {
  cli::cli_abort(
    "Delegation disclosure is not authorized.",
    class = c("deputy_delegation_disclosure", "deputy_error")
  )
}

#' Authorize and redact child conversation inspection
#'
#' Hosts authenticate requesters before calling inspection methods. Identifiers
#' are routing locators, never access grants. Authorization runs before record
#' lookup; redaction runs before each snapshot leaves Deputy. These trusted host
#' callbacks never run as model tools. The default denies all disclosures.
#' @param authorize Function of `requester` and fixed host `scope`; only an exact
#'   `TRUE` permits disclosure. Errors deny access without disclosing details.
#' @param redact Function of `view` and `requester`, returning a redacted list.
#'   It may remove fields or content. It must not perform agent execution.
#' @param max_bytes Maximum serialized bytes in one disclosed snapshot or saved
#'   history. Oversized disclosures fail explicitly; select fewer children or
#'   omit transcripts. Defaults to 16 MiB.
#' @return Read-only `DelegationDisclosure` host configuration.
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
    max_bytes <- context_policy_whole_number(max_bytes, "max_bytes")
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

#' Inspect a compact delegation outcome
#'
#' Runtime identity and stop facts are separate from model-authored answer and
#' claims. `completed` means execution ended normally, not verified task success.
#' Outcomes are produced by [LeadAgent] and are read-only portable values.
#' @param runtime Plain runtime identity, status and stop-reason record.
#' @param answer Bounded model-authored answer text.
#' @param references Scoped artifact locators, with provenance and availability.
#'   References never confer authorization, verification or approval.
#' @param claims Model-authored missing-evidence and unresolved-work claims.
#'   `NULL` means not supplied, not that no work or evidence is missing.
#' @return A read-only `DelegationOutcome`.
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

local({
  S7::method(`$`, DelegationDisclosure) <- function(x, name) S7::prop(x, name)
  S7::method(`$`, DelegationOutcome) <- function(x, name) S7::prop(x, name)
})

inspection_portable <- function(x, depth = 0L) {
  if (
    depth > 64L ||
      is.object(x) ||
      !(is.null(x) || is.atomic(x) || is.list(x)) ||
      !all(names(attributes(x)) %in% c("names", "dim", "dimnames"))
  ) {
    cli::cli_abort("Inspection history must contain portable data only.")
  }
  if (is.list(x)) {
    lapply(x, inspection_portable, depth = depth + 1L)
  }
  invisible(NULL)
}

inspection_bound <- function(x, disclosure) {
  if (length(serialize(x, NULL, version = 3)) > disclosure$max_bytes) {
    cli::cli_abort(
      "Delegation disclosure exceeds max_bytes; narrow the selection."
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

inspection_scope <- function(lead) {
  c(
    lead$.__enclos_env__$private$delegation_scope,
    list(agent_id = lead$agent_id, session_id = lead$session_id())
  )
}

inspection_text <- function(text, bytes = 8192L) {
  text <- enc2utf8(text %||% "")
  # Starting with at most `bytes` characters bounds the UTF-8 trim work.
  text <- substr(text, 1L, bytes)
  while (nchar(text, type = "bytes") > bytes) {
    text <- substr(text, 1L, nchar(text) - 1L)
  }
  text
}

lead_prepare_outcome <- function(lead, id) {
  private <- lead$.__enclos_env__$private
  record <- private$subagent_runs[[id]]
  text <- record$result %||% ""
  record$answer <- inspection_text(text)
  record$answer_truncated <- nchar(text, type = "bytes") > 8192L
  record$references <- lapply(record$artifacts, function(ref) {
    ref$scope <- private$delegation_scope
    ref
  })
  if (record$answer_truncated) {
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
      private$ensure_tool_result_reader()
    }
  }
  private$subagent_runs[[id]] <- record
  invisible(NULL)
}

delegation_outcome <- function(record, compact = FALSE) {
  structured <- record$agent_result$structured_output
  claim <- function(name) {
    value <- if (is.list(structured)) structured[[name]]
    if (!is.character(value) || anyNA(value)) {
      return(NULL)
    }
    inspection_text(paste(head(value, 16L), collapse = "\n"), 2048L)
  }
  DelegationOutcome(
    runtime = c(
      record[c(
        "delegation_id",
        "agent_id",
        "agent_name",
        "session_id",
        "run_id",
        "parent_agent_id",
        "parent_run_id",
        "tool_call_id",
        "status",
        "stop_reason"
      )],
      list(
        conversation_id = record$session_id,
        task_success = "not_assessed",
        answer_truncated = isTRUE(record$answer_truncated),
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
      head(record$references %||% list(), 8L)
    } else {
      record$references %||% list()
    },
    claims = list(
      missing_evidence = claim("missing_evidence"),
      unresolved_work = claim("unresolved_work")
    )
  )
}

# Preserve released ellmer Content records; omit provider-private payloads,
# hidden thinking, executable tool definitions and arbitrary display extras.
inspection_record_turn <- function(turn) {
  turn <- portable_session_turns(list(turn))[[1L]]
  if ("json" %in% S7::prop_names(turn)) {
    turn@json <- list()
  }
  clean <- function(content) {
    if (inherits(content, "ellmer::ContentThinking")) {
      return(NULL)
    }
    if (inherits(content, "ellmer::ContentToolResult")) {
      content@extra <- list()
      if (!is.null(content@request)) content@request <- clean(content@request)
    }
    content
  }
  turn@contents <- Filter(Negate(is.null), lapply(turn@contents, clean))
  if ("cost" %in% S7::prop_names(turn)) {
    turn@cost <- as.numeric(turn@cost)
  }
  record <- ellmer::contents_record(turn)
  inspection_portable(record)
  record
}

inspection_replay <- function(record) {
  allowed <- paste0(
    "ellmer::",
    c(
      "UserTurn",
      "AssistantTurn",
      "SystemTurn",
      "ContentText",
      "ContentImageInline",
      "ContentImageRemote",
      "ContentPDF",
      "ContentDocument",
      "ContentToolRequest",
      "ContentToolResult",
      "ContentCitation",
      "ContentToolRequestSearch",
      "ContentToolResponseSearch",
      "ContentToolRequestFetch",
      "ContentToolResponseFetch"
    )
  )
  validate <- function(x) {
    if (!is.list(x)) {
      return(invisible(NULL))
    }
    if (all(c("version", "class", "props") %in% names(x))) {
      if (!identical(x$version, 1) && !identical(x$version, 1L)) {
        cli::cli_abort("Unsupported ellmer content record version.")
      }
      if (
        !is.character(x$class) || length(x$class) != 1L || !x$class %in% allowed
      ) {
        cli::cli_abort("Unsupported inspection content class.")
      }
      if (
        !is.null(x$props$tool) ||
          length(x$props$extra) > 0L ||
          length(x$props$json) > 0L
      ) {
        cli::cli_abort(
          "Inspection history cannot restore executable or private content."
        )
      }
    }
    lapply(x, validate)
    invisible(NULL)
  }
  inspection_portable(record)
  validate(record)
  ellmer::contents_replay(record, tools = list())
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
    outcome <- delegation_outcome(record)
    references <- lapply(outcome$references, function(ref) {
      available <- tryCatch(
        {
          read_tool_result_manifest(
            ref$reference,
            lead$context_policy,
            ref$storage_session_id
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
      cumulative_usage = if (!is.null(record$usage)) S7::props(record$usage),
      errors = record[c(
        "error",
        "hook_error",
        "cleanup_error",
        "outcome_error"
      )],
      transcript = if (transcript) {
        lapply(record$turns, inspection_record_turn)
      } else {
        NULL
      },
      retention = list(
        transcript = if (transcript) "included" else "not_requested",
        execution = "read_only",
        continuation = "unsupported"
      )
    )
  })
}

lead_inspect_subagents <- function(lead, requester, delegation_id, transcript) {
  private <- lead$.__enclos_env__$private
  disclosure <- private$.delegation_disclosure
  inspection_authorize(disclosure, requester, inspection_scope(lead))
  if (
    !is.logical(transcript) || length(transcript) != 1L || is.na(transcript)
  ) {
    cli::cli_abort("transcript must be TRUE or FALSE.")
  }
  views <- lead_inspection_records(lead, delegation_id, transcript)
  views <- lapply(views, function(view) {
    view <- disclosure$redact(view, requester)
    if (!is.list(view)) {
      cli::cli_abort("Disclosure redaction must return a list.")
    }
    inspection_portable(view)
    view
  })
  inspection_bound(views, disclosure)
}

#' Replay authorized settled child history
#'
#' Replays host-owned snapshots from `LeadAgent$export_subagents()` using public
#' ellmer Content records. No Chat, model request, tools, or active execution is
#' restored. Hosts own durable storage and authenticate the supplied history;
#' this function does not treat stored scope or IDs as authorization.
#' @param history A portable snapshot produced by `export_subagents()`.
#' @param requester Authenticated host request context.
#' @param disclosure A freshly host-bound [DelegationDisclosure].
#' @param scope Current host scope, matched exactly against the saved scope after
#'   authorization. Obtain it from the host's own durable ownership record.
#' @return Authorized, redacted child views with native ellmer `turns` added for
#'   read-only rendering. Artifact availability is `unresolved` until the host
#'   checks its retained storage; saved availability is never treated as current.
#' @export
delegation_history <- function(history, requester, disclosure, scope) {
  inspection_authorize(disclosure, requester, scope)
  inspection_portable(history)
  inspection_bound(history, disclosure)
  if (
    !identical(history$schema_version, 1L) ||
      !identical(history$scope, scope) ||
      !is.list(history$children)
  ) {
    delegation_disclosure_abort()
  }
  views <- lapply(history$children, function(view) {
    if (
      !is.list(view) ||
        !view$outcome$runtime$status %in%
          c("completed", "failed", "stopped", "not_started", "suspended")
    ) {
      cli::cli_abort("Only settled child history can be replayed.")
    }
    view <- disclosure$redact(view, requester)
    inspection_portable(view)
    if (!is.list(view)) {
      cli::cli_abort("Disclosure redaction must return a list.")
    }
    view$turns <- lapply(view$transcript, inspection_replay)
    view$outcome$references <- lapply(view$outcome$references, function(ref) {
      ref$availability <- "unresolved"
      ref
    })
    view
  })
  inspection_bound(views, disclosure)
}
