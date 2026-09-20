#' @include value-properties.R delegation-input.R delegation-inspection.R
NULL

# A host-selected fork is deliberately a small value. It contains the
# authenticated locator and an inert public projection of selected turns; it
# never contains an ellmer Chat, a tool closure, or a callback.

context_fork_abort <- function(reason, message) {
  cli::cli_abort(
    message,
    class = c(
      "deputy_context_fork_error",
      "deputy_delegation_input_error",
      "deputy_error"
    ),
    reason = reason,
    .envir = parent.frame()
  )
}

context_fork_point <- function(value) {
  if (is.character(value)) {
    return(delegation_text(value, "fork_point"))
  }
  if (
    is.numeric(value) &&
      length(value) == 1L &&
      !is.na(value) &&
      is.finite(value) &&
      value >= 0 &&
      value <= .Machine$integer.max &&
      value == floor(value) &&
      is.null(attributes(value))
  ) {
    return(as.integer(value))
  }
  context_fork_abort(
    "invalid",
    "{.arg fork_point} must be a non-negative turn number or host token."
  )
}

context_fork_content_id <- function(content) {
  if (!inherits(content, "ellmer::ContentToolRequest")) {
    return(NULL)
  }
  if (!"id" %in% S7::prop_names(content)) {
    return(NULL)
  }
  id <- tryCatch(S7::prop(content, "id"), error = function(error) NULL)
  if (
    is.null(id) ||
      !is.character(id) ||
      length(id) != 1L ||
      is.na(id) ||
      !is.null(attributes(id)) ||
      !nzchar(id)
  ) {
    return(NULL)
  }
  id
}

context_fork_tool_ids <- function(turns) {
  # Tool rounds are turn-level units. A provider may place several requests in
  # one assistant turn and the corresponding results in the immediately
  # following user turn; flattening individual contents would incorrectly make
  # request A/request B/result A/result B look like two orphaned requests.
  roles <- vapply(
    turns,
    function(turn) {
      if (inherits(turn, "ellmer::AssistantTurn")) {
        return("assistant")
      }
      "user"
    },
    character(1)
  )
  by_turn <- lapply(turns, function(turn) {
    events <- list()
    for (content in turn@contents) {
      if (inherits(content, "ellmer::ContentToolRequest")) {
        events[[length(events) + 1L]] <- list(
          kind = "request",
          id = context_fork_content_id(content)
        )
      } else if (inherits(content, "ellmer::ContentToolResult")) {
        request <- tryCatch(content@request, error = function(error) NULL)
        events[[length(events) + 1L]] <- list(
          kind = "result",
          id = context_fork_content_id(request)
        )
      }
    }
    events
  })
  events <- unlist(by_turn, recursive = FALSE)
  ids <- vapply(
    events,
    function(event) event$id %||% NA_character_,
    character(1)
  )
  known_ids <- ids[!is.na(ids) & nzchar(ids)]
  counts <- table(known_ids)
  valid_ids <- names(counts[counts == 2L])
  if (length(valid_ids)) {
    valid_ids <- valid_ids[vapply(
      valid_ids,
      function(id) {
        matching <- events[which(ids == id)]
        sum(vapply(matching, `[[`, character(1), "kind") == "request") == 1L &&
          sum(vapply(matching, `[[`, character(1), "kind") == "result") == 1L
      },
      logical(1)
    )]
  }
  settled_ids <- character()
  if (length(by_turn) > 1L) {
    for (index in seq_len(length(by_turn) - 1L)) {
      requests <- by_turn[[index]]
      results <- by_turn[[index + 1L]]
      requests <- Filter(function(event) event$kind == "request", requests)
      results <- Filter(function(event) event$kind == "result", results)
      current_kinds <- vapply(by_turn[[index]], `[[`, character(1), "kind")
      next_kinds <- vapply(
        by_turn[[index + 1L]],
        `[[`,
        character(1),
        "kind"
      )
      request_ids <- vapply(
        requests,
        function(event) event$id %||% NA_character_,
        character(1)
      )
      result_ids <- vapply(
        results,
        function(event) event$id %||% NA_character_,
        character(1)
      )
      if (
        length(request_ids) &&
          identical(roles[[index]], "assistant") &&
          identical(roles[[index + 1L]], "user") &&
          all(current_kinds == "request") &&
          all(next_kinds == "result") &&
          setequal(request_ids, result_ids) &&
          !anyNA(request_ids) &&
          all(nzchar(request_ids)) &&
          all(request_ids %in% valid_ids) &&
          !anyDuplicated(request_ids)
      ) {
        settled_ids <- c(settled_ids, request_ids)
      }
    }
  }
  settled_ids <- unique(settled_ids)
  incomplete_ids <- unique(ids[is.na(ids) | !ids %in% settled_ids])
  incomplete_ids[is.na(incomplete_ids)] <- ""
  list(
    incomplete = incomplete_ids,
    replacements = sum(is.na(ids) | !ids %in% settled_ids)
  )
}

context_fork_inert_json <- function(value) {
  # The input has already passed the shared sanitized record/replay boundary.
  # Reuse its typed value projection for nested native Content as well.
  candidate <- inspection_record_content(
    ellmer::ContentToolResult(value = value)
  )$props$value
  tryCatch(
    as.character(jsonlite::toJSON(
      candidate,
      auto_unbox = TRUE,
      null = "null",
      dataframe = "rows"
    )),
    error = function(error) {
      if (is.character(candidate)) {
        return(inspection_text(paste(candidate, collapse = "\n"), 4096L))
      }
      if (is.atomic(candidate)) {
        return(inspection_text(
          paste(as.character(candidate), collapse = ", "),
          4096L
        ))
      }
      if (is.list(candidate) && !is.object(candidate)) {
        return(paste0(
          "<inert list with ",
          length(candidate),
          " entries>"
        ))
      }
      paste0(
        "<inert public value: ",
        paste(class(candidate), collapse = "/"),
        ">"
      )
    }
  )
}

context_fork_inert_content <- function(content) {
  if (inherits(content, "ellmer::ContentToolRequest")) {
    name <- tryCatch(S7::prop(content, "name"), error = function(error) NULL)
    arguments <- tryCatch(
      S7::prop(content, "arguments"),
      error = function(error) list()
    )
    detail <- context_fork_inert_json(arguments)
    label <- paste0(
      "[Inert incomplete tool evidence: ",
      name %||% "unknown",
      "; arguments=",
      detail,
      "]"
    )
  } else {
    value <- tryCatch(content@value, error = function(error) NULL)
    error_text <- tryCatch(
      if (inherits(content@error, "condition")) {
        conditionMessage(content@error)
      } else if (
        is.character(content@error) &&
          length(content@error) == 1L &&
          !is.na(content@error)
      ) {
        content@error
      } else {
        NULL
      },
      error = function(error) NULL
    )
    detail <- context_fork_inert_json(value)
    label <- paste0(
      "[Inert incomplete tool evidence; value=",
      detail,
      if (!is.null(error_text)) paste0("; error=", error_text) else "",
      "]"
    )
  }
  ellmer::ContentText(label)
}

context_fork_sanitize_turns <- function(turns, tool_ids) {
  upload_omitted <- FALSE
  sanitize <- function(content) {
    # Raw ellmer tool records do not mark which nested lists were Content.
    # Conservatively omit upload-shaped records too, without reconstructing
    # other ordinary record-shaped application data.
    upload_record <- is.list(content) &&
      !is.object(content) &&
      all(c("version", "class", "props") %in% names(content)) &&
      identical(content$class, "ellmer::ContentUploaded")
    if (inherits(content, "ellmer::ContentUploaded") || upload_record) {
      upload_omitted <<- TRUE
      return(ellmer::ContentText(
        "[Provider upload omitted: supply portable content for this fork.]"
      ))
    }
    if (inherits(content, "ellmer::ContentToolRequest")) {
      id <- context_fork_content_id(content)
      if (is.null(id) || id %in% tool_ids$incomplete) {
        return(context_fork_inert_content(content))
      }
      return(content)
    }
    if (inherits(content, "ellmer::ContentToolResult")) {
      content@value <- sanitize(content@value)
      request <- tryCatch(content@request, error = function(error) NULL)
      id <- context_fork_content_id(request)
      if (is.null(id) || id %in% tool_ids$incomplete) {
        return(context_fork_inert_content(content))
      }
      return(content)
    }
    if (is.list(content) && !is.object(content)) {
      return(lapply(content, sanitize))
    }
    content
  }
  turns <- lapply(turns, function(turn) {
    if (!inherits(turn, "ellmer::Turn")) {
      return(turn)
    }
    turn@contents <- lapply(turn@contents, sanitize)
    turn
  })
  list(
    turns = turns,
    omissions = if (upload_omitted) "provider_upload" else character()
  )
}

context_fork_input_bound <- function(turns, max_bytes) {
  # Walk only the public S7 properties used by the existing observation
  # projection. Native turns can carry provider state and tool closures, so
  # serializing them here would defeat the bound before inspection_record_turn
  # has removed those fields.  The projected inert records are checked again
  # after inspection for their exact portable size.
  if (!observation_payload_fits(turns, max_bytes)) {
    context_fork_abort(
      "oversized",
      "The selected public fork turns exceed max_bytes."
    )
  }
  invisible(NULL)
}

context_fork_turn_records <- function(turns, max_bytes, max_turns) {
  if (!is.list(turns) || is.object(turns)) {
    context_fork_abort(
      "invalid",
      "{.arg turns} must be a plain list of public ellmer turns."
    )
  }
  if (length(turns) > max_turns) {
    context_fork_abort(
      "oversized",
      "The host-selected fork exceeds max_turns."
    )
  }
  native <- lapply(turns, function(turn) {
    if (
      inherits(turn, "ellmer::SystemTurn") ||
        inherits(turn, "ellmer::AssistantPartialTurn")
    ) {
      context_fork_abort(
        "invalid",
        "Fork turns cannot contain SystemTurn or AssistantPartialTurn values."
      )
    }
    if (
      inherits(turn, "ellmer::UserTurn") ||
        inherits(turn, "ellmer::AssistantTurn")
    ) {
      return(turn)
    }
    # Allow a portable record to be reconstructed for a saved host value, but
    # never accept arbitrary objects or turn-like lists as native content.
    if (is.list(turn) && !is.object(turn)) {
      if (!observation_payload_fits(turn, max_bytes)) {
        context_fork_abort(
          "oversized",
          "A selected portable fork turn exceeds max_bytes."
        )
      }
      replayed <- tryCatch(
        inspection_replay(turn, sanitize = TRUE),
        error = function(error) {
          context_fork_abort(
            "invalid",
            "{.arg turns} contains an invalid public ellmer record."
          )
        }
      )
      if (
        inherits(replayed, "ellmer::SystemTurn") ||
          inherits(replayed, "ellmer::AssistantPartialTurn")
      ) {
        context_fork_abort(
          "invalid",
          "Fork turns cannot contain SystemTurn or AssistantPartialTurn values."
        )
      }
      if (
        !inherits(replayed, "ellmer::UserTurn") &&
          !inherits(replayed, "ellmer::AssistantTurn")
      ) {
        context_fork_abort(
          "invalid",
          "Fork turns must be UserTurn or AssistantTurn values."
        )
      }
      return(replayed)
    }
    context_fork_abort(
      "invalid",
      "{.arg turns} may contain only UserTurn or AssistantTurn values."
    )
  })
  context_fork_input_bound(native, max_bytes)
  # Establish the existing inert public projection before looking at tool
  # rounds or converting incomplete evidence to text. This removes hidden
  # thinking, private extras and executable bindings before any custom fork
  # representation can see their values.
  clean_records <- tryCatch(
    lapply(native, inspection_record_turn),
    error = function(error) {
      context_fork_abort(
        "invalid",
        "The selected turns contain unsupported public fork evidence."
      )
    }
  )
  clean_native <- lapply(clean_records, function(record) {
    tryCatch(
      inspection_replay(record),
      error = function(error) {
        context_fork_abort(
          "invalid",
          "The selected public fork turn cannot be replayed safely."
        )
      }
    )
  })
  context_fork_input_bound(clean_native, max_bytes)
  tool_ids <- context_fork_tool_ids(clean_native)
  sanitized <- context_fork_sanitize_turns(clean_native, tool_ids)
  clean_native <- sanitized$turns
  records <- lapply(clean_native, inspection_record_turn)
  bytes <- length(serialize(records, NULL, version = 3))
  if (bytes > max_bytes) {
    context_fork_abort(
      "oversized",
      "The projected fork turns exceed max_bytes."
    )
  }
  list(
    records = records,
    bytes = as.integer(bytes),
    omissions = c(
      sanitized$omissions,
      if (tool_ids$replacements > 0L) "partial_tool_evidence"
    )
  )
}

context_fork_projection <- function(omissions) {
  list(
    schema_version = 1L,
    format = "ellmer-public-content-record-v1",
    execution = "inert",
    tool_bindings = "omitted",
    provider_private = "omitted",
    hidden_thinking = "omitted",
    omissions = unique(c(
      "tool_bindings",
      "provider_private",
      "hidden_thinking",
      omissions
    ))
  )
}

#' Describe a host-selected conversation fork
#'
#' ContextFork() is a read-only request to seed a fresh standalone Agent with
#' selected public ellmer turns. The host supplies the owner, conversation,
#' branch, revision and fork point and remains responsible for authenticating
#' those identifiers. Turns are projected through the public ellmer record
#' contract; tool bindings, hidden thinking and provider-private fields are
#' omitted, and incomplete tool evidence becomes inert text.
#'
#' @param owner_id Host owner identifier.
#' @param conversation_id Host conversation identifier.
#' @param branch_id Host-selected branch identifier.
#' @param revision Exact host revision identifier.
#' @param fork_point Host fork point token or non-negative turn number.
#' @param view Either "transcript" for the complete selected transcript or
#'   "context" for the current model context. The latter never falls back to
#'   the transcript automatically.
#' @param turns A bounded list of native public ellmer turns, or public records
#'   produced by `ellmer::contents_record()` for those turns.
#' @param max_bytes Maximum serialized bytes of the inert public projection.
#' @param max_turns Maximum number of selected turns.
#' @param schema_version Portable value schema version, currently 1L.
#' @return A read-only ContextFork S7 value with no Chat or executable object.
#' @export
ContextFork <- S7::new_class(
  "ContextFork",
  package = "deputy",
  properties = list(
    schema_version = readonly_property("schema_version", S7::class_integer),
    owner_id = readonly_property("owner_id", S7::class_character),
    conversation_id = readonly_property("conversation_id", S7::class_character),
    branch_id = readonly_property("branch_id", S7::class_character),
    revision = readonly_property("revision", S7::class_character),
    fork_point = readonly_property(
      "fork_point",
      S7::new_union(S7::class_integer, S7::class_character)
    ),
    view = readonly_property("view", S7::class_character),
    turns = readonly_property("turns", S7::class_list),
    max_bytes = readonly_property("max_bytes", S7::class_integer),
    max_turns = readonly_property("max_turns", S7::class_integer),
    projection = readonly_property("projection", S7::class_list),
    omissions = readonly_property("omissions", S7::class_character),
    size = readonly_property("size", S7::class_list)
  ),
  constructor = function(
    owner_id = NULL,
    conversation_id = NULL,
    branch_id = NULL,
    revision = NULL,
    fork_point = NULL,
    view = c("transcript", "context"),
    turns = list(),
    max_bytes = 64 * 1024,
    max_turns = 256L,
    schema_version = 1L
  ) {
    owner_id <- delegation_text(owner_id, "owner_id")
    conversation_id <- delegation_text(conversation_id, "conversation_id")
    branch_id <- delegation_text(branch_id, "branch_id")
    revision <- delegation_text(revision, "revision")
    fork_point <- context_fork_point(fork_point)
    if (
      !is.character(view) ||
        !length(view) ||
        anyNA(view) ||
        !is.null(attributes(view))
    ) {
      context_fork_abort("invalid", "{.arg view} must be one string.")
    }
    view <- match.arg(view, c("transcript", "context"))
    max_bytes <- context_policy_whole_number(max_bytes, "max_bytes")
    max_turns <- context_policy_whole_number(max_turns, "max_turns")
    if (is.null(max_bytes) || is.null(max_turns)) {
      context_fork_abort(
        "invalid",
        "Fork bounds must be finite positive whole numbers."
      )
    }
    if (
      !is.numeric(schema_version) ||
        length(schema_version) != 1L ||
        is.na(schema_version) ||
        schema_version != 1 ||
        !is.null(attributes(schema_version))
    ) {
      context_fork_abort("invalid", "Unsupported ContextFork schema.")
    }
    normalized <- context_fork_turn_records(turns, max_bytes, max_turns)
    omissions <- unique(normalized$omissions)
    projection <- context_fork_projection(omissions)
    value <- S7::new_object(
      S7::S7_object(),
      schema_version = 1L,
      owner_id = owner_id,
      conversation_id = conversation_id,
      branch_id = branch_id,
      revision = revision,
      fork_point = fork_point,
      view = view,
      turns = normalized$records,
      max_bytes = max_bytes,
      max_turns = max_turns,
      projection = projection,
      omissions = projection$omissions,
      size = list(
        bytes = normalized$bytes,
        turns = length(normalized$records)
      )
    )
    freeze_value(value)
  }
)

context_fork_record <- function(fork, include_turns = TRUE) {
  fields <- list(
    schema_version = fork$schema_version,
    owner_id = fork$owner_id,
    conversation_id = fork$conversation_id,
    branch_id = fork$branch_id,
    revision = fork$revision,
    fork_point = fork$fork_point,
    view = fork$view,
    max_bytes = fork$max_bytes,
    max_turns = fork$max_turns,
    projection = fork$projection,
    omissions = fork$omissions,
    size = fork$size
  )
  if (include_turns) {
    fields$turns <- fork$turns
  }
  inspection_portable(fields)
  fields
}

context_fork_authorization_snapshot <- function(fork) {
  record <- context_fork_record(fork)
  record
}

context_fork_receipt <- function(receipt, fork) {
  if (!is.list(receipt) || is.object(receipt)) {
    context_fork_abort(
      "unauthorized",
      "Fork authorization must return a scoped identity and revision record."
    )
  }
  names <- names(receipt)
  canonical <- c("owner_id", "conversation_id", "branch_id", "revision")
  if (
    is.null(names) ||
      anyDuplicated(names) ||
      !setequal(names, canonical) ||
      !identical(names(attributes(receipt)), "names")
  ) {
    context_fork_abort(
      "unauthorized",
      "Fork authorization returned unexpected receipt fields."
    )
  }
  selected <- receipt[canonical]
  selected <- lapply(
    selected,
    delegation_text,
    field = "authorization receipt"
  )
  names(selected) <- canonical
  expected <- list(
    owner_id = fork$owner_id,
    conversation_id = fork$conversation_id,
    branch_id = fork$branch_id,
    revision = fork$revision
  )
  if (
    !identical(
      selected[c("owner_id", "conversation_id", "branch_id")],
      expected[c("owner_id", "conversation_id", "branch_id")]
    )
  ) {
    context_fork_abort(
      "scope_mismatch",
      "Fork authorization does not match the selected source scope."
    )
  }
  if (!identical(selected$revision, expected$revision)) {
    context_fork_abort(
      "stale",
      "Fork authorization does not match the selected source revision."
    )
  }
  selected
}

context_fork_authorize <- function(fork, authorize) {
  if (!is.function(authorize)) {
    context_fork_abort("invalid", "{.arg authorize} must be a function.")
  }
  receipt <- tryCatch(
    authorize(context_fork_authorization_snapshot(fork)),
    error = function(error) NULL
  )
  if (is.null(receipt) || identical(receipt, FALSE)) {
    context_fork_abort("unauthorized", "Fork source authorization was denied.")
  }
  context_fork_receipt(receipt, fork)
}

context_fork_replay <- function(fork) {
  lapply(fork$turns, function(record) {
    tryCatch(
      inspection_replay(record),
      error = function(error) {
        context_fork_abort(
          "invalid",
          "The fork contains an invalid inert public turn record."
        )
      }
    )
  })
}

context_fork_manifest <- function(parent, child, fork, receipt, initial_turns) {
  message <- delegation_json(list(
    type = "deputy_context_fork_v1",
    owner_id = fork$owner_id,
    conversation_id = fork$conversation_id,
    branch_id = fork$branch_id,
    revision = fork$revision,
    fork_point = fork$fork_point,
    view = fork$view
  ))
  definition <- list(
    name = child$agent_name %||% "fork",
    prompt = child$get_system_prompt() %||% "",
    memory = character(),
    initial_prompt = NULL,
    skills = character()
  )
  prepared <- list(
    input = DelegationInput(message),
    sources = list(),
    message = message
  )
  manifest <- prepare_delegation_manifest(parent, definition, prepared, child)
  fields <- S7::props(manifest)
  estimated <- tryCatch(
    child$.__enclos_env__$private$context_token_count(
      list(message),
      turns = initial_turns
    ),
    error = function(error) NULL
  )
  if (
    !is.null(estimated) &&
      !is.null(child$context_policy$max_tokens) &&
      estimated > child$context_policy$max_tokens
  ) {
    context_fork_abort(
      "oversized",
      "The selected fork context exceeds ContextPolicy$max_tokens."
    )
  }
  fields$size$estimated_tokens <- estimated
  fields$policies$fork <- list(
    owner_id = fork$owner_id,
    conversation_id = fork$conversation_id,
    branch_id = fork$branch_id,
    revision = fork$revision,
    fork_point = fork$fork_point,
    view = fork$view,
    max_bytes = fork$max_bytes,
    max_turns = fork$max_turns,
    projection = fork$projection,
    omissions = fork$omissions,
    size = fork$size,
    turn_digest = delegation_digest(fork$turns),
    receipt = receipt
  )
  fields$size$fork_bytes <- fork$size$bytes
  fields$size$manifest_bytes <- 0L
  # max_bytes bounds only the host-selected history projection. The ordinary
  # parent admission ceiling remains the limit for the manifest and later
  # continuation brief.
  limit <- parent$.__enclos_env__$private$delegation_max_bytes
  repeat {
    manifest <- do.call(DelegationManifest, fields)
    bytes <- delegation_bytes(S7::props(manifest))
    if (identical(bytes, fields$size$manifest_bytes)) {
      break
    }
    fields$size$manifest_bytes <- bytes
  }
  if (bytes > limit) {
    context_fork_abort(
      "oversized",
      "The fork manifest exceeds the host admission bound."
    )
  }
  manifest
}

context_fork_reauthorize <- function(entry) {
  if (is.null(entry$fork)) {
    return(invisible(entry$authorization))
  }
  receipt <- context_fork_authorize(entry$fork, entry$authorize)
  invisible(receipt)
}

#' Retain a host-authorized context fork for explicit continuation
#'
#' The child must be a standalone Agent with an independent empty Chat. Its own
#' tools, prompt and resources remain host-configured; the fork only seeds inert
#' selected history and uses the ordinary retained-conversation governance.
#'
#' @param parent Owning Agent.
#' @param agent Standalone empty child Agent.
#' @param fork A host-selected ContextFork.
#' @param authorize Function receiving the portable fork snapshot and returning
#'   the exact current `owner_id`, `conversation_id`, `branch_id`, and `revision`
#'   record.
#' @param usage_limits Cumulative UsageLimits ceiling for the retained handle.
#' @param max_runs Maximum explicit continuations, default 32.
#' @return An owner-local retained conversation handle.
#' @export
fork_agent <- function(
  parent,
  agent,
  fork,
  authorize,
  usage_limits,
  max_runs = 32L
) {
  if (!inherits(parent, "Agent") || !inherits(agent, "Agent")) {
    context_fork_abort(
      "invalid",
      "{.arg parent} and {.arg agent} must be Agent objects."
    )
  }
  if (!S7::S7_inherits(fork, ContextFork)) {
    context_fork_abort("invalid", "{.arg fork} must be a ContextFork.")
  }
  # Current parent ownership/lease checks precede host source authorization so
  # a positive source receipt can never bypass the parent's authority.
  check_conversation_owner(parent)
  validate_fork_candidate(parent, agent)
  receipt <- context_fork_authorize(fork, authorize)
  turns <- context_fork_replay(fork)
  manifest <- context_fork_manifest(parent, agent, fork, receipt, turns)
  retain_conversation(
    parent,
    agent,
    usage_limits,
    max_runs,
    initial_turns = turns,
    fork = fork,
    authorize = authorize,
    authorization = receipt,
    manifest = manifest
  )
}

validate_fork_candidate <- function(parent, agent) {
  validate_conversation_candidate(parent, agent)
  child_private <- agent$.__enclos_env__$private
  if (
    identical(parent$agent_id, agent$agent_id) ||
      identical(parent$session_id(), agent$session_id())
  ) {
    context_fork_abort(
      "invalid",
      "A fork child must have distinct agent and session identities."
    )
  }
  turns <- child_private$.chat$get_turns()
  compacted <- child_private$.compacted_turns
  if (length(turns) || length(compacted)) {
    context_fork_abort(
      "invalid",
      "A fork child must use an independent empty Chat."
    )
  }
  check_conversation_owner(parent)
  invisible(NULL)
}

local({
  S7::method(`$`, ContextFork) <- function(x, name) S7::prop(x, name)
})
