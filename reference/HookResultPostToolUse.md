# Create a PostToolUse hook result

Return this from a PostToolUse hook callback.

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

  One non-missing logical value. If FALSE, stop the agent after this
  hook

- suppress_output:

  Coerced with [`isTRUE()`](https://rdrr.io/r/base/Logic.html). Whether
  to suppress the result on Deputy's emitted `tool_end` event. This does
  not remove the result from model context.

- updated_tool_output:

  Optional replacement value for Deputy's emitted `tool_end` event.
  ellmer does not support rewriting the model-visible in-flight result
  from this callback.

- additional_context:

  Optional text to append to the running context

- stop_reason:

  Optional stop reason used when `continue = FALSE`

## Value

A `HookResultPostToolUse` S7 object

## See also

[CallbackResult](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
for read-only properties and S7 inspection.

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
