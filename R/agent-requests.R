# Model dispatch governance. ellmer owns provider IO and transport retries.

normalize_fallback_chats <- function(
  chats,
  primary,
  argument = "fallback_chats"
) {
  if (!is.list(chats)) {
    abort_deputy("{.arg {argument}} must be a list of Chats")
  }
  for (chat in chats) {
    validate_chat(chat)
    if (inherits(chat, "Agent") || identical(chat, primary)) {
      abort_deputy("Fallback templates must be independent ellmer Chats")
    }
    if (length(chat$get_turns()) || length(chat$get_tools())) {
      abort_deputy(
        "Fallback templates must have no conversation turns or tools"
      )
    }
  }
  # The caller can keep and change their templates without changing our policy.
  lapply(chats, clone_governed_chat)
}

# Keep only Deputy-owned registrations here. Public removal functions let us
# clone an active Chat without copying callbacks that close over its Agent.
# Existing caller callbacks remain registered and are cloned by ellmer.
install_request_callbacks <- function(agent) {
  private <- agent$.__enclos_env__$private
  chat <- private$.chat
  if (!is.function(chat$on_request_start)) {
    return(invisible(NULL))
  }
  callbacks <- list(
    on_request_start = function(turns) {
      request_start_async(agent, private, turns)
    },
    on_request_end = function(turn) end_model_request(agent, turn)
  )
  attr(chat, "deputy_request_callbacks") <- lapply(
    names(callbacks),
    function(name) {
      list(
        name = name,
        callback = callbacks[[name]],
        remove = chat[[name]](callbacks[[name]])
      )
    }
  )
  chat$conversation_id <- private$.session_id
  invisible(NULL)
}

# Defined once so coro reuses its state machine for every model request.
request_start_async <- coro::async(function(agent, private, turns) {
  tryCatch(
    {
      # All tool results have settled; ellmer has not stored or dispatched
      # the pending user turn yet. Count its contents without appending it.
      if (private$current_run_state$task_requests > 0L) {
        pending <- utils::tail(turns, 1L)[[1L]]
        coro::await(private$maybe_auto_compact(
          messages = pending@contents
        ))
      }
      begin_model_request(agent)
    },
    error = function(error) {
      retain_pending_tool_results(agent, turns)
      rlang::cnd_signal(error)
    }
  )
})

retain_pending_tool_results <- function(agent, request_turns) {
  pending <- utils::tail(request_turns, 1L)[[1L]]
  if (
    !inherits(pending, "ellmer::UserTurn") ||
      !any(vapply(
        pending@contents,
        inherits,
        logical(1),
        what = "ellmer::ContentToolResult"
      ))
  ) {
    return(invisible(NULL))
  }
  chat <- agent$.__enclos_env__$private$.chat
  current <- chat$get_turns()
  previous <- utils::head(request_turns, -1L)
  # Compaction preserves the pending round. If a host deliberately replaced
  # that conversation while we awaited, do not append orphaned tool results.
  if (
    length(current) &&
      length(previous) &&
      identical(tail(current, 1L), tail(previous, 1L))
  ) {
    chat$set_turns(c(current, list(pending)))
  }
  invisible(NULL)
}

remove_request_callbacks <- function(chat) {
  callbacks <- attr(chat, "deputy_request_callbacks", exact = TRUE)
  for (callback in callbacks) {
    callback$remove()
  }
  attr(chat, "deputy_request_callbacks") <- NULL
  invisible(callbacks)
}

clone_governed_chat <- function(chat) {
  callbacks <- remove_request_callbacks(chat)
  on.exit(
    {
      if (length(callbacks)) {
        attr(chat, "deputy_request_callbacks") <- lapply(
          callbacks,
          function(callback) {
            callback$remove <- chat[[callback$name]](callback$callback)
            callback
          }
        )
      }
    },
    add = TRUE
  )
  args <- names(formals(chat$clone))
  cloned <- if (any(c("deep", "...") %in% args)) {
    chat$clone(deep = TRUE)
  } else {
    chat$clone()
  }
  if (identical(cloned, chat)) {
    abort_deputy("Chat cloning must return an independent instance")
  }
  cloned
}

begin_model_request <- function(agent) {
  private <- agent$.__enclos_env__$private
  state <- private$current_run_state
  if (is.null(state)) {
    return(invisible(NULL))
  }
  status <- tree_usage_status(agent) %||%
    usage_limit_status(
      private$current_run_usage(),
      state$limits,
      require_followup = TRUE
    )
  if (!is.null(status)) {
    private$mark_usage_limit(status)
  }
  if (isTRUE(private$should_stop)) {
    cli_abort(
      "The governed run has stopped",
      class = c("deputy_run_stopped", "deputy_error")
    )
  }
  private$current_outer_requests <- private$current_outer_requests + 1L
  state$request_number <- state$request_number + 1L
  state$task_requests <- state$task_requests + 1L
  state$request_turns_before <- length(private$.chat$get_turns())
  state$model_failure <- NULL
  private$record_run_event(private$agent_event(
    "request_start",
    request_number = state$request_number,
    fallback_index = state$fallback_index,
    provider = agent$provider()$name,
    model = agent$get_model()
  ))
  invisible(NULL)
}

end_model_request <- function(agent, turn) {
  private <- agent$.__enclos_env__$private
  state <- private$current_run_state
  if (is.null(state)) {
    return(invisible(NULL))
  }
  state$response_seen <- TRUE
  private$record_run_event(private$agent_event(
    "request_end",
    request_number = state$request_number,
    provider = agent$provider()$name,
    model = agent$get_model(),
    outcome = "response"
  ))
  invisible(NULL)
}

record_model_failure <- function(agent, condition, structured = FALSE) {
  # Callback code can make HTTP requests too. In ordinary streams ellmer
  # records an AssistantPartialTurn after start callbacks and before IO, then
  # finalizes it before end callbacks. Require that public dispatch evidence.
  private <- agent$.__enclos_env__$private
  state <- private$current_run_state
  state$model_failure <- NULL
  if (!inherits(condition, c("httr2_failure", "httr2_http"))) {
    return(invisible(FALSE))
  }
  if (isTRUE(private$current_stream_controller$cancelled)) {
    return(invisible(FALSE))
  }
  turns <- private$.chat$get_turns()
  turn <- if (length(turns) > state$request_turns_before) {
    utils::tail(turns, 1L)[[1]]
  }
  partial <- inherits(turn, "ellmer::AssistantPartialTurn")
  # Structured value requests bypass request callbacks in ellmer 0.5.0 and
  # append their turn only after a response. A completed turn rules out IO
  # failure here too; preserve any subsequent application error as run_error.
  if ((!structured && !partial) || (structured && !is.null(turn) && !partial)) {
    return(invisible(FALSE))
  }
  state$model_failure <- condition
  private$record_run_event(private$agent_event(
    "request_error",
    request_number = private$current_run_state$request_number,
    provider = agent$provider()$name,
    model = agent$get_model(),
    condition = condition
  ))
  invisible(TRUE)
}

# Only transport failures known to be transient qualify. Authentication,
# validation, callbacks, and arbitrary application errors are terminal.
fallback_transport_error <- function(condition) {
  inherits(condition, "httr2_failure") ||
    any(vapply(
      c(408L, 429L, 500L, 502L, 503L, 504L),
      function(status) {
        inherits(condition, paste0("httr2_http_", status))
      },
      logical(1)
    ))
}

try_chat_fallback <- function(agent, condition) {
  private <- agent$.__enclos_env__$private
  state <- private$current_run_state
  if (
    isTRUE(private$should_stop) ||
      isTRUE(state$response_seen) ||
      private$current_tool_calls > 0L ||
      isTRUE(private$.approval_resume$executed) ||
      !identical(state$model_failure, condition) ||
      !fallback_transport_error(condition) ||
      state$fallback_index >= length(private$.fallback_chats)
  ) {
    return(FALSE)
  }

  # Even content recorded upstream but not yet yielded locks out fallback.
  turns <- private$.chat$get_turns()
  added <- utils::tail(
    turns,
    max(0L, length(turns) - length(state$dispatch_turns))
  )
  if (
    any(vapply(
      added,
      function(turn) {
        inherits(turn, "ellmer::AssistantTurn") &&
          (!inherits(turn, "ellmer::AssistantPartialTurn") ||
            length(turn@contents) > 0L)
      },
      logical(1)
    ))
  ) {
    return(FALSE)
  }

  usage <- private$current_run_usage()
  status <- usage_limit_status(usage, state$limits, require_followup = TRUE)
  if (!is.null(status)) {
    private$mark_usage_limit(status)
    return(FALSE)
  }
  selected <- state$fallback_index + 1L
  replacement <- clone_governed_chat(private$.fallback_chats[[selected]])
  replacement$set_system_prompt(private$.chat$get_system_prompt())
  replacement$set_turns(state$dispatch_turns)
  # Adapt the current registry again to retain the same authority and working
  # directory. The replacement never imports executable tools from a template.
  replacement$set_tools(lapply(private$.chat$get_tools(), private$adapt_tool))
  remove_request_callbacks(private$.chat)
  unmark_chat_owner(private$.chat, agent)
  mark_chat_owner(replacement, agent)
  private$.chat <- replacement
  replacement$on_tool_request(private$handle_tool_request)
  replacement$on_tool_result(private$handle_tool_result)
  rebind_tool_observers(agent)
  private$current_external_usage <- usage
  private$current_outer_requests <- 0L
  private$current_usage_baseline <- agent_usage_snapshot(replacement)
  state$fallback_index <- selected
  private$.fallback_position <- selected
  private$mark_usage_stale()
  install_request_callbacks(agent)
  private$record_run_event(private$agent_event(
    "fallback",
    fallback_index = selected,
    provider = agent$provider()$name,
    model = agent$get_model(),
    condition = condition,
    usage = usage
  ))
  TRUE
}

# An Agent marks the Chat it wraps, so set_chat() can't take over a Chat that
# still backs another Agent: rewiring it would bind that Agent's calls to the
# wrong permissions, hooks and tools. The weak reference frees the Chat once
# its Agent is gone.
# Every live Agent built on a Chat, held by weak reference: Agents may share a
# Chat, and set_chat() must not move one away from under another.
chat_owners <- function(chat) {
  refs <- attr(chat, "deputy_agent_owners", exact = TRUE)
  owners <- lapply(refs, function(ref) {
    if (rlang::is_weakref(ref)) rlang::wref_key(ref)
  })
  Filter(Negate(is.null), owners)
}

mark_chat_owner <- function(chat, agent) {
  owners <- chat_owners(chat)
  if (!any(vapply(owners, identical, logical(1), agent))) {
    owners <- c(owners, list(agent))
  }
  attr(chat, "deputy_agent_owners") <- lapply(owners, rlang::new_weakref)
  invisible(chat)
}

unmark_chat_owner <- function(chat, agent) {
  owners <- Filter(function(owner) !identical(owner, agent), chat_owners(chat))
  attr(chat, "deputy_agent_owners") <- if (length(owners)) {
    lapply(owners, rlang::new_weakref)
  }
  invisible(chat)
}

other_chat_owners <- function(chat, agent) {
  Filter(function(owner) !identical(owner, agent), chat_owners(chat))
}

# Agent$set_chat(): a host-selected replacement, moved between runs the way
# try_chat_fallback() moves a failed request. The new Chat receives the prompt,
# the history and this Agent's own adapted tools; the old Chat keeps no Deputy
# callbacks, observers or tools that could run outside the Agent.
replace_agent_chat <- function(agent, chat) {
  private <- agent$.__enclos_env__$private
  if (isTRUE(private$run_active)) {
    conversation_abort("Wait for the active run before replacing the Chat.")
  }
  if (!is.null(private$.pending_approval_path)) {
    approval_abort(
      "This Agent has a pending approval; resume or deny it before replacing the Chat."
    )
  }
  check_conversation_lease(agent, NULL)
  validate_chat(chat)
  if (inherits(chat, "Agent")) {
    abort_deputy("{.arg chat} must be an ellmer Chat, not an Agent")
  }
  check_incoming_conversation(chat)
  old <- private$.chat
  if (identical(chat, old)) {
    return(invisible(agent))
  }
  # Another Agent built on the same Chat would lose its tools and callbacks
  # when this one moves away.
  if (length(other_chat_owners(old, agent))) {
    abort_deputy(c(
      "This Agent's Chat is shared with another Agent",
      "i" = "Give each Agent its own Chat before replacing one."
    ))
  }
  if (length(other_chat_owners(chat, agent))) {
    abort_deputy("This Chat already belongs to another Agent")
  }
  if (length(chat$get_turns()) || length(chat$get_tools())) {
    abort_deputy("The new Chat must have no conversation turns or tools")
  }
  tools <- old$get_tools()
  native <- names(tools)[vapply(
    tools,
    inherits,
    logical(1),
    what = "ellmer::ToolBuiltIn"
  )]
  if (length(native)) {
    abort_deputy(c(
      "Provider-native tools can't move to another Chat: {.val {native}}",
      "i" = "Remove them with {.code $set_tools()} before replacing the Chat."
    ))
  }

  # If moving fails, the destination is returned empty, with its own prompt,
  # so the caller can retry with it.
  destination_prompt <- chat$get_system_prompt()
  moved_turns <- portable_turns(old$get_turns())
  kept <- attr(moved_turns, "kept")
  attr(moved_turns, "kept") <- NULL
  # The old Chat is untouched until the move succeeds; only the observer
  # removers and reader state are rebound, so keep them to restore.
  removers <- private$.tool_observer_removers
  reader_registered <- private$.tool_result_reader_registered
  moved <- tryCatch(
    {
      chat$set_system_prompt(old$get_system_prompt())
      chat$set_turns(moved_turns)
      chat$set_tools(tools)
      private$.chat <- chat
      private$rewire_chat_runtime()
      NULL
    },
    error = function(error) error
  )
  if (!is.null(moved)) {
    private$.chat <- old
    private$.tool_observer_removers <- removers
    private$.tool_result_reader_registered <- reader_registered
    # Tool callbacks on the destination are cleared on success too (see
    # set_chat()); here they may be Deputy's own, half installed.
    try(clear_chat_tool_callbacks(chat), silent = TRUE)
    try(chat$set_tools(list()), silent = TRUE)
    try(chat$set_turns(list()), silent = TRUE)
    try(chat$set_system_prompt(destination_prompt), silent = TRUE)
    rlang::cnd_signal(moved)
  }
  # Microcompacted results and shown activity are keyed by position; dropped
  # turns shift them.
  private$.cleared_tool_results <- remap_cleared_tool_results(
    private$.cleared_tool_results,
    kept,
    offset = length(private$.compacted_turns)
  )
  private$.activity_overlay <- activity_remap(
    private$.activity_overlay,
    kept,
    offset = length(private$.compacted_turns)
  )
  unmark_chat_owner(old, agent)
  mark_chat_owner(chat, agent)
  # Fallbacks start again from the new primary Chat.
  private$.fallback_position <- 0L
  private$mark_usage_stale()
  # The Agent now runs on the new Chat, so failing to clear the old one is
  # reported rather than presented as a failed swap.
  cleared <- tryCatch(
    {
      clear_chat_tool_callbacks(old)
      old$set_tools(list())
      NULL
    },
    error = function(error) error
  )
  if (!is.null(cleared)) {
    cli::cli_warn(
      c(
        "The Agent now uses the new Chat, but the old Chat couldn't be cleared.",
        "i" = "Don't reuse the old Chat; its tools may still be bound to this Agent."
      ),
      parent = cleared
    )
  }
  invisible(agent)
}

# Reasoning content carries a signature or encrypted state that only the
# provider which produced it accepts, so history moving to another Chat keeps
# every other content type. An assistant turn that held only reasoning (a
# response stopped while thinking) is dropped: providers reject empty
# assistant messages, and they accept consecutive user messages.
# The result records the original positions of the turns it keeps as the
# "kept" attribute.
portable_turns <- function(turns) {
  turns <- lapply(turns, function(turn) {
    if (!inherits(turn, "ellmer::AssistantTurn")) {
      return(turn)
    }
    keep <- Filter(
      function(content) !inherits(content, "ellmer::ContentThinking"),
      turn@contents
    )
    if (length(keep) == length(turn@contents)) {
      return(turn)
    }
    if (length(keep) == 0L) {
      return(NULL)
    }
    turn@contents <- keep
    turn
  })
  kept <- which(!vapply(turns, is.null, logical(1)))
  structure(turns[kept], kept = kept)
}

# Microcompacted tool results are keyed "turn:content" by position in the
# complete conversation: the compacted prefix (`offset` turns), then the
# context. Moves the context keys to where the kept turns now sit.
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

# ellmer resets a cancelled controller when a stream starts. A governed stream
# starts lazily, so reset once the run is accepted, before a host such as
# shinychat reads the controller for the new run.
reset_stream_controller <- function(controller) {
  if (
    inherits(controller, "ellmer_stream_controller") &&
      isTRUE(controller$cancelled)
  ) {
    controller$reset()
  }
  invisible(controller)
}

register_tool_observer <- function(agent, phase, callback) {
  check_conversation_lease(agent, NULL)
  private <- agent$.__enclos_env__$private
  method <- paste0("on_tool_", phase)
  field <- paste0(".tool_", phase, "_observers")
  remove <- private$.chat[[method]](callback)
  private$.tool_observer_id <- private$.tool_observer_id + 1L
  id <- as.character(private$.tool_observer_id)
  private[[field]][[id]] <- callback
  private$.tool_observer_removers[[id]] <- remove
  function() {
    check_conversation_lease(agent, NULL)
    remove <- private$.tool_observer_removers[[id]]
    if (is.function(remove)) {
      remove()
    }
    private$.tool_observer_removers[[id]] <- NULL
    private[[field]][[id]] <- NULL
    invisible(NULL)
  }
}

rebind_tool_observers <- function(agent) {
  private <- agent$.__enclos_env__$private
  private$.tool_observer_removers <- list()
  for (phase in c("request", "result")) {
    field <- paste0(".tool_", phase, "_observers")
    method <- paste0("on_tool_", phase)
    for (id in names(private[[field]])) {
      private$.tool_observer_removers[[id]] <- private$.chat[[method]](private[[
        field
      ]][[id]])
    }
  }
  invisible(NULL)
}
