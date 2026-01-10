# Abort with a session save error

Signals that saving a session file failed.

## Usage

``` r
abort_session_save(
  message,
  path = NULL,
  parent = NULL,
  ...,
  .envir = parent.frame()
)
```

## Arguments

- message:

  The error message (supports cli formatting)

- path:

  Path where the session was being saved

- parent:

  The parent error that caused the failure (optional)

- ...:

  Additional context fields

- .envir:

  Environment for cli interpolation

## Examples

``` r
if (FALSE) { # \dontrun{
abort_session_save(
  "Cannot write to {.path {path}}",
  path = "/readonly/path/session.rds"
)
} # }
```
