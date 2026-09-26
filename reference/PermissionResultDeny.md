# Create a deny permission result

Return this from a `can_use_tool` callback or a PermissionRequest hook
to deny a tool call.

## Usage

``` r
PermissionResultDeny(reason, interrupt = FALSE)
```

## Arguments

- reason:

  Why the call was denied. The model sees it.

- interrupt:

  `TRUE` or `FALSE`. `TRUE` also stops the run, with stop reason
  `"permission_denied"`.

## Value

A `PermissionResultDeny` object.

## See also

[CallbackResult](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
for reading result fields.

## Examples

``` r
# Deny a tool call
PermissionResultDeny(reason = "File write not allowed")
#> <deputy::PermissionResultDeny>
#>  @ decision : chr "deny"
#>  @ reason   : chr "File write not allowed"
#>  @ interrupt: logi FALSE

# Deny and stop the run
PermissionResultDeny(reason = "Critical security violation", interrupt = TRUE)
#> <deputy::PermissionResultDeny>
#>  @ decision : chr "deny"
#>  @ reason   : chr "Critical security violation"
#>  @ interrupt: logi TRUE
```
