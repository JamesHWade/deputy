# Create a deny permission result

Returns a permission result that denies the tool from executing.

## Usage

``` r
PermissionResultDeny(reason, interrupt = FALSE)
```

## Arguments

- reason:

  Reason for denial (shown to the LLM)

- interrupt:

  If TRUE, stop the entire conversation (default FALSE)

## Value

A `PermissionResultDeny` object

## Examples

``` r
# Deny a tool call
PermissionResultDeny(reason = "File write not allowed")
#> $decision
#> [1] "deny"
#> 
#> $reason
#> [1] "File write not allowed"
#> 
#> $interrupt
#> [1] FALSE
#> 
#> attr(,"class")
#> [1] "PermissionResultDeny" "PermissionResult"     "list"                

# Deny and interrupt the conversation
PermissionResultDeny(reason = "Critical security violation", interrupt = TRUE)
#> $decision
#> [1] "deny"
#> 
#> $reason
#> [1] "Critical security violation"
#> 
#> $interrupt
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "PermissionResultDeny" "PermissionResult"     "list"                
```
