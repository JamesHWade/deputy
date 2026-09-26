# Inspect a tool's origin and annotations

Reports where a tool comes from and which annotations it declares. It
works on tools as you created them and on the wrapped copies an agent or
subagent holds. The tool is not called.

## Usage

``` r
tool_metadata(tool)
```

## Arguments

- tool:

  An ellmer tool, or a provider's built-in tool.

## Value

A list with `name`, `source`, `annotations` (as declared),
`missing_annotations`, and `effective_annotations` (the declared values,
with cautious defaults filling the gaps). `source$type` is `"function"`,
`"package"` (with `package`), `"provider"`, or `"mcp"` (with `server`
and `tool`). Whether a call is allowed still depends on the agent's
permissions.

## See also

[PermissionMode](https://jameshwade.github.io/deputy/reference/PermissionMode.md),
[tools_mcp](https://jameshwade.github.io/deputy/reference/tools_mcp.md),
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md)

## Examples

``` r
tool_metadata(tool_read_file)
#> $name
#> [1] "read_file"
#> 
#> $source
#> $source$type
#> [1] "package"
#> 
#> $source$package
#>     name 
#> "deputy" 
#> 
#> 
#> $annotations
#> $annotations$read_only_hint
#> [1] TRUE
#> 
#> $annotations$destructive_hint
#> [1] FALSE
#> 
#> 
#> $missing_annotations
#> [1] "idempotent_hint" "open_world_hint"
#> 
#> $effective_annotations
#> $effective_annotations$read_only_hint
#> [1] TRUE
#> 
#> $effective_annotations$destructive_hint
#> [1] FALSE
#> 
#> $effective_annotations$idempotent_hint
#> [1] FALSE
#> 
#> $effective_annotations$open_world_hint
#> [1] TRUE
#> 
#> 
```
