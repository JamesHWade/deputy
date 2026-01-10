# Create a hook that logs all tool calls

Convenience function to create a PostToolUse hook that logs tool calls
using the cli package.

## Usage

``` r
hook_log_tools(verbose = FALSE)
```

## Arguments

- verbose:

  If TRUE, include tool result in log

## Value

A
[HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
object

## Examples

``` r
if (FALSE) { # \dontrun{
agent$add_hook(hook_log_tools())
} # }
```
