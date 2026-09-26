# Create a PostToolUse hook result

Return this from a PostToolUse hook to stop the run or to change what
the agent's `tool_end` event reports. The model always sees the tool's
real result.

## Usage

``` r
HookResultPostToolUse(
  continue = TRUE,
  suppress_output = FALSE,
  updated_tool_output = NULL,
  additional_context = NULL,
  stop_reason = NULL
)
```

## Arguments

- continue:

  `TRUE` or `FALSE`. `FALSE` stops the run after this tool call.

- suppress_output:

  If `TRUE`, leave the result out of the `tool_end` event.

- updated_tool_output:

  Optional value to report in the `tool_end` event instead of the tool's
  result.

- additional_context:

  Optional text to add to the agent's system prompt. It stays there for
  later turns; the same text is only added once.

- stop_reason:

  Optional stop reason used when `continue = FALSE`. Defaults to
  `"hook_requested_stop"`.

## Value

A `HookResultPostToolUse` object.

## See also

[CallbackResult](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
for reading result fields.

## Examples

``` r
# Continue execution
HookResultPostToolUse()
#> <deputy::HookResultPostToolUse>
#>  @ continue           : logi TRUE
#>  @ suppress_output    : logi FALSE
#>  @ updated_tool_output: NULL
#>  @ additional_context : NULL
#>  @ stop_reason        : NULL

# Stop after this tool
HookResultPostToolUse(continue = FALSE)
#> <deputy::HookResultPostToolUse>
#>  @ continue           : logi FALSE
#>  @ suppress_output    : logi FALSE
#>  @ updated_tool_output: NULL
#>  @ additional_context : NULL
#>  @ stop_reason        : NULL
```
