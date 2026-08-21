# Create a read-only permission policy

Creates a permission policy that only allows reading files. All write
operations, code execution, and web access are denied.

## Usage

``` r
permissions_readonly()
```

## Value

A
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
object

## Examples

``` r
perms <- permissions_readonly()
perms$check("read_file", list(path = "test.txt"))
#> $decision
#> [1] "allow"
#> 
#> $message
#> NULL
#> 
#> attr(,"class")
#> [1] "PermissionResultAllow" "PermissionResult"      "list"                 
```
