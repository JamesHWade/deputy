# Subagent activity presenter lifecycle and async stream merging -------------

new_activity_presenter <- function(requester, interval) {
  state <- new.env(parent = emptyenv())
  state$requester <- requester
  state$interval <- interval
  state$queue <- list()
  state$delegations <- list()
  state$run_id <- NULL
  # The run of the reply this presenter streams.
  state$stream_run <- NULL
  state$calls <- 0L
  state$limited <- FALSE
  state$error <- NULL
  state
}

# A replaced conversation starts the presenter afresh: cards waiting to be
# streamed, labels and counts belong to the conversation they were shown in,
# as do the results a stopped presenter left for the reply streaming now.
activity_reset <- function(agent) {
  private <- agent_private(agent)
  private$.activity_leftover <- NULL
  state <- private$.activity
  if (is.null(state)) {
    return(invisible(NULL))
  }
  state$queue <- list()
  state$delegations <- list()
  state$run_id <- NULL
  state$calls <- 0L
  state$limited <- FALSE
  # A reply still streaming belongs to the replaced conversation: its
  # subagents' calls aren't shown in the new one.
  state$skip_run <- private$current_run_id
  invisible(NULL)
}

activity_enable <- function(agent, requester, interval = 0.1) {
  if (!is.function(requester)) {
    cli::cli_abort("{.arg requester} must be a function returning the viewer.")
  }
  private <- agent_private(agent)
  # One presenter per lead. A second would show the same calls again under
  # new keys, and the first one's running cards would never be settled.
  if (!is.null(private$.activity)) {
    cli::cli_abort(c(
      "Subagent activity is already shown for this lead.",
      "i" = paste(
        "Call {.fn stop} on the value {.fn subagent_chat_activity} returned",
        "before showing it again."
      )
    ))
  }
  state <- new_activity_presenter(requester, interval)
  private$.activity <- state
  invisible(state)
}

# `presenter` is the one to stop: once it has been stopped and another shown,
# stopping it again leaves the other running.
activity_disable <- function(agent, presenter = NULL) {
  private <- agent_private(agent)
  state <- private$.activity
  if (!is.null(presenter) && !identical(state, presenter)) {
    return(invisible(agent))
  }
  # Cards still running when the presenter stops would stay running in saved
  # history, since no later poll will settle them.
  for (entry in activity_open_entries(agent)) {
    activity_settle(
      agent,
      entry,
      "Not shown: subagent activity stopped before this call returned.",
      state = state
    )
  }
  # The reply streaming now, if it started with this presenter, takes what
  # was queued, those results included; a later reply doesn't. A presenter
  # shown during a reply has no stream in it, so an earlier presenter's
  # results for that reply are kept.
  run_id <- private$current_run_id
  earlier <- private$.activity_leftover
  if (
    !is.null(state) &&
      length(state$queue) &&
      !is.null(run_id) &&
      !identical(earlier$run_id, run_id)
  ) {
    private$.activity_leftover <- list(
      run_id = run_id,
      presenter = state,
      queue = state$queue
    )
  }
  private$.activity <- NULL
  invisible(agent)
}

# `presenter` is the one the reading stream started with: a stream takes only
# its own presenter's cards, and what that presenter left queued for this
# reply when it stopped, never another presenter's.
activity_take <- function(agent, presenter = NULL) {
  private <- agent_private(agent)
  mine <- function(state) is.null(presenter) || identical(state, presenter)
  queue <- list()
  leftover <- private$.activity_leftover
  if (!is.null(leftover) && mine(leftover$presenter)) {
    private$.activity_leftover <- NULL
    if (identical(leftover$run_id, private$current_run_id)) {
      queue <- leftover$queue
    }
  }
  state <- private$.activity
  if (!is.null(state) && mine(state)) {
    queue <- c(queue, state$queue)
    state$queue <- list()
  }
  queue
}

activity_wait <- function(slot, seconds) {
  promises::promise(function(resolve, reject) {
    slot$waiter <- resolve
    later::later(
      function() {
        if (identical(slot$waiter, resolve)) {
          slot$waiter <- NULL
          resolve(FALSE)
        }
      },
      seconds
    )
  })
}

activity_wake <- function(slot) {
  waiter <- slot$waiter
  if (is.function(waiter)) {
    slot$waiter <- NULL
    waiter(TRUE)
  }
  invisible(NULL)
}

activity_watch <- function(slot, value) {
  slot$done <- FALSE
  slot$value <- NULL
  slot$error <- NULL
  promises::then(
    promises::as.promise(value),
    onFulfilled = function(result) {
      slot$value <- result
      slot$done <- TRUE
      activity_wake(slot)
    },
    onRejected = function(error) {
      slot$error <- error
      slot$done <- TRUE
      activity_wake(slot)
    }
  )
  invisible(NULL)
}

# The lead's stream with its subagents' tool calls merged in as they happen.
# While the lead waits on a delegation, the stream checks for new calls on a
# timer; before it yields a tool result, and when it ends, it settles them.
activity_stream <- coro::async_generator(function(agent, inner, presenter) {
  slot <- new.env(parent = emptyenv())
  waiting <- FALSE
  interval <- presenter$interval
  repeat {
    for (content in activity_take(agent, presenter)) {
      coro::yield(content)
    }
    if (!waiting) {
      next_value <- tryCatch(
        inner(),
        error = function(error) promises::promise_reject(error)
      )
      # The reply has started its run by now.
      presenter$stream_run <- agent_private(agent)$current_run_id
      activity_watch(slot, next_value)
      waiting <- TRUE
    }
    if (!isTRUE(slot$done)) {
      coro::await(activity_wait(slot, interval))
      if (!isTRUE(slot$done)) {
        activity_poll(agent, presenter = presenter)
        next
      }
    }
    waiting <- FALSE
    if (!is.null(slot$error)) {
      activity_poll(agent, closing = TRUE, presenter = presenter)
      for (content in activity_take(agent, presenter)) {
        coro::yield(content)
      }
      rlang::cnd_signal(slot$error)
    }
    value <- slot$value
    if (coro::is_exhausted(value)) {
      activity_poll(agent, closing = TRUE, presenter = presenter)
      for (content in activity_take(agent, presenter)) {
        coro::yield(content)
      }
      break
    }
    if (inherits(value, "ellmer::ContentToolResult")) {
      activity_poll(agent, final = TRUE, presenter = presenter)
      for (content in activity_take(agent, presenter)) {
        coro::yield(content)
      }
    }
    coro::yield(value)
  }
})

# Bring the lead's view of its subagents' tool calls up to date. `final`
# rereads every open delegation and settles calls that won't return once their
# delegation has settled; `closing` does so for every open call, because the
# lead's reply is ending and a card must not stay running in saved history.
# A stream polls only the presenter it started with; once that presenter is
# stopped, or another shown, it reads nothing more.
activity_poll <- function(
  agent,
  final = FALSE,
  closing = FALSE,
  presenter = NULL
) {
  private <- agent_private(agent)
  state <- private$.activity
  run_id <- private$current_run_id
  if (
    is.null(state) ||
      is.null(run_id) ||
      identical(state$skip_run, run_id) ||
      (!is.null(presenter) && !identical(state, presenter))
  ) {
    return(invisible(NULL))
  }
  if (!identical(state$run_id, run_id)) {
    state$run_id <- run_id
    state$calls <- 0L
    state$limited <- FALSE
  }
  result <- tryCatch(
    {
      requester <- state$requester()
      inspection_authorize(
        lead_disclosure(agent),
        requester,
        inspection_scope(agent)
      )
      activity_refresh(
        agent,
        state,
        requester,
        run_id,
        final || closing,
        closing
      )
      state$error <- NULL
    },
    error = function(error) {
      # A viewer who may not see the subagents sees no activity; the runs and
      # the lead's own conversation are unaffected.
      state$error <- inspection_text(conditionMessage(error), 1024L)
      # Cards already shown still get a result when the reply ends, so none
      # stays running in saved history.
      if (closing) {
        for (open in activity_open_entries(agent)) {
          activity_settle(
            agent,
            open,
            "Not shown: subagent activity could not be read when the reply ended.",
            state = state
          )
        }
      }
    }
  )
  invisible(result)
}

# The agent's shown activity as a session payload keeps it. A save made
# mid-reply first reads what the reply hasn't shown yet, so a call that has
# returned is saved with its result. A card still waiting for its result gets
# one saying so in the payload, since nothing settles it once the payload is
# loaded; the live conversation keeps waiting for the call.
activity_saved_entries <- function(agent) {
  private <- agent_private(agent)
  state <- private$.activity
  # Only the reply this presenter is streaming is read again. After
  # `run_sync()`, a text stream or a finished reply, the run's calls were
  # never shown here.
  if (
    !is.null(state) &&
      isTRUE(private$run_active) &&
      identical(state$stream_run, private$current_run_id)
  ) {
    activity_poll(agent, final = TRUE, presenter = state)
  }
  overlay <- private$.activity_overlay
  for (open in activity_open_entries(agent)) {
    overlay[[length(overlay) + 1L]] <- list(
      turn = open$turn,
      content = activity_settled_result(
        open,
        "Not completed: the conversation was saved before this call returned."
      )
    )
  }
  overlay_session_entries(overlay)
}

# The shown activity of a saved session, checked against the turns it is
# loaded with. Cards are shown in assistant turns, but `$set_turns()` and
# `$add_turn()` keep a card from any turn, so a load takes back what a save
# wrote.
activity_session_overlay <- function(session, path = NULL) {
  overlay_session_overlay(
    session,
    field = "activity",
    accepts = is_activity_content,
    malformed = "Invalid session file - its subagent activity is malformed",
    path = path
  )
}
