#' @include value-properties.R
NULL

# Hook system for deputy agents

#' Hook events
#'
#' @description
#' `HookEvent` lists the events you can attach a hook to with [HookMatcher()].
#'
#' When several hooks match an event, they run in the order they were added.
#' The first callback that returns a non-`NULL` value decides the outcome, and
#' the remaining hooks for that event don't run. If a PreToolUse callback
#' errors or times out, the tool call is denied. Errors in other callbacks are
#' reported and the run continues.
#'
#' A callback may return a promise of what it would have returned, so a hook
#' can wait for a person, a model or a file. Deputy waits for the promise, up
#' to the hook's `promise_timeout`, before it goes on:
#'
#' * `PreToolUse`, `PermissionRequest`: before the tool runs.
#' * `PostToolUse`, `PostToolUseFailure`: before the next model request. The
#'   tool's result has already been recorded when the hook answers.
#' * `PostModelRequest`, `SessionStart`, `UserPromptSubmit`, `SubagentStart`,
#'   `SubagentStop`, and `PreCompact` and `PostCompact` during automatic
#'   compaction: before the run goes on.
#' * `Stop`, `SessionEnd`: before the run finishes.
#'
#' A promise that is rejected, or has not settled in time, counts as no answer
#' and is recorded as a hook error; for `PreToolUse` that denies the call.
#' Deputy does not wait for `Notification` or `ConfigChange` hooks, for a hook
#' fired by `$compact()`, or for `Stop` and `SessionEnd` when a run ends with
#' an error or its stream is abandoned. With tools run concurrently, other
#' tool calls of the same response may start or finish while a hook waits. If
#' `$interrupt()` is called while a hook waits, or by the callback itself, the
#' run stops when the hook answers, and a tool it was asked about does not
#' run.
#'
#' @section Events:
#'
#' Each entry shows the event with its callback's arguments, then when it
#' fires.
#'
#' * `PreToolUse(tool_name, tool_input, context)`: before a tool runs, once
#'   the permission policy has allowed it.
#' * `PostToolUse(tool_name, tool_result, tool_error, context)`: after a tool
#'   call finishes, whether or not it failed.
#' * `PostToolUseFailure(tool_name, tool_result, tool_error, context)`: after
#'   `PostToolUse`, when the tool failed.
#' * `PostModelRequest(context)`: after each model request of a run, once its
#'   response has arrived: the task's requests, a structured request, and the
#'   summary request of an automatic compaction. It needs ellmer's request
#'   callbacks, so a stand-in for a Chat that lacks them never fires it.
#' * `PermissionRequest(tool_name, tool_input, permission_result, context)`:
#'   when the permission policy denies a call.
#' * `SessionStart(context)`: at the start of each run.
#' * `UserPromptSubmit(prompt, context)`: at the start of each run, after
#'   `SessionStart`.
#' * `Stop(reason, context)`: at each stop of a run. A `Stop` hook may return
#'   [HookResultStop()] to send an answered run on, so a run can stop more
#'   than once.
#' * `SessionEnd(reason, context)`: once, when the run has ended.
#' * `SubagentStart(agent_name, task, context)`: when a subagent starts a
#'   delegated task.
#' * `SubagentStop(agent_name, task, result, context)`: when a subagent
#'   finishes.
#' * `PreCompact(turns_to_compact, turns_to_keep, context)`: before older
#'   turns are summarised.
#' * `PostCompact(result, context)`: after compaction.
#' * `Notification(message, context)`: when the agent reports something, such
#'   as a denied call.
#' * `ConfigChange(key, old_value, new_value, context)`: when
#'   `set_permission_mode()` changes the mode.
#'
#' `tool_input` is the named list of tool arguments. After a successful call
#' `tool_error` is `NULL`; after a failure `tool_result` is `NULL` and
#' `tool_error` holds the error message. `reason` is the stop reason, such as
#' `"complete"`, `"request_limit"`, `"cost_limit"`, `"tool_loop"`,
#' `"hook_requested_stop"` or `"provider_error"`. `result` is the subagent's
#' result for `SubagentStop` and the [DeputyCompaction] for `PostCompact`. For
#' `ConfigChange`, `key` is `"permission_mode"`.
#'
#' Five events use the callback's return value:
#'
#' * `PreToolUse`: return [HookResultPreToolUse()] to allow or deny the call,
#'   or to stop the run.
#' * `PostToolUse`: return [HookResultPostToolUse()] to stop the run or to
#'   change what the `tool_end` event shows.
#' * `PermissionRequest`: return [PermissionResultAllow()] to allow the call
#'   anyway, or [PermissionResultDeny()] to change the reason.
#' * `PreCompact`: return [HookResultPreCompact()] to cancel compaction or to
#'   supply your own summary.
#' * `Stop`: return [HookResultStop()] to send the run on.
#'
#' A run that is sent on keeps its run ID, its limits and its usage. The
#' result's `response` is the text of the last pass, and its `turns` hold
#' every pass. Only an answered run is sent on, and a run that extracts
#' structured output with `$chat_structured()` never is.
#'
#' Other events ignore the return value. Returning `NULL` means "no decision".
#'
#' @section Context:
#'
#' `context` is a named list. Every event includes:
#'
#' * `working_dir`: the agent's working directory.
#' * `agent_id`, `agent_name`, `session_id`: the agent's identifiers.
#' * `run_id`: the current run, when one is active.
#' * `run_context`: the run's `run_context` list.
#' * `parent_agent_id`, `parent_run_id`, `delegation_id`: set in subagent runs.
#'
#' Some events add fields:
#'
#' * `tool_call_id`, `permission_mode`, `usage`, `usage_limits` (tool events):
#'   the call's ID, the permission mode, the run's [AgentUsage] so far and its
#'   [UsageLimits].
#' * `usage`, `usage_limits`, `request_number` (PostModelRequest): the run's
#'   [AgentUsage] so far, its [UsageLimits] and the request's number in the
#'   run.
#' * `tool_annotations`, `tool_arguments`, `tool_metadata` (PreToolUse,
#'   PermissionRequest): the tool's annotations, declared arguments and
#'   [tool_metadata()], when available.
#' * `usage`, `cost`, `ending` (Stop, SessionEnd): the run's [AgentUsage], the
#'   conversation's cost, as returned by `agent$cost()`, and the run's
#'   [RunEnding] as it stands.
#' * `stop_hook_active` (Stop): `TRUE` when a hook has already sent this run
#'   on.
#' * `total_turns`, `compact_count` (PreCompact, PostCompact): the number of
#'   turns in the conversation and the number being summarised.
#' * `automatic` (PostCompact): `TRUE` when compaction ran automatically
#'   during a run rather than through `compact()`.
#' * `child_agent_id`, `child_run_id`, `status` (SubagentStart, SubagentStop):
#'   the subagent's identifiers and status.
#' * `level`, `code` (Notification): a severity such as `"info"` or
#'   `"warning"`, and a notification code when there is one.
#' * `permissions`, `provider`, `tools_count` (SessionStart): the agent's
#'   [Permissions], a list with the provider `name` and `model`, and the
#'   number of registered tools.
#'
#' @seealso `vignette("hooks")`
#' @examples
#' \dontrun{
#' # Log each tool call. Returning NULL leaves the decision to other hooks.
#' agent$add_hook(HookMatcher(
#'   event = "PreToolUse",
#'   callback = function(tool_name, tool_input, context) {
#'     message("Tool: ", tool_name, " in ", context$working_dir)
#'     NULL
#'   }
#' ))
#'
#' # Stop the run when a tool fails
#' agent$add_hook(HookMatcher(
#'   event = "PostToolUse",
#'   callback = function(tool_name, tool_result, tool_error, context) {
#'     if (!is.null(tool_error)) {
#'       return(HookResultPostToolUse(continue = FALSE))
#'     }
#'     NULL
#'   }
#' ))
#' }
#'
#' @export
HookEvent <- c(
  "PreToolUse",
  "PostToolUse",
  "PostToolUseFailure",
  "PostModelRequest",

  "Stop",
  "SubagentStart",
  "SubagentStop",
  "UserPromptSubmit",
  "Notification",
  "PermissionRequest",
  "ConfigChange",
  "PreCompact",
  "PostCompact",

  "SessionStart",
  "SessionEnd"
)

#' Create a hook
#'
#' @description
#' `HookMatcher()` pairs a callback with a [hook event][HookEvent] and,
#' optionally, a tool-name pattern. Add it to an agent with
#' `agent$add_hook()`. The object is read-only; read its fields with `@` or
#' `S7::prop()`.
#'
#' @param event One of [HookEvent].
#' @param callback A function taking the arguments listed for `event` in
#'   [HookEvent], or `...`. `HookMatcher()` errors if the arguments don't fit.
#' @param pattern Optional regular expression matched against the tool name.
#'   A hook with a pattern only fires for events that have a tool name.
#' @param timeout Time limit for the callback, in seconds. The default, 0,
#'   runs the callback in your R session with no limit. A positive value runs
#'   it in a fresh R process with [callr::r()]. That process can't see your
#'   global variables or attached packages (call functions as `pkg::fn()`),
#'   and its printed output and other side effects stay there. Such a
#'   callback can't return a promise.
#' @param promise_timeout Time limit, in seconds, for a promise the callback
#'   returns. The default is 60. A promise that has not settled by then counts
#'   as no answer and is recorded as a hook error. For PreToolUse that denies
#'   the call.
#' @return A `HookMatcher` object.
#' @seealso [hook_matches()]
#' @examples
#' hook <- HookMatcher(
#'   "PreToolUse",
#'   callback = function(tool_name, tool_input, context) {
#'     HookResultPreToolUse(permission = "deny", reason = "Read only")
#'   },
#'   pattern = "^write_"
#' )
#' hook_matches(hook, "write_file")
#' S7::prop(hook, "event")
#' @export
HookMatcher <- S7::new_class(
  "HookMatcher",
  package = "deputy",
  properties = list(
    event = readonly_property("event", S7::class_character),
    callback = readonly_property("callback", S7::class_function),
    pattern = readonly_property(
      "pattern",
      S7::new_union(S7::class_character, NULL)
    ),
    timeout = readonly_property("timeout", S7::class_numeric),
    promise_timeout = readonly_property(
      "promise_timeout",
      S7::class_numeric
    )
  ),
  constructor = function(
    event,
    callback,
    pattern = NULL,
    timeout = 0,
    promise_timeout = 60
  ) {
    if (!is_nonempty_string(event) || !event %in% HookEvent) {
      cli_abort(c(
        "Invalid hook event: {.val {event}}",
        "i" = "Valid events are: {.val {HookEvent}}"
      ))
    }
    if (!is.function(callback)) {
      cli_abort("{.arg callback} must be a function")
    }
    validate_hook_callback(event, callback)
    validate_hook_pattern(pattern)
    timeout <- validate_hook_timeout(timeout)
    promise_timeout <- validate_hook_promise_timeout(promise_timeout)
    value <- S7::new_object(
      S7::S7_object(),
      event = event,
      callback = callback,
      pattern = pattern,
      timeout = timeout,
      promise_timeout = promise_timeout
    )
    freeze_value(value)
  }
)

#' Test whether a hook matches a tool name
#'
#' @param hook A [HookMatcher].
#' @param tool_name One tool name, or `NULL`. A hook without a pattern matches
#'   every name, including `NULL`; a hook with a pattern never matches `NULL`.
#' @return `TRUE` or `FALSE`.
#' @export
hook_matches <- S7::new_generic(
  "hook_matches",
  "hook",
  function(hook, tool_name = NULL) {
    S7::S7_dispatch()
  }
)

S7::method(hook_matches, HookMatcher) <- function(hook, tool_name = NULL) {
  if (!is.null(tool_name) && !is_nonempty_string(tool_name)) {
    cli_abort("{.arg tool_name} must be NULL or one non-empty string")
  }
  if (is.null(hook@pattern)) {
    return(TRUE)
  }
  if (is.null(tool_name)) {
    return(FALSE)
  }
  grepl(hook@pattern, tool_name)
}

S7::method(print, HookMatcher) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<HookMatcher>")
    cli::cli_div(theme = list(div = list("margin-left" = 2)))
    cli::cli_text("event: {x@event}")
    cli::cli_text("pattern: {if (is.null(x@pattern)) '<any>' else x@pattern}")
    cli::cli_text("timeout: {x@timeout} seconds")
  }))
  invisible(x)
}

# The value, or a promise of it, passed to `fn`. Synchronous when `value` is
# not a promise, so code that never sees a promise runs exactly as before.
hook_then <- function(value, fn) {
  if (promises::is.promising(value)) promises::then(value, fn) else fn(value)
}

# For a caller that cannot wait: a promise counts as no answer. The promise
# `fire()` returns never rejects, so dropping it is safe.
hook_unawaited <- function(result) {
  if (promises::is.promising(result)) NULL else result
}

# Fires hooks on `registry` through `fire` (a function of no arguments) and
# hands `record` the errors of that firing only: once for those raised before
# `fire` returned, and again when a promised result settles. Other firings
# pending against the same registry are not this one's.
fire_with_errors <- function(registry, fire, record) {
  fire_id <- registry$reserve_fire_id()
  copied <- 0L
  copy <- function() {
    errors <- registry$errors_from(fire_id)
    if (length(errors) > copied) {
      record(errors[seq.int(copied + 1L, length(errors))])
      copied <<- length(errors)
    }
    invisible(NULL)
  }
  # On exit, so the errors raised before `fire` threw are handed over too.
  on.exit(copy(), add = TRUE)
  hook_then(fire(), function(value) {
    copy()
    value
  })
}

# A promise that settles as `promise` does, or rejects after `seconds`.
hook_promise_timeout <- function(promise, seconds, event) {
  promises::promise(function(resolve, reject) {
    cancel <- later::later(
      function() {
        reject(rlang::error_cnd(
          class = c("deputy_hook_timeout", "deputy_error"),
          message = sprintf(
            "%s hook's promise did not settle within %s seconds",
            event,
            format(seconds)
          )
        ))
      },
      seconds
    )
    promises::then(
      promises::as.promise(promise),
      onFulfilled = function(value) {
        cancel()
        resolve(value)
      },
      onRejected = function(error) {
        cancel()
        reject(error)
      }
    )
  })
}

#' Hook registry
#'
#' @description
#' Holds an agent's hooks, finds the ones that match an event, and runs them.
#' Each agent has its own registry in `agent$hooks`; add hooks with
#' `agent$add_hook()`.
#'
#' @keywords internal
HookRegistry <- R6::R6Class(
  "HookRegistry",

  public = list(
    #' @description
    #' Create an empty registry.
    initialize = function() {
      private$assert_configurable()
      private$hooks <- list()
    },

    #' @description
    #' Add a hook to the registry.
    #'
    #' @param hook A [HookMatcher].
    #' @return The registry, invisibly.
    add = function(hook) {
      private$assert_configurable()
      if (!S7::S7_inherits(hook, HookMatcher)) {
        cli_abort("{.arg hook} must be a HookMatcher object")
      }
      private$hooks <- c(private$hooks, list(hook))
      invisible(self)
    },

    #' @description
    #' Get the hooks that match an event.
    #'
    #' @param event A [HookEvent].
    #' @param tool_name Optional tool name to match against hook patterns.
    #' @return A list of [HookMatcher] objects.
    get_hooks = function(event, tool_name = NULL) {
      matching <- list()
      for (hook in private$hooks) {
        if (hook@event == event && hook_matches(hook, tool_name)) {
          matching <- c(matching, list(hook))
        }
      }
      matching
    },

    #' @description
    #' Run the matching hooks in the order they were added and return the
    #' first non-`NULL` result. Later hooks don't run. When a callback returns
    #' a promise, later hooks wait for it, and the promise `fire()` returns
    #' resolves to that result.
    #'

    #' A failing callback is recorded in `last_errors()`. For PreToolUse the
    #' failure denies the tool call; for other events it is reported and the
    #' next hook runs.
    #'
    #' @param event A [HookEvent].
    #' @param tool_name Optional tool name, matched against hook patterns and
    #'   passed to the callback.
    #' @param ... Other arguments for the callback.
    #' @return The first non-`NULL` result, or `NULL`. A promise of it when a
    #'   callback returned a promise.
    fire = function(event, tool_name = NULL, ...) {
      hooks <- self$get_hooks(event, tool_name)

      # Build args list including tool_name if provided
      args <- list(...)
      if (!is.null(tool_name)) {
        args <- c(list(tool_name = tool_name), args)
      }

      fire_id <- private$reserved_fire_id
      private$reserved_fire_id <- NULL
      if (is.null(fire_id)) {
        private$fire_count <- private$fire_count + 1L
        fire_id <- private$fire_count
      }

      private$fire_from(hooks, 1L, event, tool_name, args, fire_id)
    },

    #' @description
    #' Reserve the ID of the next `fire()` call, so that its errors can be
    #' found afterwards with `errors_from()`. Call it immediately before
    #' `fire()`.
    #' @return The ID, an integer.
    reserve_fire_id = function() {
      private$fire_count <- private$fire_count + 1L
      private$reserved_fire_id <- private$fire_count
      private$reserved_fire_id
    },

    #' @description
    #' Get the errors hook callbacks have raised since the registry was created
    #' or last cleared. Use it to check logging hooks, whose failures don't
    #' stop the run.
    #'
    #' @return A list of records with `event`, `tool_name`, `error`,
    #'   `timestamp` and `fire_id`, the ID of the `fire()` call that raised
    #'   the error.
    last_errors = function() {
      private$hook_errors
    },

    #' @description
    #' Get the errors raised by one `fire()` call, including those of promises
    #' that settled later.
    #' @param fire_id An ID from `reserve_fire_id()`.
    #' @return A list of records, as `last_errors()` returns.
    errors_from = function(fire_id) {
      Filter(
        function(error) identical(error$fire_id, fire_id),
        private$hook_errors
      )
    },

    #' @description
    #' Clear the recorded errors.
    clear_errors = function() {
      private$hook_errors <- list()
      invisible(self)
    },

    #' @description
    #' Get the number of registered hooks.
    #' @return An integer.
    count = function() {
      length(private$hooks)
    },

    #' @description
    #' Print the registry.
    print = function() {
      cli::cat_line(cli::cli_format_method({
        cli::cli_text("<HookRegistry>")
        cli::cli_div(theme = list(div = list("margin-left" = 2)))
        cli::cli_text("hooks: {self$count()} registered")

        if (self$count() > 0) {
          # Group by event
          by_event <- list()
          for (hook in private$hooks) {
            event <- hook@event
            if (is.null(by_event[[event]])) {
              by_event[[event]] <- 0
            }
            by_event[[event]] <- by_event[[event]] + 1
          }

          for (event in names(by_event)) {
            cli::cli_text("{event} : {by_event[[event]]}")
          }
        }
      }))
      invisible(self)
    }
  ),

  private = list(
    call_hook = function(hook, args) {
      if (hook@timeout > 0) {
        callr::r(
          child_function(function(callback, args) {
            do.call(callback, args)
          }),
          args = list(callback = hook@callback, args = args),
          timeout = hook@timeout
        )
      } else {
        do.call(hook@callback, args)
      }
    },

    hook_failed = function(event, tool_name, error, fire_id) {
      error_message <- if (inherits(error, "condition")) {
        conditionMessage(error)
      } else {
        paste(format(error), collapse = " ")
      }

      # Track the error for programmatic access
      error_info <- list(
        event = event,
        tool_name = tool_name,
        error = error_message,
        timestamp = Sys.time(),
        fire_id = fire_id
      )
      private$hook_errors <- c(private$hook_errors, list(error_info))

      # Use prominent error logging for all hook failures
      # PreToolUse failures are security-critical
      if (event == "PreToolUse") {
        cli::cli_alert_danger(c(
          "PreToolUse hook failed - denying tool for safety",
          "x" = "{error_message}"
        ))
        return(HookResultPreToolUse(
          permission = "deny",
          reason = paste("Hook error:", error_message)
        ))
      }

      # For other events, log prominently but continue execution
      # These could be logging/audit hooks that shouldn't crash the agent
      severity <- switch(
        event,
        "PostToolUse" = "PostToolUse hook failed (audit/logging may be incomplete)",
        "Stop" = "Stop hook failed (cleanup may be incomplete)",
        "SessionEnd" = "SessionEnd hook failed (state may not be saved)",
        "SessionStart" = "SessionStart hook failed (initialization may be incomplete)",
        paste0(event, " hook failed")
      )

      cli::cli_alert_danger(c(
        "{severity}",
        "x" = "{error_message}",
        "i" = "Use registry$last_errors() to inspect hook failures"
      ))

      NULL
    },

    fire_from = function(hooks, index, event, tool_name, args, fire_id) {
      while (index <= length(hooks)) {
        hook <- hooks[[index]]
        result <- tryCatch(
          private$call_hook(hook, args),
          error = function(e) private$hook_failed(event, tool_name, e, fire_id)
        )
        if (promises::is.promising(result)) {
          rest <- index + 1L
          settled <- promises::then(
            hook_promise_timeout(result, hook@promise_timeout, event),
            onFulfilled = function(value) value,
            onRejected = function(error) {
              private$hook_failed(event, tool_name, error, fire_id)
            }
          )
          return(promises::then(settled, function(value) {
            if (!is.null(value)) {
              return(value)
            }
            private$fire_from(hooks, rest, event, tool_name, args, fire_id)
          }))
        }
        if (!is.null(result)) {
          return(result)
        }
        index <- index + 1L
      }
      NULL
    },

    configuration_locked = FALSE,
    assert_configurable = function() {
      if (private$configuration_locked) {
        conversation_abort(
          "Hook configuration belongs to a retained conversation until release."
        )
      }
    },
    hooks = list(),
    hook_errors = list(),
    fire_count = 0L,
    reserved_fire_id = NULL
  )
)
