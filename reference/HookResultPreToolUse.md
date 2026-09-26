# Create a PreToolUse hook result

Return this from a PreToolUse hook to allow or deny a tool call. A hook
can only deny calls that the permission policy has already allowed.

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

  Either `"allow"` or `"deny"`.

- reason:

  Why the call was denied. The model sees it.

- continue:

  `TRUE` or `FALSE`. `FALSE` stops the run.

- additional_context:

  Optional text to add to the agent's system prompt. It stays there for
  later turns; the same text is only added once.

- stop_reason:

  Optional stop reason used when `continue = FALSE`. Defaults to
  `"hook_requested_stop"`.

## Value

A `HookResultPreToolUse` object.

## See also

[CallbackResult](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
for reading result fields.

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
