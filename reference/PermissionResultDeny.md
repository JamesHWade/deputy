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

  One non-missing logical value. If TRUE, stop the entire conversation
  (default FALSE)

## Value

A `PermissionResultDeny` S7 object

## See also

[CallbackResult](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
for read-only properties and S7 inspection.

## Examples

``` r
# Deny a tool call
PermissionResultDeny(reason = "File write not allowed")
#> <deputy::PermissionResultDeny>
#>  @ decision : chr "deny"
#>  @ reason   : chr "File write not allowed"
#>  @ interrupt: logi FALSE

# Deny and interrupt the conversation
PermissionResultDeny(reason = "Critical security violation", interrupt = TRUE)
#> <deputy::PermissionResultDeny>
#>  @ decision : chr "deny"
#>  @ reason   : chr "Critical security violation"
#>  @ interrupt: logi TRUE
```
