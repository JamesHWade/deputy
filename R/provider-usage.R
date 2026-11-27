# Provider and ellmer token-table accounting, cost extraction, and turn-based
# fallback usage summaries.

extract_token_costs <- function(tokens) {
  records <- if (is.null(tokens)) 0L else NROW(tokens)
  if (records == 0L) {
    numeric()
  } else if (!"cost" %in% names(tokens)) {
    rep(NA_real_, records)
  } else {
    suppressWarnings(as.numeric(tokens[["cost"]]))
  }
}

provider_cost_summary <- function(tokens, expected_records = NULL) {
  records <- if (is.null(tokens)) 0L else NROW(tokens)
  expected_records <- expected_records %||% records

  costs <- extract_token_costs(tokens)
  if (length(costs) < expected_records) {
    costs <- c(costs, rep(NA_real_, expected_records - length(costs)))
  }
  unavailable <- is.na(costs) | !is.finite(costs)
  missing <- sum(unavailable)
  known <- sum(costs[!unavailable])
  if (missing > 0L) {
    return(list(
      total = NA_real_,
      known = known,
      complete = FALSE,
      missing = as.integer(missing)
    ))
  }

  list(total = sum(costs), known = known, complete = TRUE, missing = 0L)
}

provider_usage_summary <- function(chat) {
  turns_read <- TRUE
  turns <- tryCatch(chat$get_turns(), error = function(e) {
    turns_read <<- FALSE
    list()
  })
  # ellmer's own get_tokens() is a pure function of the turns, so its summary
  # can be reused until the turn list changes. Replaced methods (subclasses
  # and test doubles) may report other state and are always asked again.
  cacheable <- turns_read && is_ellmer_chat_method(chat, "get_tokens")
  if (cacheable) {
    cached <- attr(chat, "deputy_usage_summary", exact = TRUE)
    if (!is.null(cached) && identical(cached$turns, turns)) {
      return(cached$summary)
    }
  }
  summary <- provider_usage_summary_for(chat, turns, cacheable)
  if (cacheable) {
    # An environment attribute updates the Chat in place, as the request
    # callback registry does. The cache holds the turn list it describes, so
    # identical() compares retained objects (shared elements by pointer).
    attr(chat, "deputy_usage_summary") <- list(
      turns = turns,
      summary = summary
    )
  }
  summary
}

provider_usage_summary_for <- function(chat, turns, ellmer_tokens) {
  requests <- sum(vapply(
    turns,
    inherits,
    logical(1),
    what = "ellmer::AssistantTurn"
  ))
  # ellmer 0.5.0's token table assumes paired user/assistant turns. A
  # retained, undispatched tool-result turn breaks its input-preview column.
  # These public producer properties retain the actual usage without adding
  # a fictitious assistant response or changing provider serialization.
  tokens <- if (ellmer_tokens && ellmer_token_table_fails(turns)) {
    assistant_turn_tokens(turns)
  } else {
    tryCatch(chat$get_tokens(), error = function(e) {
      if (ellmer_tokens) {
        ellmer_token_table_observe(turns, e)
      }
      assistant_turn_tokens(turns)
    })
  }
  token_sum <- function(name) {
    if (is.null(tokens) || !name %in% names(tokens)) {
      return(0)
    }
    sum(as.numeric(tokens[[name]]), na.rm = TRUE)
  }
  cost <- provider_cost_summary(tokens, expected_records = requests)
  cost_records <- extract_token_costs(tokens)

  list(
    requests = requests,
    input = token_sum("input"),
    output = token_sum("output"),
    cached = token_sum("cached_input"),
    total = cost$total,
    known = cost$known,
    complete = cost$complete,
    missing = cost$missing,
    cost_records = cost_records
  )
}

# Whether `chat[[name]]` is ellmer's own Chat method rather than a replacement.
# R6 copies share the method body, so the comparison is a pointer check.
is_ellmer_chat_method <- function(chat, name) {
  if (!is.environment(chat) || !inherits(chat, "Chat")) {
    return(FALSE)
  }
  method <- chat[[name]]
  reference <- ellmer::Chat$public_methods[[name]]
  is.function(method) &&
    is.function(reference) &&
    identical(body(method), body(reference)) &&
    identical(formals(method), formals(reference))
}

# Process-wide observations of ellmer behavior. Each records the method body
# it was learned from, so a different ellmer method is observed afresh.
ellmer_observations <- new.env(parent = emptyenv())

# ellmer 0.5.0 adds one input preview per user turn to a table with one row
# per completed assistant turn, and tibble recycles only length-one columns.
ellmer_token_table_unpaired <- function(turns) {
  users <- 0L
  completed <- 0L
  for (turn in turns) {
    if (inherits(turn, "ellmer::UserTurn")) {
      users <- users + 1L
    } else if (
      inherits(turn, "ellmer::AssistantTurn") &&
        !inherits(turn, "ellmer::AssistantPartialTurn")
    ) {
      completed <- completed + 1L
    }
  }
  users != completed && users != 1L
}

# TRUE only once this ellmer's get_tokens() has been observed to reject an
# unpaired table. Skipping the call then avoids building and discarding the
# same error, with its backtrace, on every usage snapshot.
ellmer_token_table_fails <- function(turns) {
  observed <- ellmer_observations$token_table
  isTRUE(observed$unpaired_fails) &&
    identical(observed$body, body(ellmer::Chat$public_methods$get_tokens)) &&
    ellmer_token_table_unpaired(turns)
}

ellmer_token_table_observe <- function(turns, error) {
  if (
    inherits(error, "tibble_error_assign_incompatible_size") &&
      ellmer_token_table_unpaired(turns)
  ) {
    ellmer_observations$token_table <- list(
      unpaired_fails = TRUE,
      body = body(ellmer::Chat$public_methods$get_tokens)
    )
  }
  invisible(NULL)
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

# Usage for the whole conversation: the turns compaction removed from the
# model's context, followed by the turns still in it. Those removed turns keep
# their reported tokens and cost.
conversation_usage_summary <- function(chat, compacted_turns = list()) {
  summary <- provider_usage_summary(chat)
  earlier <- assistant_turn_tokens(compacted_turns)
  if (NROW(earlier) == 0L) {
    return(summary)
  }
  earlier_total <- function(name) sum(earlier[[name]], na.rm = TRUE)
  earlier_cost <- provider_cost_summary(earlier)
  complete <- isTRUE(summary$complete) && isTRUE(earlier_cost$complete)
  list(
    requests = summary$requests + NROW(earlier),
    input = summary$input + earlier_total("input"),
    output = summary$output + earlier_total("output"),
    cached = summary$cached + earlier_total("cached_input"),
    total = if (complete) summary$total + earlier_cost$total else NA_real_,
    known = summary$known + earlier_cost$known,
    complete = complete,
    missing = summary$missing + earlier_cost$missing,
    cost_records = c(earlier$cost, summary$cost_records)
  )
}

# Tool calls the model asked for in `turns`, including any that were denied.
count_tool_requests <- function(turns) {
  counts <- vapply(
    turns,
    function(turn) {
      if (!inherits(turn, "ellmer::AssistantTurn")) {
        return(0L)
      }
      sum(vapply(
        turn@contents,
        inherits,
        logical(1),
        what = "ellmer::ContentToolRequest"
      ))
    },
    integer(1)
  )
  sum(counts)
}
