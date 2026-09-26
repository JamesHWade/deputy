# Write content to a file

A tool that writes text to a file, creating the file and any missing
parent directories.

## Usage

``` r
tool_write_file(path, content, append = FALSE)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the file to write.

- content:

  Text to write.

- append:

  If `TRUE`, add to the end of the file instead of overwriting it.

## Value

A status message with the number of characters written.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = list(tool_write_file)
)
} # }
```
