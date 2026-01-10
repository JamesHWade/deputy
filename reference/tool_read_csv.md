# Read a CSV file

A tool that reads a CSV file and returns a summary of its structure
along with the first few rows.

## Usage

``` r
tool_read_csv(path, n_max = 1000, show_head = 10)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the CSV file to read (tool argument)

- n_max:

  Maximum number of rows to read (tool argument)

- show_head:

  Number of rows to show in preview (tool argument)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = list(tool_read_csv)
)
} # }
```
