# Get the trusted results from a run

Get the trusted results from a run

## Usage

``` r
result_trusted_results(result, type = NULL)
```

## Arguments

- result:

  An
  [AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).

- type:

  Optional result type. `NULL` returns results of every type.

## Value

A list of `"trusted_result"`
[AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)s.
Each has `result_id`, `result_type`, `tool_name`, `tool_fingerprint` (a
SHA-256 digest of the producing tool's code, argument schema and
metadata: the same for every call, whatever its inputs), `tool_call_id`,
`arguments`, the tool's unchanged `value`, and the IDs of the run and
agent that produced it.

## See also

[TrustedResults](https://jameshwade.github.io/deputy/reference/TrustedResults.md)
