# Abort with a hook error

Signals that a hook callback failed during execution.

## Usage

``` r
abort_hook(
  message,
  hook_event = NULL,
  parent = NULL,
  ...,
  .envir = parent.frame()
)
```

## Arguments

- message:

  The error message (supports cli formatting)

- hook_event:

  The hook event type (e.g., "PreToolUse", "PostToolUse")

- parent:

  The parent error from the hook callback (optional)

- ...:

  Additional context fields

- .envir:

  Environment for cli interpolation

## Examples

``` r
if (FALSE) { # \dontrun{
abort_hook(
  c("Hook {.val {hook_event}} failed", "x" = "Callback error"),
  hook_event = "PreToolUse"
)
} # }
```
