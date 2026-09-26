# Create a usage record

A usage record counts model requests, tool calls, tokens and estimated
cost.
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)`$usage`
and the `"usage"` and `"stop"` events cover a single run.
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md)`$usage()`
covers the whole conversation, including turns that compaction removed
from the model's context. You rarely need to call `AgentUsage()`
yourself.

Records are read-only. Read fields with `$`;
[`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
returns them all as a plain list, which is handy for logging.

## Usage

``` r
AgentUsage(
  requests = 0L,
  tool_calls = 0L,
  input_tokens = 0,
  output_tokens = 0,
  cached_tokens = 0,
  cost_usd = 0
)
```

## Arguments

- requests:

  Number of model requests.

- tool_calls:

  Number of tool calls requested, including denied calls.

- input_tokens:

  Input tokens reported by the provider.

- output_tokens:

  Output tokens reported by the provider.

- cached_tokens:

  Cached input tokens reported by the provider. They aren't added to
  `total_tokens`.

- cost_usd:

  Estimated cost in US dollars, or `NA_real_` if the cost of some
  responses is unknown.

## Value

An `AgentUsage` object.

## Additional properties

- `@total_tokens`:

  `input_tokens + output_tokens`.

## Examples

``` r
AgentUsage(
  requests = 2,
  tool_calls = 1,
  input_tokens = 120,
  output_tokens = 30,
  cost_usd = 0.002
)
#> <AgentUsage>
#>   requests: 2
#>   tool_calls: 1
#>   tokens: 150
#>   cached_tokens: 0
#>   cost_usd: $0.0020
usage <- AgentUsage(input_tokens = 120, output_tokens = 30, cost_usd = NA_real_)
usage$total_tokens
#> [1] 150
S7::props(usage)
#> $requests
#> [1] 0
#> 
#> $tool_calls
#> [1] 0
#> 
#> $input_tokens
#> [1] 120
#> 
#> $output_tokens
#> [1] 30
#> 
#> $cached_tokens
#> [1] 0
#> 
#> $total_tokens
#> [1] 150
#> 
#> $cost_usd
#> [1] NA
#> 
```
