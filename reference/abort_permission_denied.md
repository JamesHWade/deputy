# Abort with a permission denied error

Signals that an operation was denied by the permission system.

## Usage

``` r
abort_permission_denied(
  message,
  tool_name = NULL,
  permission_mode = NULL,
  reason = NULL,
  ...,
  .envir = parent.frame()
)
```

## Arguments

- message:

  The error message (supports cli formatting)

- tool_name:

  Name of the tool that was denied (optional)

- permission_mode:

  The current permission mode (optional)

- reason:

  Reason for denial (optional)

- ...:

  Additional context fields

- .envir:

  Environment for cli interpolation

## Examples

``` r
if (FALSE) { # \dontrun{
abort_permission_denied(
  "Write operations not allowed in {.val {mode}} mode",
  tool_name = "write_file",
  permission_mode = "readonly"
)
} # }
```
