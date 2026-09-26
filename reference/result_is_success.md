# Check whether a run completed

Check whether a run completed

## Usage

``` r
result_is_success(result)
```

## Arguments

- result:

  An
  [AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).

## Value

`TRUE` if the stop reason is `"complete"`, meaning the model finished on
its own. It doesn't check the answer.
