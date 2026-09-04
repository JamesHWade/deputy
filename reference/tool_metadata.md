# Inspect a tool's origin and annotation coverage

Returns metadata for the executable source of an ellmer tool, including
tools wrapped by an Agent or copied into a delegated Agent. This does
not call the tool, connect a server, or authorize execution.

## Usage

``` r
tool_metadata(tool)
```

## Arguments

- tool:

  An ellmer function tool or supported provider-native tool.

## Value

A list with `name`, `source`, supplied `annotations`,
`missing_annotations`, and `effective_annotations`. Source types are
`"function"`, `"package"` (with package name), `"provider"`, or `"mcp"`
(with exact server and tool names). Unknown origins are not guessed from
tool names. Effective annotations describe the conservative defaults;
permission modes, capabilities, lists, and callbacks still decide
access.

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
