# Set usage limits for a run

`UsageLimits()` caps what one run of an
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) may use:
model requests, tool calls, tokens and estimated cost. Each run starts
counting from zero, so earlier turns in the conversation, or in a loaded
session, don't count against it. A `NULL` field sets no limit.

Request and tool-call limits are checked before each request or tool
call. Token and cost limits can only be checked after a response
arrives, so a run can go over them by one response.

Limits passed to `Agent$new()` apply to every run. Limits passed to a
single run take any `NULL` field from the agent's limits, so they can't
remove a limit the agent sets. Subagent runs are also capped by what is
left of the lead's budget.

The object is read-only: read fields with `$` and create a new one to
change a limit.

## Usage

``` r
UsageLimits(
  max_requests = NULL,
  max_tool_calls = NULL,
  max_input_tokens = NULL,
  max_output_tokens = NULL,
  max_total_tokens = NULL,
  max_cost_usd = NULL,
  on_exceed = c("stop", "error")
)
```

## Arguments

- max_requests:

  Maximum model requests, counting failed requests, compaction
  summaries, structured-output extraction and corrections. ellmer's own
  HTTP retries don't count separately.

- max_tool_calls:

  Maximum tool calls the model may request. Denied calls count too.

- max_input_tokens:

  Maximum input tokens.

- max_output_tokens:

  Maximum output tokens.

- max_total_tokens:

  Maximum input plus output tokens. Cached input tokens are reported
  separately and aren't added again.

- max_cost_usd:

  Maximum estimated cost in US dollars. If the cost of a response is
  unknown, the run stops with `"cost_unavailable"` rather than guessing.

- on_exceed:

  What happens when a limit is reached. `"stop"` (the default) ends the
  run and returns an
  [AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
  whose `stop_reason` names the limit, such as `"request_limit"`,
  `"tool_call_limit"` or `"cost_limit"`. `"error"` ends the run the same
  way, then signals an error that inherits from `deputy_budget` (see
  [deputy-errors](https://jameshwade.github.io/deputy/reference/deputy-errors.md)).
  The result is still available from `$last_run()`.

## Value

A `UsageLimits` object.

## Examples

``` r
UsageLimits(max_requests = 5, max_tool_calls = 10)
#> <UsageLimits>
#>   max_requests: 5
#>   max_tool_calls: 10
#>   max_input_tokens: unlimited
#>   max_output_tokens: unlimited
#>   max_total_tokens: unlimited
#>   max_cost_usd: unlimited
#>   on_exceed: stop
UsageLimits(max_cost_usd = 0.25, on_exceed = "error")
#> <UsageLimits>
#>   max_requests: unlimited
#>   max_tool_calls: unlimited
#>   max_input_tokens: unlimited
#>   max_output_tokens: unlimited
#>   max_total_tokens: unlimited
#>   max_cost_usd: 0.25
#>   on_exceed: error
```
