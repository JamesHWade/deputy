# Model dispatch governance. ellmer owns provider IO and transport retries.

normalize_fallback_chats <- function(chats, primary) {
  if (!is.list(chats)) {
    abort_deputy("{.arg fallback_chats} must be a list of Chats")
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
    on_request_start = function(turns) begin_model_request(agent),
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
  status <- usage_limit_status(
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
  private$.chat <- replacement
  replacement$on_tool_request(private$handle_tool_request)
  replacement$on_tool_result(private$handle_tool_result)
  rebind_tool_observers(agent)
  private$current_external_usage <- usage
  private$current_outer_requests <- 0L
  private$current_usage_baseline <- agent_usage_snapshot(replacement)
  state$fallback_index <- selected
  private$.fallback_position <- selected
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

register_tool_observer <- function(agent, phase, callback) {
  private <- agent$.__enclos_env__$private
  method <- paste0("on_tool_", phase)
  field <- paste0(".tool_", phase, "_observers")
  remove <- private$.chat[[method]](callback)
  private$.tool_observer_id <- private$.tool_observer_id + 1L
  id <- as.character(private$.tool_observer_id)
  private[[field]][[id]] <- callback
  private$.tool_observer_removers[[id]] <- remove
  function() {
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
