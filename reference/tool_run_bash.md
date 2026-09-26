# Execute bash commands

A tool that executes bash/shell commands and returns the output. **Use
with caution!** This can execute arbitrary system commands.

## Usage

``` r
tool_run_bash(command)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- command:

  The bash command to execute (tool argument)

## Value

When called directly, a character string containing command output
(standard error follows a `[stderr]` line) or a success message. A
command that exits with a non-zero status is rejected with its status
and output, so the model sees the step failed.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-5.6-luna"),
  tools = list(tool_run_bash),
  permissions = permissions_full()  # Required for bash
)
} # }
```
