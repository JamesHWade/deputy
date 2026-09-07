# Create a PreToolUse hook result

Return this from a PreToolUse hook callback to control tool execution.

## Usage

``` r
HookResultPreToolUse(
  permission = c("allow", "deny"),
  reason = NULL,
  continue = TRUE,
  additional_context = NULL,
  stop_reason = NULL
)
```

## Arguments

- permission:

  Either `"allow"` or `"deny"`

- reason:

  Reason for denial (shown to the LLM)

- continue:

  One non-missing logical value. If FALSE, stop the agent after this
  hook

- additional_context:

  Optional text to append to the running context

- stop_reason:

  Optional stop reason used when `continue = FALSE`

## Value

A `HookResultPreToolUse` S7 object

## See also

[CallbackResult](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
for read-only properties and S7 inspection.

## Examples

``` r
# Allow a tool call
HookResultPreToolUse(permission = "allow")
#> <deputy::HookResultPreToolUse>
#>  @ permission        : chr "allow"
#>  @ reason            : NULL
#>  @ continue          : logi TRUE
#>  @ additional_context: NULL
#>  @ stop_reason       : NULL

# Deny a dangerous command
HookResultPreToolUse(
  permission = "deny",
  reason = "Dangerous command pattern detected"
)
#> <deputy::HookResultPreToolUse>
#>  @ permission        : chr "deny"
#>  @ reason            : chr "Dangerous command pattern detected"
#>  @ continue          : logi TRUE
#>  @ additional_context: NULL
#>  @ stop_reason       : NULL
```
