# Configure run-scoped usage limits

`UsageLimits()` defines run-scoped stop conditions for one call to
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) `$run()`
or `$run_sync()`. Limits are evaluated against usage added by that run,
not the complete persisted conversation. This keeps resumed sessions
from inheriting a spent budget.

Request and tool-call limits are checked at model and tool boundaries.
Token and cost limits depend on usage reported after a model response,
so the run stops after an overage is observed and can exceed a threshold
by one response. A `NULL` field leaves that limit unset on this object;
when the object configures or overrides an
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md), Deputy
may fill unset fields from the agent's defaults.

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

  Maximum model requests. `NULL` leaves the field unset.

- max_tool_calls:

  Maximum requested tool calls. Rejected calls count toward usage.
  `NULL` leaves the field unset.

- max_input_tokens:

  Maximum provider-reported input tokens. `NULL` leaves the field unset.

- max_output_tokens:

  Maximum provider-reported output tokens. `NULL` leaves the field
  unset.

- max_total_tokens:

  Maximum input plus output tokens. Cached input is reported separately
  and is not counted twice. `NULL` leaves the field unset.

- max_cost_usd:

  Maximum provider-reported estimated cost in US dollars. `NULL` leaves
  the field unset. If configured, missing provider cost data stops the
  run with `"cost_unavailable"` rather than undercounting.

- on_exceed:

  What to do when a limit is exceeded. `"stop"` returns an
  [AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
  with a typed stop reason; `"error"` emits the final usage event and
  then signals a structured Deputy limit error.

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
