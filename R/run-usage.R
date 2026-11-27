#' @include value-properties.R
NULL

# Run-scoped usage accounting and limits.

#' Set usage limits for a run
#'
#' @description
#' `UsageLimits()` caps what one run of an [Agent] may use: model requests,
#' tool calls, tokens and estimated cost. Each run starts counting from zero, so
#' earlier turns in the conversation, or in a loaded session, don't count
#' against it. A `NULL` field sets no limit.
#'
#' Request and tool-call limits are checked before each request or tool call.
#' Token and cost limits can only be checked after a response arrives, so a run
#' can go over them by one response.
#'
#' @section When a limit ends a run:
#' By default a request or tool-call limit is a hard ceiling: the run stops
#' and makes no further request. With `on_exceed = "wrap_up"`, a run that
#' reaches `max_requests` or `max_tool_calls` before the model has
#' answered gets one more request, with no tools, and a short instruction to
#' answer now with what it has and say what it could not check. That request is
#' made in addition to `max_requests`, so **with `"wrap_up"` a run may make one
#' request more than `max_requests`** (a run limited to 5 requests may make 6).
#' It is counted in the run's usage, and its answer becomes the result's
#' `response`. The `stop_reason` is still the limit's, and the result's
#' `ending$wrapped_up` is `TRUE`. Token and cost limits never get this
#' request: a run that has reached `max_input_tokens`, `max_output_tokens`,
#' `max_total_tokens` or `max_cost_usd`, or that has less room left under
#' `max_input_tokens` or `max_total_tokens` than its conversation is estimated
#' to take, ends at once, because the extra request is what those limits
#' exist to prevent. The same goes for a run
#' inside a delegation graph or tree whose shared budget is spent, for
#' structured-output runs, for a run that has answered, and for a run that was
#' stopped for another reason. Subagents, specialists and background tasks
#' inherit the lead's `on_exceed`. Setting `"wrap_up"` on a graph applies to its
#' routes. A lead's request count includes its delegates' wrap-up requests
#' and can exceed its own `max_requests` by at most one. An explicit
#' hard request or tool-call limit on an agent, retained conversation or
#' background task still applies. If the extra request fails, the run still
#' ends on the limit.
#'
#' Limits passed to `Agent$new()` apply to every run. Limits passed to a single
#' run take any `NULL` field from the agent's limits, so they can't remove a
#' limit the agent sets. A single run keeps its own `on_exceed` and
#' `on_unknown_cost`; the agent's values for those don't replace them. Subagent
#' runs are also capped by what is left of the lead's budget.
#'
#' The object is read-only: read fields with `$` and create a new one to change
#' a limit.
#'
#' @param max_requests Maximum model requests, counting failed requests,
#'   compaction summaries, structured-output extraction and corrections.
#'   ellmer's own HTTP retries don't count separately.
#' @param max_tool_calls Maximum tool calls the model may request. Denied
#'   calls count too.
#' @param max_input_tokens Maximum input tokens.
#' @param max_output_tokens Maximum output tokens.
#' @param max_total_tokens Maximum input plus output tokens. Cached input
#'   tokens are reported separately and aren't added again.
#' @param max_cost_usd Maximum estimated cost in US dollars. Cost comes from
#'   ellmer's price table; for models newer than your installed ellmer's
#'   bundled table (such as `gpt-6.2-sol` or `gemini-4-neon` on ellmer 0.5.2),
#'   run [ellmer::models_update_prices()] first. If the cost of a response is
#'   unknown, the run stops with `"cost_unavailable"` rather than guessing,
#'   unless `on_unknown_cost = "continue"`.
#' @param on_exceed What happens when a limit is reached. `"stop"` (the
#'   default) ends the run and returns an [AgentResult] whose `stop_reason`
#'   names the limit, such as `"request_limit"`, `"tool_call_limit"` or
#'   `"cost_limit"`. `"error"` ends the run the same way, then signals an error
#'   that inherits from `deputy_budget` (see [deputy-errors]). The result is
#'   still available from `$last_run()`. `"wrap_up"` ends the run on the limit
#'   the same way as `"stop"`, but first makes one more request, without tools,
#'   so the model can answer with what it has; see the section above. Delegates
#'   inherit this choice.
#' @param on_unknown_cost What happens when `max_cost_usd` is set and the cost
#'   of a response is unknown. `"stop"` (the default) ends the run with
#'   `"cost_unavailable"`. `"continue"` lets the run go on. The limit is then
#'   checked against the cost that is known ([AgentUsage]'s `known_cost_usd`),
#'   and a subagent's budget is what that leaves.
#'
#' @return A `UsageLimits` object.
#' @examples
#' UsageLimits(max_requests = 5, max_tool_calls = 10)
#' UsageLimits(max_cost_usd = 0.25, on_exceed = "error")
#' @export
UsageLimits <- S7::new_class(
  "UsageLimits",
  package = "deputy",
  properties = list(
    max_requests = readonly_property(
      "max_requests",
      S7::new_union(NULL, S7::class_integer)
    ),
    max_tool_calls = readonly_property(
      "max_tool_calls",
      S7::new_union(NULL, S7::class_integer)
    ),
    max_input_tokens = readonly_property(
      "max_input_tokens",
      S7::new_union(NULL, S7::class_integer)
    ),
    max_output_tokens = readonly_property(
      "max_output_tokens",
      S7::new_union(NULL, S7::class_integer)
    ),
    max_total_tokens = readonly_property(
      "max_total_tokens",
      S7::new_union(NULL, S7::class_integer)
    ),
    max_cost_usd = readonly_property(
      "max_cost_usd",
      S7::new_union(NULL, S7::class_double)
    ),
    on_exceed = readonly_property("on_exceed", S7::class_character),
    on_unknown_cost = readonly_property(
      "on_unknown_cost",
      S7::class_character
    )
  ),
  constructor = function(
    max_requests = NULL,
    max_tool_calls = NULL,
    max_input_tokens = NULL,
    max_output_tokens = NULL,
    max_total_tokens = NULL,
    max_cost_usd = NULL,
    on_exceed = c("stop", "error", "wrap_up"),
    on_unknown_cost = c("stop", "continue")
  ) {
    on_exceed <- match.arg(on_exceed)
    on_unknown_cost <- match.arg(on_unknown_cost)
    value <- S7::new_object(
      S7::S7_object(),
      max_requests = validate_usage_limit(max_requests, "max_requests"),
      max_tool_calls = validate_usage_limit(max_tool_calls, "max_tool_calls"),
      max_input_tokens = validate_usage_limit(
        max_input_tokens,
        "max_input_tokens"
      ),
      max_output_tokens = validate_usage_limit(
        max_output_tokens,
        "max_output_tokens"
      ),
      max_total_tokens = validate_usage_limit(
        max_total_tokens,
        "max_total_tokens"
      ),
      max_cost_usd = validate_usage_limit(
        max_cost_usd,
        "max_cost_usd",
        integer = FALSE
      ),
      on_exceed = on_exceed,
      on_unknown_cost = on_unknown_cost
    )
    freeze_value(value)
  }
)

register_dollar_prop(UsageLimits)

S7::method(print, UsageLimits) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<UsageLimits>")
    cli::cli_div(theme = list(div = list("margin-left" = 2)))
    for (field in usage_limit_fields()) {
      value <- S7::prop(x, field)
      cli::cli_text("{field}: {value %||% \"unlimited\"}")
    }
    # The default is left out so that existing printed output does not change.
    if (identical(x@on_unknown_cost, "continue")) {
      cli::cli_text("on_unknown_cost: continue")
    }
    cli::cli_text("on_exceed: {x@on_exceed}")
  }))
  invisible(x)
}

#' Create a usage record
#'
#' @description
#' A usage record counts model requests, tool calls, tokens and estimated cost.
#' [AgentResult]`$usage` and the `"usage"` and `"stop"` events cover a single
#' run. [Agent]`$usage()` covers the whole conversation, including turns that
#' compaction removed from the model's context. You rarely need to call
#' `AgentUsage()` yourself.
#'
#' Records are read-only. Read fields with `$`; `S7::props()` returns them all
#' as a plain list, which is handy for logging.
#'
#' @param requests Number of model requests.
#' @param tool_calls Number of tool calls requested, including denied calls.
#' @param input_tokens Input tokens reported by the provider.
#' @param output_tokens Output tokens reported by the provider.
#' @param cached_tokens Cached input tokens reported by the provider. They
#'   aren't added to `total_tokens`.
#' @param cost_usd Estimated cost in US dollars, or `NA_real_` if the cost of
#'   some responses is unknown.
#' @param known_cost_usd The cost of the responses whose cost is known. When
#'   `cost_usd` is known this is ignored: the known cost is `cost_usd`. When
#'   `cost_usd` is `NA_real_`, it is a lower bound and `NULL` (the default)
#'   means `0`.
#'
#' @prop total_tokens `input_tokens + output_tokens`.
#' @prop known_cost_usd The cost of the responses whose cost is known.
#' @return An `AgentUsage` object.
#' @examples
#' AgentUsage(
#'   requests = 2,
#'   tool_calls = 1,
#'   input_tokens = 120,
#'   output_tokens = 30,
#'   cost_usd = 0.002
#' )
#' usage <- AgentUsage(input_tokens = 120, output_tokens = 30, cost_usd = NA_real_)
#' usage$total_tokens
#' S7::props(usage)
#' @export
AgentUsage <- S7::new_class(
  "AgentUsage",
  package = "deputy",
  properties = list(
    requests = readonly_property("requests", S7::class_integer),
    tool_calls = readonly_property("tool_calls", S7::class_integer),
    input_tokens = readonly_property("input_tokens", S7::class_double),
    output_tokens = readonly_property("output_tokens", S7::class_double),
    cached_tokens = readonly_property("cached_tokens", S7::class_double),
    total_tokens = readonly_property("total_tokens", S7::class_double),
    cost_usd = readonly_property("cost_usd", S7::class_double),
    known_cost_usd = readonly_property("known_cost_usd", S7::class_double)
  ),
  constructor = function(
    requests = 0L,
    tool_calls = 0L,
    input_tokens = 0,
    output_tokens = 0,
    cached_tokens = 0,
    cost_usd = 0,
    known_cost_usd = NULL
  ) {
    requests <- validate_agent_usage_value(requests, "requests", integer = TRUE)
    tool_calls <- validate_agent_usage_value(
      tool_calls,
      "tool_calls",
      integer = TRUE
    )
    input_tokens <- validate_agent_usage_value(input_tokens, "input_tokens")
    output_tokens <- validate_agent_usage_value(output_tokens, "output_tokens")
    cached_tokens <- validate_agent_usage_value(cached_tokens, "cached_tokens")
    cost_usd <- validate_agent_usage_value(
      cost_usd,
      "cost_usd",
      allow_unknown = TRUE
    )
    # Like total_tokens, the known cost is derived when the cost is known, so
    # a supplied value is ignored rather than allowed to disagree with it.
    known_cost_usd <- if (!is.na(cost_usd)) {
      cost_usd
    } else if (is.null(known_cost_usd)) {
      0
    } else {
      validate_agent_usage_value(known_cost_usd, "known_cost_usd")
    }
    value <- S7::new_object(
      S7::S7_object(),
      requests = requests,
      tool_calls = tool_calls,
      input_tokens = input_tokens,
      output_tokens = output_tokens,
      cached_tokens = cached_tokens,
      total_tokens = input_tokens + output_tokens,
      cost_usd = cost_usd,
      known_cost_usd = known_cost_usd
    )
    freeze_value(value)
  }
)

register_dollar_prop(AgentUsage)

validate_agent_usage_value <- function(
  value,
  name,
  integer = FALSE,
  allow_unknown = FALSE
) {
  if (
    isTRUE(allow_unknown) &&
      is.numeric(value) &&
      length(value) == 1L &&
      is.na(value)
  ) {
    return(NA_real_)
  }
  value <- validate_usage_limit(value, name, integer = integer)
  if (is.null(value)) {
    cli::cli_abort("{.arg {name}} must be a non-negative number")
  }
  value
}

S7::method(print, AgentUsage) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<AgentUsage>")
    cli::cli_div(theme = list(div = list("margin-left" = 2)))
    cli::cli_text("requests: {x@requests}")
    cli::cli_text("tool_calls: {x@tool_calls}")
    cli::cli_text("tokens: {x@total_tokens}")
    cli::cli_text("cached_tokens: {x@cached_tokens}")
    cli::cli_text("cost_usd: {format_cost(x@cost_usd)}")
    # Shown only when it says something the cost line does not, so existing
    # printed output does not change.
    if (is.na(x@cost_usd) && x@known_cost_usd > 0) {
      cli::cli_text("known_cost_usd: {format_cost(x@known_cost_usd)}")
    }
  }))
  invisible(x)
}

validate_usage_limit <- function(value, name, integer = TRUE) {
  if (is.null(value)) {
    return(NULL)
  }
  if (
    !is.numeric(value) ||
      length(value) != 1 ||
      is.na(value) ||
      !is.finite(value) ||
      value < 0
  ) {
    cli::cli_abort(
      "{.arg {name}} must be NULL or a non-negative length-1 number"
    )
  }
  if (isTRUE(integer) && value != floor(value)) {
    cli::cli_abort("{.arg {name}} must be a whole number")
  }
  max_integer <- .Machine$integer.max
  if (isTRUE(integer) && value > max_integer) {
    cli::cli_abort(
      "{.arg {name}} must be no greater than {.val {max_integer}}"
    )
  }
  if (isTRUE(integer)) as.integer(value) else as.numeric(value)
}

# The properties of UsageLimits that are limits; the others are options.
usage_limit_fields <- function() {
  c(
    "max_requests",
    "max_tool_calls",
    "max_input_tokens",
    "max_output_tokens",
    "max_total_tokens",
    "max_cost_usd"
  )
}

# The usage each limit is checked against, named by limit. A cost that is
# unknown is `NA`, unless the limits say to go on without it: then it is the
# cost that is known, a lower bound.
usage_against_limits <- function(usage, limits) {
  cost <- usage$cost_usd
  if (is.na(cost) && identical(limits$on_unknown_cost, "continue")) {
    cost <- usage$known_cost_usd
  }
  list(
    max_requests = usage$requests,
    max_tool_calls = usage$tool_calls,
    max_input_tokens = usage$input_tokens,
    max_output_tokens = usage$output_tokens,
    max_total_tokens = usage$total_tokens,
    max_cost_usd = cost
  )
}

# What is left of each limit after `usage`, less what is `reserved` for
# others: the budget a subagent or a retained conversation can be given.
# `NULL` where there is no limit, and `NA` where the cost is unknown and the
# limits stop on that.
usage_limits_remaining <- function(limits, usage, reserved = NULL) {
  used <- usage_against_limits(usage, limits)
  fields <- usage_limit_fields()
  remaining <- lapply(fields, function(field) {
    limit <- S7::prop(limits, field)
    if (is.null(limit)) {
      return(NULL)
    }
    held <- if (field %in% names(reserved)) reserved[[field]] else 0
    max(0, limit - used[[field]] - held)
  })
  stats::setNames(remaining, fields)
}

# Reserve a child's possible wrap-up with its requests so concurrent
# delegations draw from the same allowance.
delegation_request_allowance <- function(limits) {
  requests <- limits$max_requests
  if (isTRUE(requests > 0) && identical(limits$on_exceed, "wrap_up")) {
    return(requests + 1)
  }
  requests
}

merge_usage_limits <- function(override, defaults) {
  if (!S7::S7_inherits(override, UsageLimits)) {
    cli::cli_abort("{.arg usage_limits} must be created with UsageLimits()")
  }
  if (!S7::S7_inherits(defaults, UsageLimits)) {
    cli::cli_abort("{.arg defaults} must be created with UsageLimits()")
  }

  resolved <- S7::props(override)
  for (field in usage_limit_fields()) {
    if (is.null(resolved[[field]])) {
      resolved[field] <- list(S7::prop(defaults, field))
    }
  }
  do.call(UsageLimits, resolved)
}

normalize_usage_limits <- function(limits) {
  if (is.null(limits)) {
    return(UsageLimits(max_requests = 25))
  }
  if (!S7::S7_inherits(limits, UsageLimits)) {
    cli::cli_abort("{.arg usage_limits} must be created with UsageLimits()")
  }
  limits
}

usage_snapshot_from_summary <- function(summary, tool_calls = 0L) {
  usage <- AgentUsage(
    requests = summary$requests,
    tool_calls = tool_calls,
    input_tokens = summary$input,
    output_tokens = summary$output,
    cached_tokens = summary$cached,
    cost_usd = summary$total,
    known_cost_usd = summary$known
  )
  attr(usage, "provider_cost_records") <- summary$cost_records
  attr(usage, "provider_usage_totals") <- unlist(
    summary[c("input", "output", "cached")],
    use.names = TRUE
  )
  usage
}

agent_usage_snapshot <- function(chat) {
  usage_snapshot_from_summary(provider_usage_summary(chat))
}

conversation_usage_snapshot <- function(
  chat,
  compacted_turns = list(),
  tool_calls = 0L
) {
  usage_snapshot_from_summary(
    conversation_usage_summary(chat, compacted_turns),
    tool_calls = tool_calls
  )
}

agent_usage_difference <- function(
  current,
  baseline,
  tool_calls = 0L,
  requests = NULL
) {
  non_negative <- function(value) {
    if (is.na(value)) {
      return(NA_real_)
    }
    max(0, value)
  }
  current_costs <- attr(current, "provider_cost_records", exact = TRUE)
  baseline_costs <- attr(baseline, "provider_cost_records", exact = TRUE)
  request_difference <- non_negative(current$requests - baseline$requests)
  if (!is.null(requests)) {
    request_difference <- max(request_difference, requests)
  }
  known <- non_negative(current$known_cost_usd - baseline$known_cost_usd)
  cost <- if (!is.null(current_costs) && !is.null(baseline_costs)) {
    if (length(current_costs) < length(baseline_costs)) {
      NA_real_
    } else if (length(current_costs) > length(baseline_costs)) {
      first <- length(baseline_costs) + 1L
      added <- current_costs[first:length(current_costs)]
      added_cost <- provider_cost_summary(
        data.frame(cost = added),
        expected_records = request_difference
      )
      known <- added_cost$known
      added_cost$total
    } else {
      current_totals <- attr(
        current,
        "provider_usage_totals",
        exact = TRUE
      )
      baseline_totals <- attr(
        baseline,
        "provider_usage_totals",
        exact = TRUE
      )
      provider_changed <- !identical(current_costs, baseline_costs) ||
        !identical(current_totals, baseline_totals)
      if (isTRUE(provider_changed)) {
        non_negative(current$cost_usd - baseline$cost_usd)
      } else if (request_difference == 0L) {
        known <- 0
        0
      } else {
        NA_real_
      }
    }
  } else {
    non_negative(current$cost_usd - baseline$cost_usd)
  }

  AgentUsage(
    requests = request_difference,
    tool_calls = tool_calls,
    input_tokens = non_negative(current$input_tokens - baseline$input_tokens),
    output_tokens = non_negative(
      current$output_tokens - baseline$output_tokens
    ),
    cached_tokens = non_negative(
      current$cached_tokens - baseline$cached_tokens
    ),
    cost_usd = cost,
    known_cost_usd = known
  )
}

agent_usage_add <- function(left, right) {
  AgentUsage(
    requests = left$requests + right$requests,
    tool_calls = left$tool_calls + right$tool_calls,
    input_tokens = left$input_tokens + right$input_tokens,
    output_tokens = left$output_tokens + right$output_tokens,
    cached_tokens = left$cached_tokens + right$cached_tokens,
    cost_usd = left$cost_usd + right$cost_usd,
    known_cost_usd = left$known_cost_usd + right$known_cost_usd
  )
}

# Call after replacing conversation turns, using usage captured before the
# replacement. Run evidence survives mutable context; tool counts retain their
# separate authoritative runtime counter.
preserve_run_usage <- function(agent, usage) {
  if (is.null(usage)) {
    return(invisible(NULL))
  }
  private <- agent$.__enclos_env__$private
  private$current_external_usage <- AgentUsage(
    requests = usage@requests,
    tool_calls = usage@tool_calls - private$current_tool_calls,
    input_tokens = usage@input_tokens,
    output_tokens = usage@output_tokens,
    cached_tokens = usage@cached_tokens,
    cost_usd = usage@cost_usd,
    known_cost_usd = usage@known_cost_usd
  )
  private$current_outer_requests <- 0L
  private$current_usage_baseline <- agent_usage_snapshot(private$.chat)
  invisible(NULL)
}

usage_limit_status <- function(usage, limits, require_followup = FALSE) {
  used <- usage_against_limits(usage, limits)
  checks <- list(
    list(
      field = "max_requests",
      reason = "request_limit",
      label = "model requests",
      reached = require_followup
    ),
    list(
      field = "max_tool_calls",
      reason = "tool_call_limit",
      label = "tool calls",
      reached = FALSE
    ),
    list(
      field = "max_input_tokens",
      reason = "input_token_limit",
      label = "input tokens",
      reached = require_followup
    ),
    list(
      field = "max_output_tokens",
      reason = "output_token_limit",
      label = "output tokens",
      reached = require_followup
    ),
    list(
      field = "max_total_tokens",
      reason = "total_token_limit",
      label = "total tokens",
      reached = require_followup
    ),
    list(
      field = "max_cost_usd",
      reason = "cost_limit",
      label = "estimated cost",
      reached = require_followup
    )
  )

  for (check in checks) {
    limit <- S7::prop(limits, check$field)
    if (is.null(limit)) {
      next
    }
    check$actual <- used[[check$field]]
    # The cost is still unknown here only when the limits stop on that.
    if (identical(check$field, "max_cost_usd") && is.na(check$actual)) {
      check$reason <- "cost_unavailable"
      check$limit <- limit
      return(check)
    }
    exceeded <- check$actual > limit ||
      (isTRUE(check$reached) && check$actual >= limit)
    if (isTRUE(exceeded)) {
      return(c(check, list(limit = limit)))
    }
  }
  NULL
}

usage_limit_message <- function(status) {
  if (identical(status$reason, "cost_unavailable")) {
    return(paste0(
      "Run cost limit cannot be enforced because the provider did not ",
      "report complete cost information. Run `ellmer::models_update_prices()` ",
      "if the model is newer than your installed ellmer price table."
    ))
  }
  paste0(
    "Run limit reached for ",
    status$label,
    ": ",
    status$actual,
    " / ",
    status$limit,
    if (isTRUE(status$reserved > 0)) {
      paste0(" (", status$reserved, " set aside for background tasks)")
    },
    "."
  )
}

intersect_usage_limits <- function(left, right) {
  fields <- S7::props(left)
  for (name in usage_limit_fields()) {
    values <- c(S7::prop(left, name), S7::prop(right, name))
    fields[name] <- list(if (length(values)) min(values) else NULL)
  }
  fields$on_unknown_cost <- if (
    "stop" %in% c(left$on_unknown_cost, right$on_unknown_cost)
  ) {
    "stop"
  } else {
    "continue"
  }
  settings <- c(left$on_exceed, right$on_exceed)
  # A looser hard ceiling still holds when the tighter limit allows one
  # more request. Keep the hard stop when its ceiling determines the limit.
  hard_wrap_up_limit <- function(limits) {
    identical(limits$on_exceed, "stop") &&
      (isTRUE(limits$max_requests == fields$max_requests) ||
        isTRUE(limits$max_tool_calls == fields$max_tool_calls))
  }
  fields$on_exceed <- if ("error" %in% settings) {
    "error"
  } else if (hard_wrap_up_limit(left) || hard_wrap_up_limit(right)) {
    "stop"
  } else if ("wrap_up" %in% settings) {
    "wrap_up"
  } else {
    "stop"
  }
  do.call(UsageLimits, fields)
}

# Internal R6 methods for agent usage accounting, limit enforcement, and
# delegation budget reservations.
deputy_agent_usage_methods <- function(self = NULL, private = NULL) {
  list(
    # The limits for one run: the run's own, merged over the agent's.
    run_usage_limits = function(usage_limits) {
      limits <- if (is.null(usage_limits)) {
        self$usage_limits
      } else {
        merge_usage_limits(usage_limits, self$usage_limits)
      }
      normalize_usage_limits(limits)
    },

    derive_subagent_usage_limits = function(def) {
      limits <- private$current_usage_limits %||% self$usage_limits
      current <- if (isTRUE(private$run_active)) {
        private$current_run_usage()
      } else {
        AgentUsage()
      }
      remaining <- usage_limits_remaining(
        limits,
        current,
        private$reserved_delegation_usage()
      )
      if (!is.null(def$max_requests)) {
        remaining$max_requests <- if (is.null(remaining$max_requests)) {
          def$max_requests
        } else {
          min(remaining$max_requests, def$max_requests)
        }
      }

      do.call(
        UsageLimits,
        c(
          remaining,
          list(
            on_unknown_cost = limits$on_unknown_cost,
            on_exceed = limits$on_exceed
          )
        )
      )
    },

    reserve_delegation_usage = function(delegation_id, limits) {
      fields <- usage_limit_fields()
      reservation <- vapply(
        fields,
        function(field) S7::prop(limits, field) %||% 0,
        numeric(1)
      )
      reservation[["max_requests"]] <- delegation_request_allowance(
        limits
      ) %||%
        0
      private$delegation_usage_reservations[[delegation_id]] <- reservation
      if (is.function(private$.job_checkpoint)) {
        private$.job_checkpoint(
          self,
          list(
            type = "delegation_reserved",
            delegation_id = delegation_id
          )
        )
      }
      invisible(NULL)
    },

    release_delegation_usage = function(delegation_id) {
      private$delegation_usage_reservations[[delegation_id]] <- NULL
      if (is.function(private$.job_checkpoint)) {
        private$.job_checkpoint(
          self,
          list(
            type = "delegation_released",
            delegation_id = delegation_id
          )
        )
      }
      invisible(NULL)
    },

    reserved_delegation_usage = function() {
      fields <- usage_limit_fields()
      reserved <- stats::setNames(numeric(length(fields)), fields)
      for (reservation in private$delegation_usage_reservations) {
        reserved <- reserved + reservation[fields]
      }
      reserved
    },

    current_run_usage = function() {
      baseline <- private$current_usage_baseline %||% AgentUsage()
      current <- agent_usage_snapshot(private$.chat)
      requests <- max(
        current$requests - baseline$requests,
        private$current_outer_requests
      )
      usage <- agent_usage_difference(
        current,
        baseline,
        tool_calls = private$current_tool_calls,
        requests = requests
      )
      agent_usage_add(
        usage,
        private$current_external_usage %||% AgentUsage()
      )
    },

    add_external_usage = function(usage) {
      if (!S7::S7_inherits(usage, AgentUsage)) {
        return(invisible(FALSE))
      }
      private$current_external_usage <- agent_usage_add(
        private$current_external_usage %||% AgentUsage(),
        usage
      )
      if (!is.null(private$current_usage_limits)) {
        limit_status <- private$limit_status(require_followup = TRUE)
        if (!is.null(limit_status)) {
          private$mark_usage_limit(limit_status)
        }
      }
      invisible(TRUE)
    },

    # The run's limit status: graph-tree ceilings take precedence over the
    # agent's own limits (less unsettled background-task reservations).
    limit_status = function(
      require_followup = FALSE,
      usage = NULL,
      limits = NULL
    ) {
      tree_usage_status(self, require_followup = require_followup) %||%
        background_limit_status(
          private,
          usage %||% private$current_run_usage(),
          limits %||% private$current_usage_limits %||% self$usage_limits,
          require_followup
        )
    },

    mark_usage_limit = function(status) {
      if (is.null(status)) {
        return(invisible(NULL))
      }
      if (is.null(private$last_limit_status)) {
        private$last_limit_status <- status
      }
      private$should_stop <- TRUE
      private$stop_reason <- status$reason
      private$stop_requested_by <- NULL

      message <- usage_limit_message(status)
      private$notify(
        message,
        level = "warning",
        code = status$reason,
        usage = private$current_run_usage(),
        limit = status$limit
      )

      private$request_stream_stop(status$reason)
      invisible(status)
    },

    abort_usage_limit = function(status) {
      if (is.null(status)) {
        return(invisible(NULL))
      }
      message <- usage_limit_message(status)
      if (identical(status$reason, "request_limit")) {
        abort_request_limit(
          message,
          current_requests = status$actual,
          max_requests = status$limit,
          run_id = private$current_run_id
        )
      }
      if (identical(status$reason, "cost_unavailable")) {
        abort_cost_unavailable(
          message,
          max_cost = status$limit,
          run_id = private$current_run_id
        )
      }
      abort_budget_exceeded(
        message,
        current_cost = if (identical(status$reason, "cost_limit")) {
          status$actual
        } else {
          NULL
        },
        max_cost = if (identical(status$reason, "cost_limit")) {
          status$limit
        } else {
          NULL
        },
        budget_type = status$field,
        actual = status$actual,
        limit = status$limit,
        run_id = private$current_run_id
      )
    }
  )
}
