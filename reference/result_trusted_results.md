# Inspect trusted results

Inspect trusted results

## Usage

``` r
result_trusted_results(result, type = NULL)
```

## Arguments

- result:

  An
  [AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
  S7 value.

- type:

  Optional result type to select.

## Value

List of `"trusted_result"` events. Each contains `result_id`,
`result_type`, `tool_name`, `tool_call_id`, `arguments`, and the tool's
verbatim `value`, plus run correlation fields.

## See also

[TrustedResults](https://jameshwade.github.io/deputy/reference/TrustedResults.md)
