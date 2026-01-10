# Read file contents

A tool that reads the contents of a file and returns it as a string.

## Usage

``` r
tool_read_file(path)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the file to read (tool argument, not R function argument)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = list(tool_read_file)
)
} # }
```
