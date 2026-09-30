# Get the code execution tools

Returns `run_r_code` and `run_bash`. Both run model-written code with
your user account's access. Each call runs in a separate process, which
is not a sandbox.
[`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md)
denies both tools; allow them with `r_code = TRUE` and `bash = TRUE` in
[`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md).
For an OS sandbox, use
[`tools_mcp_repl()`](https://jameshwade.github.io/deputy/reference/tools_mcp_repl.md).

The processes don't inherit your environment variables, and R there
doesn't read `.Renviron`. They get the variables that locate programs,
libraries, locales and temporary files, such as `PATH`, `HOME`, `LANG`
and `TMPDIR`, plus the ones you name in `env`. This keeps keys out of
what the code is given, not out of its reach: code running as your user
account can still read your R session's starting environment through the
operating system, and any file your account can read, `.Renviron`
included. To keep keys from the code, run it under an account that can't
read them, or in a sandbox.

## Usage

``` r
tools_code(env = NULL)
```

## Arguments

- env:

  The names of other environment variables the code may read, such as
  `c("HTTPS_PROXY", "NO_PROXY")` behind a proxy. Proxy settings match in
  either case, so `"HTTPS_PROXY"` passes `https_proxy` too. `"inherit"`
  passes your whole environment, including every key it holds.

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
