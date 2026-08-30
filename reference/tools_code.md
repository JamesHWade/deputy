# Code execution tools

Returns a list of tools for code execution:

- `run_r_code` - Execute R code in a separate process

- `run_bash` - Execute bash commands

**Note:** These tools execute trusted code and require explicit
permissions. Process separation is not an OS sandbox;
[`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md)
denies both tools.

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
