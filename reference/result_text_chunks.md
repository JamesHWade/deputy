# Inspect streamed text

Inspect streamed text

## Usage

``` r
result_text_chunks(result)
```

## Arguments

- result:

  An
  [AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
  S7 value.

## Value

Character vector of text chunks; empty when none were emitted. Missing
and non-character text payloads are ignored. Character-vector payloads
are flattened in event order.
