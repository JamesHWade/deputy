# Code execution tools

Returns a list of tools for code execution:

- `run_r_code` - Execute R code (sandboxed by default)

- `run_bash` - Execute bash commands

**Note:** These tools require appropriate permissions. By default,
[`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md)
allows R code but not bash.

## Usage

``` r
tools_code()
```

## Value

A list of tool definitions

## See also

[tool_run_r_code](https://jameshwade.github.io/deputy/reference/tool_run_r_code.md),
[tool_run_bash](https://jameshwade.github.io/deputy/reference/tool_run_bash.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = tools_code()
)
} # }
```
