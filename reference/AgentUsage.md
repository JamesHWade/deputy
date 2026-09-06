# Create an agent usage record

`AgentUsage()` creates a normalized usage record. `AgentResult$usage`
and run `usage`/`stop` events are scoped to that run, while
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md)`$usage()`
describes the complete in-memory conversation at the time it is called.

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

  Number of model requests attributed to the run.

- tool_calls:

  Number of requested tool calls, including calls rejected before
  execution.

- input_tokens:

  Provider-reported input tokens.

- output_tokens:

  Provider-reported output tokens.

- cached_tokens:

  Provider-reported cached input tokens. These are reported separately
  and are not added again to `total_tokens`.

- cost_usd:

  Provider-reported estimated cost in US dollars, or `NA_real_` when the
  provider did not report complete cost information.

## Value

An `AgentUsage` object.

## Examples

``` r
AgentUsage(
  requests = 2,
  tool_calls = 1,
  input_tokens = 120,
  output_tokens = 30,
  cost_usd = 0.002
)
#> $requests
#> [1] 2
#> 
#> $tool_calls
#> [1] 1
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
#> [1] 0.002
#> 
#> attr(,"class")
#> [1] "AgentUsage" "list"      
```
