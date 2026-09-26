# Create a hook that logs tool calls

Creates a PostToolUse hook that prints a cli line after each tool call,
saying whether it succeeded or failed. It returns `NULL`, so hooks added
after it still run.

## Usage

``` r
hook_log_tools(verbose = FALSE)
```

## Arguments

- verbose:

  If `TRUE`, also print the first 100 characters of each successful
  result.

## Value

A
[HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md).

## Examples

``` r
if (FALSE) { # \dontrun{
agent$add_hook(hook_log_tools())
} # }
```
