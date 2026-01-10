# Execute R code

A tool that executes R code and returns the result. By default, runs in
a separate process for safety (requires the callr package).

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

## Details

This tool intentionally uses R's code evaluation capabilities to execute
arbitrary R code provided by the LLM. This is a core feature for agentic
workflows where the agent needs to perform data analysis or other R
tasks.

For safety:

- By default, code runs in a sandboxed subprocess via callr

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
