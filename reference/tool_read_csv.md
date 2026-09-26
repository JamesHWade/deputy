# Read a CSV file

A tool that reads a CSV file and summarises it: row and column counts,
column types and the first few rows.

## Usage

``` r
tool_read_csv(path, n_max = 1000, show_head = 10)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the CSV file.

- n_max:

  Maximum number of rows to read. Defaults to 1000.

- show_head:

  Number of rows to show. Defaults to 10.

## Value

The summary as one string.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = list(tool_read_csv)
)
} # }
```
