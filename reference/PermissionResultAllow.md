# Create an allow permission result

Return this from a `can_use_tool` callback or a PermissionRequest hook
to allow a tool call.

## Usage

``` r
PermissionResultAllow(message = NULL)
```

## Arguments

- message:

  Optional note stored on the result. Deputy doesn't show it to the
  model or the user.

## Value

A `PermissionResultAllow` object.

## See also

[CallbackResult](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
for reading result fields.

## Examples

``` r
# Allow a tool call
PermissionResultAllow()
#> <deputy::PermissionResultAllow>
#>  @ decision: chr "allow"
#>  @ message : NULL

# Allow with a message
PermissionResultAllow(message = "Tool approved by custom callback")
#> <deputy::PermissionResultAllow>
#>  @ decision: chr "allow"
#>  @ message : chr "Tool approved by custom callback"
```
