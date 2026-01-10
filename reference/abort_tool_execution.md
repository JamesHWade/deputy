# Abort with a tool execution error

Signals that a tool failed during execution.

## Usage

``` r
abort_tool_execution(
  message,
  tool_name,
  tool_input = NULL,
  parent = NULL,
  ...,
  .envir = parent.frame()
)
```

## Arguments

- message:

  The error message (supports cli formatting)

- tool_name:

  Name of the tool that failed

- tool_input:

  The input that was passed to the tool (optional)

- parent:

  The parent error that caused the failure (optional)

- ...:

  Additional context fields

- .envir:

  Environment for cli interpolation

## Examples

``` r
if (FALSE) { # \dontrun{
abort_tool_execution(
  c("Tool {.fn {tool_name}} failed", "x" = "File not found"),
  tool_name = "read_file",
  tool_input = list(path = "/nonexistent/file.txt")
)
} # }
```
