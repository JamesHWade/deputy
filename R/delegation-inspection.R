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
#' @param max_bytes Maximum serialized content-payload bytes in one disclosed
#'   snapshot or saved history, including replayed turn content but excluding
#'   shared R class/method metadata. Oversized disclosures fail explicitly;
#'   select fewer children or omit transcripts. Defaults to 16 MiB.
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

inspection_duration_omission <-
  "[Unsupported duration payload omitted from retained history.]"

inspection_data_frame_rows <- function(value) {
  row_names <- unclass(attr(unclass(value), "row.names", exact = TRUE))
  if (
    length(row_names) == 2L &&
      is.na(row_names[[1L]]) &&
      is.numeric(row_names[[2L]]) &&
      row_names[[2L]] < 0L
  ) {
    return(-row_names[[2L]])
  }
  length(row_names)
}

inspection_duration_shape_supported <- function(value) {
  if (!inherits(value, "difftime") || length(class(value)) != 1L) {
    return(FALSE)
  }
  units <- attr(value, "units", exact = TRUE)
  if (
    !is.character(units) ||
      is.object(units) ||
      length(units) != 1L ||
      is.na(units)
  ) {
    return(FALSE)
  }
  if (!units %in% c("secs", "mins", "hours", "days", "weeks")) {
    return(FALSE)
  }
  attributes <- attributes(value)
  if (!all(names(attributes) %in% c("class", "units"))) {
    return(FALSE)
  }
  values <- unclass(value)
  is.numeric(values) && !is.object(values)
}

inspection_duration_supported <- function(value) {
  if (!inspection_duration_shape_supported(value)) {
    return(FALSE)
  }
  values <- unclass(value)
  !any(is.nan(values) | is.infinite(values))
}

inspection_duration_projection <- function(value) {
  if (inherits(value, "difftime")) {
    if (!inspection_duration_supported(value)) {
      return(inspection_duration_omission)
    }
    return(list(
      value = as.double(unclass(value)),
      units = attr(value, "units", exact = TRUE)
    ))
  }
  if (is.data.frame(value)) {
    columns <- unclass(value)
    column_names <- unclass(attr(columns, "names", exact = TRUE))
    row_names <- unclass(attr(columns, "row.names", exact = TRUE))
    rows <- inspection_data_frame_rows(value)
    columns <- lapply(columns, function(column) {
      if (inherits(column, "difftime")) {
        projected <- inspection_duration_projection(column)
        if (identical(projected, inspection_duration_omission)) {
          return(rep(inspection_duration_omission, rows))
        }
        values <- projected$value
        units <- projected$units
        if (length(values) != rows) {
          return(rep(inspection_duration_omission, rows))
        }
        return(lapply(seq_len(rows), function(index) {
          list(
            value = if (is.na(values[[index]])) NA_real_ else values[[index]],
            units = units
          )
        }))
      }
      if (is.data.frame(column)) {
        if (inspection_data_frame_rows(column) != rows) {
          return(rep(inspection_duration_omission, rows))
        }
        return(inspection_duration_projection(column))
      }
      as_is <- inherits(column, "AsIs")
      if (
        is.list(column) &&
          (!is.object(column) || as_is) &&
          !inherits(column, "POSIXlt")
      ) {
        raw_column <- if (as_is) unclass(column) else column
        if (length(raw_column) != rows) {
          return(rep(inspection_duration_omission, rows))
        }
        return(lapply(
          seq_len(rows),
          function(index) inspection_duration_projection(raw_column[[index]])
        ))
      }
      column
    })
    return(structure(
      columns,
      names = column_names,
      row.names = row_names,
      class = "data.frame"
    ))
  }
  as_is <- inherits(value, "AsIs")
  if (
    is.list(value) &&
      (!is.object(value) || as_is) &&
      !inherits(value, "POSIXlt")
  ) {
    raw_value <- if (as_is) unclass(value) else value
    return(lapply(raw_value, inspection_duration_projection))
  }
  value
}

inspection_duration_json <- function(value) {
  projected <- inspection_duration_projection(value)
  if (identical(projected, inspection_duration_omission)) {
    return(inspection_duration_omission)
  }
  as.character(jsonlite::toJSON(
    projected,
    dataframe = "rows",
    auto_unbox = TRUE,
    null = "null",
    na = "null"
  ))
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
  private <- lead$.__enclos_env__$private
  record <- private$subagent_runs[[id]]
  text <- enc2utf8(record$result %||% "")
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
    "status",
    "stop_reason"
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
  if (compact) {
    # Display labels may be shortened; opaque correlations must stay exact.
    runtime$agent_name <- inspection_text(runtime$agent_name, 512L)
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
    if (inherits(content, "ellmer::Content")) {
      if ("extra" %in% S7::prop_names(content)) {
        content@extra <- list()
      }
      if (inherits(content, "ellmer::ContentToolRequest")) {
        content@tool <- NULL
      }
      if (inherits(content, "ellmer::ContentToolResult")) {
        if (inherits(content@error, "condition")) {
          content@error <- conditionMessage(content@error)
        }
        if (!is.null(content@request)) {
          content@request <- clean(content@request)
        }
        content@value <- clean(content@value)
      }
    } else if (
      is.data.frame(content) ||
        is.factor(content) ||
        inherits(content, c("Date", "POSIXt", "difftime"))
    ) {
      if (inherits(content, "difftime") || is.data.frame(content)) {
        content <- inspection_duration_json(content)
      } else {
        content <- as.character(jsonlite::toJSON(
          content,
          dataframe = "rows",
          auto_unbox = TRUE,
          null = "null",
          na = "null"
        ))
      }
    } else if (is.object(content)) {
      # Unknown application classes have no portable public record contract.
      # Do not execute their format/record methods or lose sibling histories.
      content <- "[Unsupported tool payload omitted from retained history.]"
    } else if (is.list(content) && !is.object(content)) {
      content <- lapply(
        Filter(function(x) !inherits(x, "ellmer::ContentThinking"), content),
        clean
      )
    }
    content
  }
  turn@contents <- Filter(Negate(is.null), lapply(turn@contents, clean))
  if ("cost" %in% S7::prop_names(turn)) {
    turn@cost <- as.numeric(turn@cost)
  }
  record <- inspection_record_content(turn)
  inspection_portable(record)
  record
}

# Mark genuinely typed tool values before serializing; application objects can
# legitimately have the same field names as an ellmer record.
inspection_record_content <- function(content) {
  # Tool arguments are JSON data, never nested native content. Validate them
  # before recording can turn an S7 object into an ordinary data record.
  if (inherits(content, "ellmer::ContentToolRequest")) {
    approval_portable(content@arguments)
    approval_json_inputs(content@arguments)
  }
  record <- ellmer::contents_record(content)
  for (field in names(record$props)) {
    value <- S7::prop(content, field)
    if (inherits(value, "S7_object")) {
      record$props[[field]] <- inspection_record_content(value)
    } else if (
      is.list(value) &&
        length(value) &&
        all(vapply(value, inherits, logical(1), "S7_object"))
    ) {
      record$props[[field]] <- lapply(value, inspection_record_content)
    }
  }
  if (inherits(content, "ellmer::ContentToolResult")) {
    paths <- list()
    record_value <- function(value, path = integer()) {
      if (inherits(value, "ellmer::Content")) {
        paths[[length(paths) + 1L]] <<- path
        return(inspection_record_content(value))
      }
      if (is.list(value) && !is.object(value)) {
        for (i in seq_along(value)) {
          value[i] <- list(record_value(value[[i]], c(path, i)))
        }
      }
      value
    }
    record$props$value <- record_value(content@value)
    record$deputy_value_kind <- "marked"
    record$deputy_content_paths <- paths
  }
  record
}

inspection_replay <- function(record, sanitize = FALSE) {
  allowed <- paste0(
    "ellmer::",
    c(
      "UserTurn",
      "AssistantTurn",
      "AssistantPartialTurn",
      "SystemTurn",
      "ContentText",
      "ContentJson",
      "ContentUploaded",
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
      "ContentToolResponseFetch",
      "Source",
      "WebSource"
    )
  )
  inspection_portable(record)
  reject_hidden_record <- function(value) {
    if (!is.list(value)) {
      return(invisible(NULL))
    }
    if (
      identical(value$class, "ellmer::ContentThinking") &&
        all(c("version", "class", "props") %in% names(value))
    ) {
      cli::cli_abort(
        "Untyped tool data cannot contain private thinking records."
      )
    }
    lapply(value, reject_hidden_record)
    invisible(NULL)
  }
  replay <- function(x) {
    if (!is.list(x) || !all(c("version", "class", "props") %in% names(x))) {
      cli::cli_abort("Invalid inspection content record.")
    }
    if (!identical(x$version, 1) && !identical(x$version, 1L)) {
      cli::cli_abort("Unsupported ellmer content record version.")
    }
    if (isTRUE(sanitize) && identical(x$class, "ellmer::ContentThinking")) {
      return(NULL)
    }
    if (
      !is.character(x$class) || length(x$class) != 1L || !x$class %in% allowed
    ) {
      cli::cli_abort("Unsupported inspection content class.")
    }
    props <- x$props
    if (isTRUE(sanitize)) {
      # Only typed content positions reach replay(). Opaque tool data keeps its
      # meaning, while executable/private properties are never reconstructed.
      props$tool <- NULL
      if ("extra" %in% names(props)) {
        props$extra <- list()
      }
      if ("json" %in% names(props)) {
        props$json <- list()
      }
      if (identical(x$class, "ellmer::ContentToolRequest")) {
        reject_hidden_record(props$arguments)
      }
    }
    if (
      !is.null(props$tool) ||
        length(props$extra) > 0L ||
        length(props$json) > 0L
    ) {
      cli::cli_abort(
        "Inspection history cannot restore executable or private content."
      )
    }
    if (
      x$class %in%
        paste0(
          "ellmer::",
          c("UserTurn", "AssistantTurn", "AssistantPartialTurn", "SystemTurn")
        )
    ) {
      props$contents <- Filter(Negate(is.null), lapply(props$contents, replay))
    }
    if (identical(x$class, "ellmer::ContentToolResult")) {
      if (!is.null(props$request)) {
        props$request <- replay(props$request)
      }
      kind <- x$deputy_value_kind %||% "data"
      if (!kind %in% c("content", "contents", "data", "marked")) {
        cli::cli_abort("Invalid tool payload kind.")
      }
      props$value <- switch(
        kind,
        content = replay(props$value),
        contents = lapply(props$value, replay),
        data = props$value,
        marked = {
          restore_path <- function(value, path) {
            if (!length(path)) {
              return(replay(value))
            }
            index <- path[[1L]]
            if (
              !is.list(value) ||
                !is.numeric(index) ||
                length(index) != 1L ||
                is.na(index) ||
                index < 1L ||
                index > length(value) ||
                index != as.integer(index)
            ) {
              cli::cli_abort("Invalid tool content position.")
            }
            value[index] <- list(restore_path(value[[index]], path[-1L]))
            value
          }
          value <- props$value
          for (path in x$deputy_content_paths) {
            value <- restore_path(value, path)
          }
          value
        }
      )
      if (isTRUE(sanitize)) {
        # Resolve typed positions first, then reject private record shapes left
        # in opaque data. Caller-supplied markers cannot exempt unmarked data.
        reject_hidden_record(props$value)
      }
    }
    if (
      identical(x$class, "ellmer::ContentCitation") && !is.null(props$source)
    ) {
      props$source <- replay(props$source)
    }
    if (identical(x$class, "ellmer::ContentToolResponseSearch")) {
      props$sources <- lapply(props$sources, replay)
    }
    # The native constructor must never interpret opaque application objects as
    # record envelopes. Restore list-valued properties only after construction.
    safe <- x
    safe$version <- 1
    safe$props <- props
    for (field in names(props)) {
      if (is.list(props[[field]]) || inherits(props[[field]], "S7_object")) {
        safe$props[field] <- list(
          if (field %in% c("request", "source")) NULL else list()
        )
      }
    }
    out <- ellmer::contents_replay(safe, tools = list())
    for (field in names(props)) {
      S7::prop(out, field) <- props[[field]]
    }
    out
  }
  replay(record)
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
        lapply(record$turns, inspection_record_turn)
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
  })
}

lead_inspect_subagents <- function(
  lead,
  requester,
  delegation_id,
  transcript,
  settled_only = FALSE
) {
  private <- lead$.__enclos_env__$private
  disclosure <- private$.delegation_disclosure
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
          !view$outcome$runtime$status %in%
            c("completed", "failed", "stopped", "not_started", "suspended")
        },
        logical(1)
      ))
  ) {
    cli::cli_abort("Only settled children can be exported.")
  }
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
      !is.list(history$children) ||
      !identical(history$settled, TRUE)
  ) {
    delegation_disclosure_abort()
  }
  views <- lapply(history$children, function(view) {
    if (
      !is.list(view) ||
        (!is.null(view$outcome$runtime$status) &&
          !isTRUE(
            view$outcome$runtime$status %in%
              c("completed", "failed", "stopped", "not_started", "suspended")
          ))
    ) {
      cli::cli_abort("Only settled child history can be replayed.")
    }
    if (!is.null(view$outcome$references)) {
      view$outcome$references <- lapply(view$outcome$references, function(ref) {
        ref$availability <- "unresolved"
        ref
      })
    }
    view <- disclosure$redact(view, requester)
    inspection_portable(view)
    if (!is.list(view)) {
      cli::cli_abort("Disclosure redaction must return a list.")
    }
    view$turns <- lapply(view$transcript, inspection_replay)

    view
  })
  inspection_bound(views, disclosure)
}
