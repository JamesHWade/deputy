# Check a tool call against a permission policy

Returns the policy's decision for one tool call. It calls the policy's
`can_use_tool` callback if the rest of the policy allows the call, but
runs no hooks. Use it to test a policy.

## Usage

``` r
permissions_check(permissions, tool_name, tool_input, context = list())
```

## Arguments

- permissions:

  A
  [Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
  object.

- tool_name:

  Name of the tool.

- tool_input:

  Named list of arguments for the tool.

- context:

  Optional named list of details the agent normally supplies, such as
  `working_dir` (used to resolve relative paths) and `tool_annotations`.

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
