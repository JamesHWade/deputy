# Get the code execution tools

Returns `run_r_code` and `run_bash`. Both run model-written code with
your user account's access. Each call runs in a separate process, which
is not a sandbox.
[`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md)
denies both tools; allow them with `r_code = TRUE` and `bash = TRUE` in
[`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md).
For an OS sandbox, use
[`tools_mcp_repl()`](https://jameshwade.github.io/deputy/reference/tools_mcp_repl.md).

## Usage

``` r
tools_code()
```

## Value

A list of tools.

## See also

[tool_run_r_code](https://jameshwade.github.io/deputy/reference/tool_run_r_code.md),
[tool_run_bash](https://jameshwade.github.io/deputy/reference/tool_run_bash.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = tools_code(),
  permissions = Permissions(r_code = TRUE, bash = TRUE)
)
} # }
```
