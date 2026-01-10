# Abort with a budget exceeded error

Signals that the agent exceeded its cost budget.

## Usage

``` r
abort_budget_exceeded(
  message,
  current_cost = NULL,
  max_cost = NULL,
  ...,
  .envir = parent.frame()
)
```

## Arguments

- message:

  The error message (supports cli formatting)

- current_cost:

  The current accumulated cost

- max_cost:

  The maximum allowed cost

- ...:

  Additional context fields

- .envir:

  Environment for cli interpolation

## Examples

``` r
if (FALSE) { # \dontrun{
abort_budget_exceeded(
  "Cost limit exceeded: ${current_cost} > ${max_cost}",
  current_cost = 0.55,
  max_cost = 0.50
)
} # }
```
