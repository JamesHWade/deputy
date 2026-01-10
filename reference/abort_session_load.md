# Abort with a session load error

Signals that loading a session file failed.

## Usage

``` r
abort_session_load(
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

  Path to the session file

- parent:

  The parent error that caused the failure (optional)

- ...:

  Additional context fields

- .envir:

  Environment for cli interpolation

## Examples

``` r
if (FALSE) { # \dontrun{
abort_session_load(
  c("Failed to load session", "x" = "File corrupted"),
  path = "agent_session.rds"
)
} # }
```
