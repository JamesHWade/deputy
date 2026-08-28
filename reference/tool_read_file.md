# Read file contents

A tool that reads the contents of a file and returns it as a string.

## Usage

``` r
tool_read_file(path, pages = NULL)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the file to read (tool argument, not R function argument)

- pages:

  Optional PDF page selection. Accepts comma-separated pages and ranges
  (e.g. `"1,3-5"`). Only supported for PDF files.

## Value

When called directly, a character string with the file contents, or a
structured list when selected PDF pages are requested.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = list(tool_read_file)
)
} # }
```
