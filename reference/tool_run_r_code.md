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

The process doesn't inherit your environment variables, and R there
doesn't read `.Renviron`; a project `.Rprofile` still runs. It gets the
variables that locate programs, libraries, locales and temporary files.
To pass others, use
[`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md)
with `env`. This keeps keys out of what the code is given, not out of
its reach: code running as your user account can still read your R
session's starting environment through the operating system, and any
file your account can read, `.Renviron` included. To keep keys from the
code, run it under an account that can't read them, or in a sandbox.

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
