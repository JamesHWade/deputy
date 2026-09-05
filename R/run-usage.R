# Run-scoped usage accounting and limits.

#' Configure run-scoped usage limits
#'
#' @description
#' `UsageLimits()` defines run-scoped stop conditions for one call to [Agent]
#' `$run()` or `$run_sync()`. Limits are evaluated against usage added by that
#' run, not the complete persisted conversation. This keeps resumed sessions
#' from inheriting a spent budget.
#'
#' Request and tool-call limits are checked at model and tool boundaries. Token
#' and cost limits depend on usage reported after a model response, so the run
#' stops after an overage is observed and can exceed a threshold by one
#' response. A `NULL` field leaves that limit unset on this object; when the
#' object configures or overrides an [Agent], Deputy may fill unset fields from
#' the agent's defaults.
#'
#' @param max_requests Maximum governed model dispatches, including failed
#'   calls, automatic compaction, structured extraction, and corrections. Retries
#'   inside ellmer's HTTP transport are not separately observable. `NULL` leaves
#'   the field unset.
#' @param max_tool_calls Maximum requested tool calls. Rejected calls count
#'   toward usage. `NULL` leaves the field unset.
#' @param max_input_tokens Maximum provider-reported input tokens. `NULL` leaves
#'   the field unset.
#' @param max_output_tokens Maximum provider-reported output tokens. `NULL`
#'   leaves the field unset.
#' @param max_total_tokens Maximum input plus output tokens. Cached input is
#'   reported separately and is not counted twice. `NULL` leaves the field
#'   unset.
#' @param max_cost_usd Maximum provider-reported estimated cost in US dollars.
#'   `NULL` leaves the field unset. If configured, missing provider cost data
#'   stops the run with `"cost_unavailable"` rather than undercounting.
#' @param on_exceed What to do when a limit is exceeded. `"stop"` returns an
#'   [AgentResult] with a typed stop reason; `"error"` emits the final usage
#'   event and then signals a structured Deputy limit error.
#'
#' @return A `UsageLimits` object.
#' @examples
#' UsageLimits(max_requests = 5, max_tool_calls = 10)
#' UsageLimits(max_cost_usd = 0.25, on_exceed = "error")
#' @export
UsageLimits <- function(
  max_requests = NULL,
  max_tool_calls = NULL,
  max_input_tokens = NULL,
  max_output_tokens = NULL,
  max_total_tokens = NULL,
  max_cost_usd = NULL,
  on_exceed = c("stop", "error")
) {
  on_exceed <- match.arg(on_exceed)

  integer_limits <- list(
    max_requests = max_requests,
    max_tool_calls = max_tool_calls,
    max_input_tokens = max_input_tokens,
    max_output_tokens = max_output_tokens,
    max_total_tokens = max_total_tokens
  )
  integer_limits <- lapply(
    names(integer_limits),
    function(name) {
      validate_usage_limit(integer_limits[[name]], name, integer = TRUE)
    }
  )
  names(integer_limits) <- c(
    "max_requests",
    "max_tool_calls",
    "max_input_tokens",
    "max_output_tokens",
    "max_total_tokens"
  )

  max_cost_usd <- validate_usage_limit(
    max_cost_usd,
    "max_cost_usd",
    integer = FALSE
  )

  structure(
    c(
      integer_limits,
      list(max_cost_usd = max_cost_usd, on_exceed = on_exceed)
    ),
    class = c("UsageLimits", "list")
  )
}

#' @export
print.UsageLimits <- function(x, ...) {
  cat("<UsageLimits>\n")
  fields <- setdiff(names(x), "on_exceed")
  for (field in fields) {
    value <- x[[field]]
    cat("  ", field, ": ", value %||% "unlimited", "\n", sep = "")
  }
  cat("  on_exceed: ", x$on_exceed, "\n", sep = "")
  invisible(x)
}

#' Create an agent usage record
#'
#' @description
#' `AgentUsage()` creates a normalized usage record. `AgentResult$usage` and
#' run `usage`/`stop` events are scoped to that run, while [Agent]`$usage()`
#' describes the complete in-memory conversation at the time it is called.
#'
#' @param requests Number of model requests attributed to the run.
#' @param tool_calls Number of requested tool calls, including calls rejected
#'   before execution.
#' @param input_tokens Provider-reported input tokens.
#' @param output_tokens Provider-reported output tokens.
#' @param cached_tokens Provider-reported cached input tokens. These are
#'   reported separately and are not added again to `total_tokens`.
#' @param cost_usd Provider-reported estimated cost in US dollars, or `NA_real_`
#'   when the provider did not report complete cost information.
#'
#' @return An `AgentUsage` object.
#' @examples
#' AgentUsage(
#'   requests = 2,
#'   tool_calls = 1,
#'   input_tokens = 120,
#'   output_tokens = 30,
#'   cost_usd = 0.002
#' )
#' @export
AgentUsage <- function(
  requests = 0L,
  tool_calls = 0L,
  input_tokens = 0,
  output_tokens = 0,
  cached_tokens = 0,
  cost_usd = 0
) {
  requests <- validate_agent_usage_value(requests, "requests", integer = TRUE)
  tool_calls <- validate_agent_usage_value(
    tool_calls,
    "tool_calls",
    integer = TRUE
  )
  input_tokens <- validate_agent_usage_value(input_tokens, "input_tokens")
  output_tokens <- validate_agent_usage_value(output_tokens, "output_tokens")
  cached_tokens <- validate_agent_usage_value(
    cached_tokens,
    "cached_tokens"
  )
  cost_usd <- validate_agent_usage_value(
    cost_usd,
    "cost_usd",
    allow_unknown = TRUE
  )

  structure(
    list(
      requests = requests,
      tool_calls = tool_calls,
      input_tokens = input_tokens,
      output_tokens = output_tokens,
      cached_tokens = cached_tokens,
      total_tokens = input_tokens + output_tokens,
      cost_usd = cost_usd
    ),
    class = c("AgentUsage", "list")
  )
}

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

provider_cost_summary <- function(tokens, expected_records = NULL) {
  records <- if (is.null(tokens)) 0L else NROW(tokens)
  expected_records <- expected_records %||% records

  costs <- if (records == 0L) {
    numeric()
  } else if (!"cost" %in% names(tokens)) {
    rep(NA_real_, records)
  } else {
    suppressWarnings(as.numeric(tokens[["cost"]]))
  }
  if (length(costs) < expected_records) {
    costs <- c(costs, rep(NA_real_, expected_records - length(costs)))
  }
  unavailable <- is.na(costs) | !is.finite(costs)
  missing <- sum(unavailable)
  if (missing > 0L) {
    return(list(
      total = NA_real_,
      complete = FALSE,
      missing = as.integer(missing)
    ))
  }

  list(total = sum(costs), complete = TRUE, missing = 0L)
}

provider_usage_summary <- function(chat) {
  turns <- tryCatch(chat$get_turns(), error = function(e) list())
  requests <- sum(vapply(
    turns,
    inherits,
    logical(1),
    what = "ellmer::AssistantTurn"
  ))
  tokens <- tryCatch(chat$get_tokens(), error = function(e) {
    # ellmer 0.5.0's token table assumes paired user/assistant turns. A
    # retained, undispatched tool-result turn breaks its input-preview column.
    # These public producer properties retain the actual usage without adding
    # a fictitious assistant response or changing provider serialization.
    assistant_turn_tokens(turns)
  })
  token_sum <- function(name) {
    if (is.null(tokens) || !name %in% names(tokens)) {
      return(0)
    }
    sum(as.numeric(tokens[[name]]), na.rm = TRUE)
  }
  cost <- provider_cost_summary(tokens, expected_records = requests)
  cost_records <- if (is.null(tokens) || NROW(tokens) == 0L) {
    numeric()
  } else if (!"cost" %in% names(tokens)) {
    rep(NA_real_, NROW(tokens))
  } else {
    suppressWarnings(as.numeric(tokens[["cost"]]))
  }

  list(
    requests = requests,
    input = token_sum("input"),
    output = token_sum("output"),
    cached = token_sum("cached_input"),
    total = cost$total,
    complete = cost$complete,
    missing = cost$missing,
    cost_records = cost_records
  )
}

assistant_turn_tokens <- function(turns) {
  # Released ellmer's S7 AssistantTurn contract requires three numeric token
  # slots and one numeric cost, including for AssistantPartialTurn. Missing
  # reports use NA, which preserves unknown cost through provider_cost_summary.
  assistants <- Filter(
    function(turn) inherits(turn, "ellmer::AssistantTurn"),
    turns
  )
  token <- function(name) {
    vapply(
      assistants,
      function(turn) {
        tokens <- turn@tokens
        position <- match(name, c("input", "output", "cached_input"))
        as.numeric(tokens[[position]])
      },
      numeric(1)
    )
  }
  data.frame(
    input = token("input"),
    output = token("output"),
    cached_input = token("cached_input"),
    cost = vapply(assistants, function(turn) as.numeric(turn@cost), numeric(1))
  )
}

#' @export
print.AgentUsage <- function(x, ...) {
  cat("<AgentUsage>\n")
  cat("  requests: ", x$requests, "\n", sep = "")
  cat("  tool_calls: ", x$tool_calls, "\n", sep = "")
  cat("  tokens: ", x$total_tokens, "\n", sep = "")
  cat("  cached_tokens: ", x$cached_tokens, "\n", sep = "")
  cat("  cost_usd: ", format_cost(x$cost_usd), "\n", sep = "")
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

merge_usage_limits <- function(override, defaults) {
  if (!inherits(override, "UsageLimits")) {
    cli::cli_abort("{.arg usage_limits} must be created with UsageLimits()")
  }
  if (!inherits(defaults, "UsageLimits")) {
    cli::cli_abort("{.arg defaults} must be created with UsageLimits()")
  }

  resolved <- override
  limit_fields <- setdiff(names(defaults), "on_exceed")
  for (field in limit_fields) {
    if (is.null(resolved[[field]])) {
      resolved[[field]] <- defaults[[field]]
    }
  }
  resolved
}

normalize_usage_limits <- function(limits) {
  if (is.null(limits)) {
    return(UsageLimits(max_requests = 25))
  }
  if (!inherits(limits, "UsageLimits")) {
    cli::cli_abort("{.arg usage_limits} must be created with UsageLimits()")
  }
  limits
}

agent_usage_snapshot <- function(chat) {
  summary <- provider_usage_summary(chat)

  usage <- AgentUsage(
    requests = summary$requests,
    input_tokens = summary$input,
    output_tokens = summary$output,
    cached_tokens = summary$cached,
    cost_usd = summary$total
  )
  attr(usage, "provider_cost_records") <- summary$cost_records
  attr(usage, "provider_usage_totals") <- unlist(
    summary[c("input", "output", "cached")],
    use.names = TRUE
  )
  usage
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
  cost <- if (!is.null(current_costs) && !is.null(baseline_costs)) {
    if (length(current_costs) < length(baseline_costs)) {
      NA_real_
    } else if (length(current_costs) > length(baseline_costs)) {
      first <- length(baseline_costs) + 1L
      added <- current_costs[first:length(current_costs)]
      provider_cost_summary(
        data.frame(cost = added),
        expected_records = request_difference
      )$total
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
    cost_usd = cost
  )
}

agent_usage_add <- function(left, right) {
  AgentUsage(
    requests = left$requests + right$requests,
    tool_calls = left$tool_calls + right$tool_calls,
    input_tokens = left$input_tokens + right$input_tokens,
    output_tokens = left$output_tokens + right$output_tokens,
    cached_tokens = left$cached_tokens + right$cached_tokens,
    cost_usd = left$cost_usd + right$cost_usd
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
  usage$tool_calls <- usage$tool_calls - private$current_tool_calls
  private$current_external_usage <- usage
  private$current_outer_requests <- 0L
  private$current_usage_baseline <- agent_usage_snapshot(private$.chat)
  invisible(NULL)
}

usage_limit_status <- function(usage, limits, require_followup = FALSE) {
  checks <- list(
    list(
      field = "max_requests",
      actual = usage$requests,
      reason = "request_limit",
      label = "model requests",
      reached = require_followup
    ),
    list(
      field = "max_tool_calls",
      actual = usage$tool_calls,
      reason = "tool_call_limit",
      label = "tool calls",
      reached = FALSE
    ),
    list(
      field = "max_input_tokens",
      actual = usage$input_tokens,
      reason = "input_token_limit",
      label = "input tokens",
      reached = require_followup
    ),
    list(
      field = "max_output_tokens",
      actual = usage$output_tokens,
      reason = "output_token_limit",
      label = "output tokens",
      reached = require_followup
    ),
    list(
      field = "max_total_tokens",
      actual = usage$total_tokens,
      reason = "total_token_limit",
      label = "total tokens",
      reached = require_followup
    ),
    list(
      field = "max_cost_usd",
      actual = usage$cost_usd,
      reason = "cost_limit",
      label = "estimated cost",
      reached = require_followup
    )
  )

  for (check in checks) {
    limit <- limits[[check$field]]
    if (is.null(limit)) {
      next
    }
    if (identical(check$field, "max_cost_usd") && is.na(check$actual)) {
      check$reason <- "cost_unavailable"
      check$label <- "estimated cost"
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
      "report complete cost information."
    ))
  }
  paste0(
    "Run limit reached for ",
    status$label,
    ": ",
    status$actual,
    " / ",
    status$limit,
    "."
  )
}
