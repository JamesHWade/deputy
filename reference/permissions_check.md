# Evaluate a tool call against a permission policy

Evaluate a tool call against a permission policy

## Usage

``` r
permissions_check(permissions, tool_name, tool_input, context = list())
```

## Arguments

- permissions:

  A
  [Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
  S7 value.

- tool_name:

  Name of the tool.

- tool_input:

  Arguments passed to the tool.

- context:

  Additional context such as working directory, tool origin, and
  annotations.

## Value

A
[PermissionResultAllow](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md),
[PermissionResultDeny](https://jameshwade.github.io/deputy/reference/PermissionResultDeny.md),
or
[PermissionResultPending](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md).

## Examples

``` r
permissions_check(permissions_readonly(), "read_file", list(path = "x.txt"))
#> <deputy::PermissionResultAllow>
#>  @ decision: chr "allow"
#>  @ message : NULL
```
