# Execute R code

A tool that runs model-written R code and returns its printed output and
value. Each call starts a fresh R process, so nothing carries over
between calls; for a persistent session, use
[RSession](https://jameshwade.github.io/deputy/reference/RSession.md).
Calls time out after 30 seconds.

The code runs with your user account's access to files and the network.
The separate process protects your R session from crashes; it is not a
sandbox. The default permissions deny this tool; allow it with
`r_code = TRUE` in
[`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md).
For an OS sandbox, use
[`tools_mcp_repl()`](https://jameshwade.github.io/deputy/reference/tools_mcp_repl.md).

## Usage

``` r
tool_run_r_code(code)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- code:

  R code to run.

## Value

The captured output and the printed value as one string.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = list(tool_run_r_code),
  permissions = Permissions(r_code = TRUE)
)
} # }
```
