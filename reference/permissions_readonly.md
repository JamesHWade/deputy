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
permissions_check(perms, "read_file", list(path = "test.txt"))
#> <deputy::PermissionResultAllow>
#>  @ decision: chr "allow"
#>  @ message : NULL
```
