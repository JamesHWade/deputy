# Create an allow permission result

Returns a permission result that allows the tool to execute.

## Usage

``` r
PermissionResultAllow(message = NULL)
```

## Arguments

- message:

  Optional message to display

## Value

A `PermissionResultAllow` S7 object

## See also

[CallbackResult](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
for read-only properties and S7 inspection.

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
