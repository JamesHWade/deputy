# Execute bash commands

A tool that runs a shell command and returns its output. The model can
run any command your user account can, and nothing is sandboxed.
Commands time out after 30 seconds. The default permissions deny this
tool; allow it with `bash = TRUE` in
[`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md).

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
