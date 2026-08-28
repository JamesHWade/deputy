# Execute R code

A tool that executes R code and returns the result. It runs in a
separate process for fault isolation and timeout enforcement (requires
callr).

## Usage

``` r
tool_run_r_code(code)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- code:

  R code to execute (tool argument)

## Value

When called directly, a character string containing captured output and
the returned value.

## Details

This tool intentionally uses R's code evaluation capabilities to execute
arbitrary R code provided by the LLM. This is a core feature for agentic
workflows where the agent needs to perform data analysis or other R
tasks.

The execution boundary is explicit:

- Code runs in a separate callr subprocess, not an OS security sandbox

- A timeout prevents runaway execution

- The Permissions system can disable this tool entirely

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = list(tool_run_r_code)
)
} # }
```
