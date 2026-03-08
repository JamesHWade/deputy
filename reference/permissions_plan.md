# Create a planning permission policy

Creates a permission policy for planning-oriented sessions. Only tools
annotated as read-only are allowed, plus the permission prompt tool when
configured.

## Usage

``` r
permissions_plan(
  max_turns = 25,
  max_cost_usd = NULL,
  permission_prompt_tool_name = "AskUserQuestion"
)
```

## Arguments

- max_turns:

  Maximum number of turns (default 25)

- max_cost_usd:

  Maximum cost in USD (default NULL = unlimited)

- permission_prompt_tool_name:

  Optional tool name that the model can use to request explicit
  approval. Defaults to `"AskUserQuestion"`.

## Value

A
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
object

## Examples

``` r
perms <- permissions_plan()
```
