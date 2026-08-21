# Create a planning permission policy

Creates a permission policy for planning-oriented sessions. Only tools
annotated as read-only are allowed, plus the permission prompt tool when
configured.

## Usage

``` r
permissions_plan(permission_prompt_tool_name = "ask_user")
```

## Arguments

- permission_prompt_tool_name:

  Optional dedicated approval-tool name that the model can use to
  request explicit approval. Native capability-bearing tools are
  rejected. Defaults to `"ask_user"`.

## Value

A
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
object

## Examples

``` r
perms <- permissions_plan()
```
