test_that("UsageLimits validates and normalizes limits", {
  limits <- UsageLimits(
    max_requests = 3,
    max_tool_calls = 4,
    max_input_tokens = 100,
    max_output_tokens = 50,
    max_total_tokens = 140,
    max_cost_usd = 0.25,
    on_exceed = "error"
  )

  expect_s7_class(limits, UsageLimits)
  expect_identical(limits$max_requests, 3L)
  expect_identical(limits$max_tool_calls, 4L)
  expect_equal(limits$max_cost_usd, 0.25)
  expect_equal(limits$on_exceed, "error")
})

test_that("UsageLimits rejects invalid values", {
  expect_error(UsageLimits(max_requests = -1), "non-negative")
  expect_error(UsageLimits(max_tool_calls = 1.5), "whole number")
  expect_error(
    UsageLimits(max_total_tokens = .Machine$integer.max + 1),
    "no greater than"
  )
  expect_error(UsageLimits(max_cost_usd = Inf), "non-negative")
  expect_error(UsageLimits(on_exceed = "warn"), "should be one of")
})

test_that("UsageLimits takes on_unknown_cost and rejects other values", {
  expect_identical(UsageLimits()$on_unknown_cost, "stop")
  expect_identical(
    UsageLimits(on_unknown_cost = "continue")$on_unknown_cost,
    "continue"
  )
  expect_error(UsageLimits(on_unknown_cost = "maybe"), "should be one of")
})

test_that("every UsageLimits property is a limit or a named option", {
  expect_setequal(
    setdiff(names(S7::props(UsageLimits())), usage_limit_fields()),
    c("on_unknown_cost", "on_exceed")
  )
})

test_that("per-run limits inherit unspecified agent defaults", {
  defaults <- UsageLimits(
    max_requests = 5,
    max_output_tokens = 200,
    max_cost_usd = 0.25,
    on_exceed = "error"
  )
  override <- UsageLimits(max_tool_calls = 2)

  merged <- merge_usage_limits(override, defaults)

  expect_identical(merged$max_requests, 5L)
  expect_identical(merged$max_tool_calls, 2L)
  expect_identical(merged$max_output_tokens, 200L)
  expect_equal(merged$max_cost_usd, 0.25)
  expect_identical(merged$on_exceed, "stop")
  expect_identical(defaults$max_tool_calls, NULL)
  expect_identical(override$max_requests, NULL)
  expect_identical(
    merge_usage_limits(UsageLimits(), UsageLimits()),
    UsageLimits()
  )
})

test_that("a per-run limit keeps its own on_unknown_cost when merged", {
  defaults <- UsageLimits(max_cost_usd = 0.25, on_unknown_cost = "stop")
  override <- UsageLimits(max_tool_calls = 2, on_unknown_cost = "continue")

  expect_identical(
    merge_usage_limits(override, defaults)$on_unknown_cost,
    "continue"
  )
  expect_identical(
    merge_usage_limits(
      UsageLimits(max_tool_calls = 2),
      UsageLimits(on_unknown_cost = "continue")
    )$on_unknown_cost,
    "stop"
  )
})

test_that("limits saved before on_unknown_cost existed are rebuilt with the default", {
  props <- S7::props(UsageLimits(max_requests = 3L))
  props$on_unknown_cost <- NULL

  limits <- do.call(UsageLimits, props)

  expect_identical(limits$max_requests, 3L)
  expect_identical(limits$on_unknown_cost, "stop")
})

test_that("limits print on_unknown_cost only when it is not the default", {
  default_output <- capture_output(print(UsageLimits(max_requests = 3)))
  continue_output <- capture_output(print(
    UsageLimits(max_requests = 3, on_unknown_cost = "continue")
  ))

  expect_no_match(default_output, "on_unknown_cost", fixed = TRUE)
  expect_match(continue_output, "on_unknown_cost: continue", fixed = TRUE)
})

test_that("intersecting limits stops on an unknown cost when either side does", {
  continues <- UsageLimits(max_cost_usd = 1, on_unknown_cost = "continue")
  stops <- UsageLimits(max_requests = 3)

  expect_identical(
    intersect_usage_limits(continues, continues)$on_unknown_cost,
    "continue"
  )
  expect_identical(
    intersect_usage_limits(continues, stops)$on_unknown_cost,
    "stop"
  )
  expect_identical(
    intersect_usage_limits(stops, continues)$on_unknown_cost,
    "stop"
  )
})

test_that("usage values freeze stored and initially unset properties", {
  usage <- AgentUsage(input_tokens = 10, output_tokens = 5, cost_usd = NA_real_)
  limits <- UsageLimits()
  expect_snapshot(error = TRUE, usage@requests <- 2L)
  expect_snapshot(error = TRUE, usage$total_tokens <- 999)
  expect_snapshot(error = TRUE, usage@total_tokens <- 999)
  expect_snapshot(error = TRUE, usage@cost_usd <- 0)
  expect_snapshot(error = TRUE, limits@max_requests <- 2L)
  expect_snapshot(error = TRUE, limits$on_exceed <- "error")
  expect_snapshot(error = TRUE, S7::props(limits) <- list(max_cost_usd = 1))
  expect_snapshot(error = TRUE, S7::props(usage) <- list(input_tokens = 999))
  expect_identical(usage$total_tokens, 15)
  expect_identical(usage$cost_usd, NA_real_)
  expect_identical(limits$max_requests, NULL)
})

test_that("usage property projections are independent plain records", {
  usage <- AgentUsage(input_tokens = 10, output_tokens = 5, cached_tokens = 8)
  fields <- S7::props(usage)
  expect_identical(class(fields), "list")
  expect_named(
    fields,
    c(
      "requests",
      "tool_calls",
      "input_tokens",
      "output_tokens",
      "cached_tokens",
      "total_tokens",
      "cost_usd",
      "known_cost_usd"
    )
  )
  fields$total_tokens <- 1000
  expect_identical(usage$total_tokens, 15)
  limits <- UsageLimits(max_requests = 3, max_cost_usd = 0)
  saved <- S7::props(limits)
  expect_identical(do.call(UsageLimits, saved), limits)
  saved$max_requests <- 8L
  expect_identical(limits$max_requests, 3L)
})

test_that("runtime limits and results require genuine S7 values", {
  fake_limits <- structure(
    list(max_requests = 1L),
    class = c("UsageLimits", "list")
  )
  fake_usage <- structure(list(requests = 1L), class = c("AgentUsage", "list"))
  expect_snapshot(error = TRUE, normalize_usage_limits(fake_limits))
  expect_snapshot(error = TRUE, merge_usage_limits(fake_limits, UsageLimits()))
  expect_snapshot(error = TRUE, merge_usage_limits(UsageLimits(), fake_limits))
  expect_snapshot(error = TRUE, AgentResult(usage = fake_usage))
})

test_that("AgentUsage reports total tokens without double counting cache", {
  usage <- AgentUsage(
    requests = 2,
    tool_calls = 3,
    input_tokens = 100,
    output_tokens = 40,
    cached_tokens = 80,
    cost_usd = 0.02
  )

  expect_s7_class(usage, AgentUsage)
  expect_identical(usage$requests, 2L)
  expect_identical(usage$tool_calls, 3L)
  expect_equal(usage$total_tokens, 140)
  expect_equal(usage$cached_tokens, 80)
})

test_that("AgentUsage rejects malformed counters", {
  expect_error(AgentUsage(requests = 1.5), "whole number")
  expect_error(AgentUsage(tool_calls = -1), "non-negative")
  expect_error(AgentUsage(input_tokens = NA_real_), "non-negative")
  expect_error(AgentUsage(cost_usd = NULL), "non-negative")
})

test_that("AgentUsage preserves unknown provider cost", {
  usage <- AgentUsage(cost_usd = NA_real_)

  expect_identical(usage$cost_usd, NA_real_)
  expect_identical(
    agent_usage_difference(usage, AgentUsage())$cost_usd,
    NA_real_
  )
  expect_identical(
    agent_usage_add(AgentUsage(cost_usd = 0.1), usage)$cost_usd,
    NA_real_
  )
})

test_that("provider cost summaries distinguish zero from unknown", {
  complete <- provider_cost_summary(data.frame(cost = c(0, 0)))
  incomplete <- provider_cost_summary(data.frame(cost = c(0, NA_real_)))
  absent <- provider_cost_summary(data.frame(input = 1))
  missing_record <- provider_cost_summary(
    data.frame(cost = numeric()),
    expected_records = 1L
  )

  expect_identical(complete$total, 0)
  expect_identical(complete$complete, TRUE)
  expect_identical(complete$missing, 0L)
  expect_identical(incomplete$total, NA_real_)
  expect_identical(incomplete$complete, FALSE)
  expect_identical(incomplete$missing, 1L)
  expect_identical(absent$total, NA_real_)
  expect_identical(absent$complete, FALSE)
  expect_identical(absent$missing, 1L)
  expect_identical(missing_record$total, NA_real_)
  expect_identical(missing_record$complete, FALSE)
  expect_identical(missing_record$missing, 1L)
})

test_that("usage differences are scoped to the current run", {
  before <- AgentUsage(
    requests = 4,
    input_tokens = 100,
    output_tokens = 20,
    cached_tokens = 50,
    cost_usd = 0.1
  )
  after <- AgentUsage(
    requests = 6,
    input_tokens = 160,
    output_tokens = 45,
    cached_tokens = 70,
    cost_usd = 0.16
  )

  usage <- agent_usage_difference(after, before, tool_calls = 3)

  expect_identical(usage$requests, 2L)
  expect_identical(usage$tool_calls, 3L)
  expect_equal(usage$input_tokens, 60)
  expect_equal(usage$output_tokens, 25)
  expect_equal(usage$cached_tokens, 20)
  expect_equal(usage$cost_usd, 0.06, tolerance = 1e-12)
  expect_identical(before$requests, 4L)
  expect_identical(after$requests, 6L)
})

test_that("preserving run accounting constructs a separate usage value", {
  agent <- Agent$new(chat = create_mock_chat())
  private <- agent$.__enclos_env__$private
  private$current_tool_calls <- 2L
  usage <- AgentUsage(
    requests = 3,
    tool_calls = 5,
    input_tokens = 10,
    cost_usd = NA_real_
  )
  preserve_run_usage(agent, usage)
  expect_identical(usage$tool_calls, 5L)
  expect_equal(
    private$current_external_usage,
    AgentUsage(
      requests = 3,
      tool_calls = 3,
      input_tokens = 10,
      cost_usd = NA_real_
    )
  )
  expect_identical(private$current_outer_requests, 0L)
  expect_s7_class(private$current_usage_baseline, AgentUsage)
})

test_that("run cost ignores incomplete records from earlier turns", {
  turns <- list(create_mock_assistant_turn(cost = NA_real_))
  costs <- NA_real_
  chat <- create_mock_chat()
  chat$get_turns <- function() turns
  chat$get_tokens <- function() {
    data.frame(
      input = rep(1, length(costs)),
      output = rep(1, length(costs)),
      cached_input = rep(0, length(costs)),
      cost = costs
    )
  }

  baseline <- agent_usage_snapshot(chat)
  turns <- c(turns, list(create_mock_assistant_turn(cost = 0.02)))
  costs <- c(costs, 0.02)
  current <- agent_usage_snapshot(chat)

  expect_identical(baseline$cost_usd, NA_real_)
  expect_equal(
    agent_usage_difference(current, baseline)$cost_usd,
    0.02
  )
})

test_that("real partial turns keep usage evidence available for unpaired histories", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://127.0.0.1:1",
    model = "fixture",
    credentials = function() "unused"
  )
  completed <- ellmer::AssistantTurn("Done", tokens = c(10, 5, 2), cost = 0.01)
  partial <- ellmer::AssistantPartialTurn()
  chat$set_turns(list(
    ellmer::UserTurn("First"),
    completed,
    ellmer::UserTurn("Interrupted request"),
    partial
  ))

  usage <- agent_usage_snapshot(chat)
  expect_identical(usage$requests, 2L)
  expect_equal(usage$input_tokens, 10)
  expect_equal(usage$output_tokens, 5)
  expect_equal(usage$cached_tokens, 2)
  expect_identical(usage$cost_usd, NA_real_)
  expect_identical(
    usage_limit_status(usage, UsageLimits(max_cost_usd = 1))$reason,
    "cost_unavailable"
  )
  # The producer represents missing reports with NA rather than NULL/short
  # properties; invalid shapes are rejected before Deputy receives the turn.
  expect_identical(partial@tokens, rep(NA_real_, 3L))
  expect_identical(partial@cost, NA_real_)
  expect_error(ellmer::AssistantTurn(tokens = numeric()), "length three")
  expect_error(ellmer::AssistantTurn(cost = NULL))
})

test_that("usage limit status distinguishes reached request limits", {
  limits <- UsageLimits(max_requests = 2, max_tool_calls = 3)
  usage <- AgentUsage(requests = 2, tool_calls = 3)

  expect_null(usage_limit_status(usage, limits))

  request_status <- usage_limit_status(
    usage,
    limits,
    require_followup = TRUE
  )
  expect_equal(request_status$reason, "request_limit")
  expect_equal(request_status$actual, 2)
  expect_equal(request_status$limit, 2)

  tool_status <- usage_limit_status(
    AgentUsage(requests = 1, tool_calls = 4),
    limits
  )
  expect_equal(tool_status$reason, "tool_call_limit")
})

test_that("cost limits fail closed when provider cost is unknown", {
  status <- usage_limit_status(
    AgentUsage(cost_usd = NA_real_),
    UsageLimits(max_cost_usd = 1)
  )

  expect_identical(status$reason, "cost_unavailable")
  expect_identical(status$field, "max_cost_usd")
  expect_identical(status$actual, NA_real_)
  expect_identical(status$limit, 1)
  expect_match(usage_limit_message(status), "cannot be enforced")
})

test_that("a cost limit with on_unknown_cost = 'continue' does not report an unknown cost", {
  status <- usage_limit_status(
    AgentUsage(cost_usd = NA_real_),
    UsageLimits(max_cost_usd = 1, on_unknown_cost = "continue")
  )

  expect_null(status)
})

test_that("usage limit defaults use the native request limit", {
  limits <- normalize_usage_limits(NULL)

  expect_identical(limits$max_requests, 25L)
  expect_null(limits$max_cost_usd)
  expect_equal(limits$on_exceed, "stop")
})

test_that("AgentUsage carries the known cost", {
  expect_identical(AgentUsage(cost_usd = 0.02)$known_cost_usd, 0.02)
  expect_identical(AgentUsage(cost_usd = NA_real_)$known_cost_usd, 0)
  expect_identical(
    AgentUsage(cost_usd = NA_real_, known_cost_usd = 0.01)$known_cost_usd,
    0.01
  )
  expect_error(
    AgentUsage(cost_usd = NA_real_, known_cost_usd = -1),
    "non-negative"
  )
  expect_error(
    AgentUsage(cost_usd = NA_real_, known_cost_usd = NA_real_),
    "non-negative"
  )
  # A known cost is the cost, so a supplied known part is ignored then.
  expect_identical(
    AgentUsage(cost_usd = 0.02, known_cost_usd = 0.05)$known_cost_usd,
    0.02
  )
})

test_that("usage saved before the known cost existed is rebuilt", {
  props <- S7::props(AgentUsage(
    requests = 2,
    input_tokens = 10,
    output_tokens = 5,
    cost_usd = NA_real_,
    known_cost_usd = 0.01
  ))
  props$total_tokens <- NULL
  props$known_cost_usd <- NULL

  usage <- do.call(AgentUsage, props)

  expect_identical(usage$cost_usd, NA_real_)
  expect_identical(usage$known_cost_usd, 0)
})

test_that("usage saved with the known cost is rebuilt with it", {
  props <- S7::props(AgentUsage(
    requests = 2,
    input_tokens = 10,
    output_tokens = 5,
    cost_usd = NA_real_,
    known_cost_usd = 0.01
  ))
  props$total_tokens <- NULL

  usage <- do.call(AgentUsage, props)

  expect_identical(usage$cost_usd, NA_real_)
  expect_identical(usage$known_cost_usd, 0.01)
  expect_identical(usage, approval_usage(S7::props(usage)))
})

test_that("a response with no cost leaves the others' cost known", {
  turns <- list(
    create_mock_assistant_turn(cost = 0.02),
    create_mock_assistant_turn(cost = NA_real_),
    create_mock_assistant_turn(cost = 0.03)
  )
  chat <- create_mock_chat()
  chat$get_turns <- function() turns
  chat$get_tokens <- function() {
    data.frame(
      input = rep(1, 3),
      output = rep(1, 3),
      cached_input = rep(0, 3),
      cost = c(0.02, NA_real_, 0.03)
    )
  }

  usage <- agent_usage_snapshot(chat)
  conversation <- conversation_usage_snapshot(chat)

  expect_identical(usage$cost_usd, NA_real_)
  expect_equal(usage$known_cost_usd, 0.05)
  expect_identical(conversation$cost_usd, NA_real_)
  expect_equal(conversation$known_cost_usd, 0.05)
})

test_that("the difference and the sum of two usages keep the known cost", {
  before <- AgentUsage(cost_usd = 0.02)
  after <- AgentUsage(cost_usd = NA_real_, known_cost_usd = 0.05)

  difference <- agent_usage_difference(after, before)

  expect_identical(difference$cost_usd, NA_real_)
  expect_equal(difference$known_cost_usd, 0.03)

  total <- agent_usage_add(AgentUsage(cost_usd = 0.1), after)

  expect_identical(total$cost_usd, NA_real_)
  expect_equal(total$known_cost_usd, 0.15)
})

test_that("a difference taken from provider records keeps the known cost of the added ones", {
  chat <- create_mock_chat()
  turns <- list(create_mock_assistant_turn(cost = 0.02))
  costs <- 0.02
  chat$get_turns <- function() turns
  chat$get_tokens <- function() {
    data.frame(
      input = rep(1, length(costs)),
      output = rep(1, length(costs)),
      cached_input = rep(0, length(costs)),
      cost = costs
    )
  }
  baseline <- agent_usage_snapshot(chat)
  turns <- c(
    turns,
    list(create_mock_assistant_turn(cost = NA_real_)),
    list(create_mock_assistant_turn(cost = 0.03))
  )
  costs <- c(costs, NA_real_, 0.03)
  current <- agent_usage_snapshot(chat)

  difference <- agent_usage_difference(current, baseline)

  expect_identical(difference$cost_usd, NA_real_)
  expect_equal(difference$known_cost_usd, 0.03)
})

test_that("a cost limit that goes on is enforced against the known cost", {
  limits <- UsageLimits(max_cost_usd = 0.05, on_unknown_cost = "continue")

  expect_null(usage_limit_status(
    AgentUsage(cost_usd = NA_real_, known_cost_usd = 0.01),
    limits
  ))

  status <- usage_limit_status(
    AgentUsage(cost_usd = NA_real_, known_cost_usd = 0.06),
    limits
  )
  expect_identical(status$reason, "cost_limit")
  expect_identical(status$field, "max_cost_usd")
  expect_equal(status$actual, 0.06)
  expect_equal(status$limit, 0.05)

  stopping <- UsageLimits(max_cost_usd = 0.05)
  expect_identical(
    usage_limit_status(
      AgentUsage(cost_usd = NA_real_, known_cost_usd = 0.06),
      stopping
    )$reason,
    "cost_unavailable"
  )
})

test_that("what is left of a limit is worked out from the cost the limit is checked against", {
  limits <- UsageLimits(
    max_requests = 10,
    max_cost_usd = 0.50,
    on_unknown_cost = "continue"
  )
  reserved <- c(max_requests = 2, max_cost_usd = 0.10)

  known <- usage_limits_remaining(
    limits,
    AgentUsage(requests = 3L, cost_usd = 0.20),
    reserved
  )
  expect_identical(known$max_requests, 5)
  expect_equal(known$max_cost_usd, 0.20)
  expect_null(known$max_total_tokens)
  expect_named(known, usage_limit_fields())

  # An unknown cost the limits go on without: the known cost is what counts.
  going_on <- usage_limits_remaining(
    limits,
    AgentUsage(requests = 3L, cost_usd = NA_real_, known_cost_usd = 0.15)
  )
  expect_equal(going_on$max_cost_usd, 0.35)

  # An unknown cost the limits stop on leaves nothing that can be worked out.
  stopping <- usage_limits_remaining(
    UsageLimits(max_cost_usd = 0.50),
    AgentUsage(cost_usd = NA_real_, known_cost_usd = 0.15)
  )
  expect_identical(stopping$max_cost_usd, NA_real_)

  spent <- usage_limits_remaining(limits, AgentUsage(cost_usd = 0.75))
  expect_identical(spent$max_cost_usd, 0)
})

test_that("usage prints the known cost only when the cost is unknown and positive", {
  known_output <- capture_output(print(
    AgentUsage(cost_usd = NA_real_, known_cost_usd = 0.01)
  ))
  known_zero_output <- capture_output(print(AgentUsage(cost_usd = NA_real_)))
  default_output <- capture_output(print(AgentUsage(cost_usd = 0.01)))

  expect_match(known_output, "known_cost_usd: ", fixed = TRUE)
  expect_no_match(known_zero_output, "known_cost_usd", fixed = TRUE)
  expect_no_match(default_output, "known_cost_usd", fixed = TRUE)
})

test_that("UsageLimits keeps on_exceed as its seventh argument", {
  # on_unknown_cost was added later; a call written by position before it
  # existed must still mean what it meant.
  limits <- UsageLimits(NULL, NULL, NULL, NULL, NULL, NULL, "error")

  expect_identical(limits$on_exceed, "error")
  expect_identical(limits$on_unknown_cost, "stop")
})
