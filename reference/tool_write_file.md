# Write content to a file

A tool that writes content to a file, creating it if it doesn't exist.

## Usage

``` r
tool_write_file(path, content, append = FALSE)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the file to write (tool argument)

- content:

  Content to write to the file (tool argument)

- append:

  If TRUE, append to existing file (tool argument)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = list(tool_write_file)
)
} # }
```
