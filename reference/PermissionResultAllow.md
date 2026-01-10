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

A `PermissionResultAllow` object

## Examples

``` r
# Allow a tool call
PermissionResultAllow()
#> $decision
#> [1] "allow"
#> 
#> $message
#> NULL
#> 
#> attr(,"class")
#> [1] "PermissionResultAllow" "PermissionResult"      "list"                 

# Allow with a message
PermissionResultAllow(message = "Tool approved by custom callback")
#> $decision
#> [1] "allow"
#> 
#> $message
#> [1] "Tool approved by custom callback"
#> 
#> attr(,"class")
#> [1] "PermissionResultAllow" "PermissionResult"      "list"                 
```
