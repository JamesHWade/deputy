# Set usage limits for a run

`UsageLimits()` caps what one run of an
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) may use:
model requests, tool calls, tokens and estimated cost. Each run starts
counting from zero, so earlier turns in the conversation, or in a loaded
session, don't count against it. A `NULL` field sets no limit.

Request and tool-call limits are checked before each request or tool
call. Token and cost limits can only be checked after a response
arrives, so a run can go over them by one response.

## Usage

``` r
UsageLimits(
  max_requests = NULL,
  max_tool_calls = NULL,
  max_input_tokens = NULL,
  max_output_tokens = NULL,
  max_total_tokens = NULL,
  max_cost_usd = NULL,
  on_exceed = c("stop", "error", "wrap_up"),
  on_unknown_cost = c("stop", "continue")
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

  Maximum estimated cost in US dollars. Cost comes from ellmer's price
  table; for models newer than your installed ellmer's bundled table
  (such as `gpt-6.2-sol` or `gemini-4-neon` on ellmer 0.5.2), run
  [`ellmer::models_update_prices()`](https://ellmer.tidyverse.org/reference/models_update_prices.html)
  first. If the cost of a response is unknown, the run stops with
  `"cost_unavailable"` rather than guessing, unless
  `on_unknown_cost = "continue"`.

- on_exceed:

  What happens when a limit is reached. `"stop"` (the default) ends the
  run and returns an
  [AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
  whose `stop_reason` names the limit, such as `"request_limit"`,
  `"tool_call_limit"` or `"cost_limit"`. `"error"` ends the run the same
  way, then signals an error that inherits from `deputy_budget` (see
  [deputy-errors](https://jameshwade.github.io/deputy/reference/deputy-errors.md)).
  The result is still available from `$last_run()`. `"wrap_up"` ends the
  run on the limit the same way as `"stop"`, but first makes one more
  request, without tools, so the model can answer with what it has; see
  the section above. Delegates inherit this choice.

- on_unknown_cost:

  What happens when `max_cost_usd` is set and the cost of a response is
  unknown. `"stop"` (the default) ends the run with
  `"cost_unavailable"`. `"continue"` lets the run go on. The limit is
  then checked against the cost that is known
  ([AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)'s
  `known_cost_usd`), and a subagent's budget is what that leaves.

## Value

A `UsageLimits` object.

## When a limit ends a run

By default a request or tool-call limit is a hard ceiling: the run stops
and makes no further request. With `on_exceed = "wrap_up"`, a run that
reaches `max_requests` or `max_tool_calls` before the model has answered
gets one more request, with no tools, and a short instruction to answer
now with what it has and say what it could not check. That request is
made in addition to `max_requests`, so **with `"wrap_up"` a run may make
one request more than `max_requests`** (a run limited to 5 requests may
make 6). It is counted in the run's usage, and its answer becomes the
result's `response`. The `stop_reason` is still the limit's, and the
result's `ending$wrapped_up` is `TRUE`. Token and cost limits never get
this request: a run that has reached `max_input_tokens`,
`max_output_tokens`, `max_total_tokens` or `max_cost_usd`, or that has
less room left under `max_input_tokens` or `max_total_tokens` than its
conversation is estimated to take, ends at once, because the extra
request is what those limits exist to prevent. The same goes for a run
inside a delegation graph or tree whose shared budget is spent, for
structured-output runs, for a run that has answered, and for a run that
was stopped for another reason. Subagents, specialists and background
tasks inherit the lead's `on_exceed`. Setting `"wrap_up"` on a graph
applies to its routes. A lead's request count includes its delegates'
wrap-up requests and can exceed its own `max_requests` by at most one.
An explicit hard request or tool-call limit on an agent, retained
conversation or background task still applies. If the extra request
fails, the run still ends on the limit.

Limits passed to `Agent$new()` apply to every run. Limits passed to a
single run take any `NULL` field from the agent's limits, so they can't
remove a limit the agent sets. A single run keeps its own `on_exceed`
and `on_unknown_cost`; the agent's values for those don't replace them.
Subagent runs are also capped by what is left of the lead's budget.

The object is read-only: read fields with `$` and create a new one to
change a limit.

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
