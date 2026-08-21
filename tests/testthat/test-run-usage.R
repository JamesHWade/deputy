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

  expect_s3_class(limits, "UsageLimits")
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

  expect_s3_class(usage, "AgentUsage")
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

test_that("usage limit defaults use the native request limit", {
  limits <- normalize_usage_limits(NULL)

  expect_identical(limits$max_requests, 25L)
  expect_null(limits$max_cost_usd)
  expect_equal(limits$on_exceed, "stop")
})
