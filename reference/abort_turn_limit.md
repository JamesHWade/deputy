# Abort with a turn limit error

Signals that the agent exceeded its maximum turn limit.

## Usage

``` r
abort_turn_limit(
  message,
  current_turns = NULL,
  max_turns = NULL,
  ...,
  .envir = parent.frame()
)
```

## Arguments

- message:

  The error message (supports cli formatting)

- current_turns:

  The number of turns executed

- max_turns:

  The maximum allowed turns

- ...:

  Additional context fields

- .envir:

  Environment for cli interpolation

## Examples

``` r
if (FALSE) { # \dontrun{
abort_turn_limit(
  "Maximum turns exceeded: {current_turns}/{max_turns}",
  current_turns = 25,
  max_turns = 25
)
} # }
```
