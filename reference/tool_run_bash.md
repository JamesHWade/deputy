# Execute bash commands

A tool that runs a shell command and returns its output. The model can
run any command your user account can, and nothing is sandboxed.
Commands time out after 30 seconds. The default permissions deny this
tool; allow it with `bash = TRUE` in
[`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md).

The command doesn't inherit your environment variables. It gets the
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
tool_run_bash(command)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- command:

  The shell command to run.

## Value

The command's output as one string, with standard error after a
`[stderr]` line. A command that exits with a non-zero status is reported
to the model as a failed tool call, with its status and output.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = list(tool_run_bash),
  permissions = Permissions(bash = TRUE)
)
} # }
```
