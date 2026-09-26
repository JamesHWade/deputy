# Create a read-only permission policy

Creates a `"readonly"` policy. The agent can use the built-in
file-reading tools such as `read_file`, `list_files` and `grep_files`,
and a
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
can delegate to subagents, which are read-only too. Writes, code
execution, web access and custom tools are denied.

## Usage

``` r
permissions_readonly()
```

## Value

A
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
object.

## Examples

``` r
perms <- permissions_readonly()
permissions_check(perms, "read_file", list(path = "test.txt"))
#> <deputy::PermissionResultAllow>
#>  @ decision: chr "allow"
#>  @ message : NULL
```
