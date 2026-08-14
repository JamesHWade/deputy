# Create a PreToolUse hook result

Return this from a PreToolUse hook callback to control tool execution.

## Usage

``` r
HookResultPreToolUse(
  permission = c("allow", "deny"),
  reason = NULL,
  continue = TRUE,
  updated_input = NULL,
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

  If FALSE, stop the agent after this hook

- updated_input:

  Reserved for SDK-shape parity. **Not currently supported**: deputy
  emits a warning and proceeds with the original tool input. ellmer's
  tool-request callback contract does not yet expose a way to mutate the
  in-flight request, so use `permission = "deny"` to block a tool call
  instead of rewriting its arguments.

- additional_context:

  Optional text to append to the running context

- stop_reason:

  Optional stop reason used when `continue = FALSE`

## Value

A `HookResultPreToolUse` object

## Examples

``` r
# Allow a tool call
HookResultPreToolUse(permission = "allow")
#> $permission
#> [1] "allow"
#> 
#> $reason
#> NULL
#> 
#> $continue
#> [1] TRUE
#> 
#> $updated_input
#> NULL
#> 
#> $additional_context
#> NULL
#> 
#> $stop_reason
#> NULL
#> 
#> attr(,"class")
#> [1] "HookResultPreToolUse" "HookResult"           "list"                

# Deny a dangerous command
HookResultPreToolUse(
  permission = "deny",
  reason = "Dangerous command pattern detected"
)
#> $permission
#> [1] "deny"
#> 
#> $reason
#> [1] "Dangerous command pattern detected"
#> 
#> $continue
#> [1] TRUE
#> 
#> $updated_input
#> NULL
#> 
#> $additional_context
#> NULL
#> 
#> $stop_reason
#> NULL
#> 
#> attr(,"class")
#> [1] "HookResultPreToolUse" "HookResult"           "list"                
```
