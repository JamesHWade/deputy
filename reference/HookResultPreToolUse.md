# Create a PreToolUse hook result

Return this from a PreToolUse hook callback to control tool execution.

## Usage

``` r
HookResultPreToolUse(
  permission = c("allow", "deny"),
  reason = NULL,
  continue = TRUE
)
```

## Arguments

- permission:

  Either `"allow"` or `"deny"`

- reason:

  Reason for denial (shown to the LLM)

- continue:

  If FALSE, stop the agent after this hook

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
#> attr(,"class")
#> [1] "HookResultPreToolUse" "HookResult"           "list"                
```
