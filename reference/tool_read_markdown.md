# Convert a file to markdown using MarkItDown

Converts a local file to markdown text using Python
[MarkItDown](https://github.com/microsoft/markitdown) via `reticulate`.
This is useful for rich formats (e.g. DOCX, PPTX, PDF, HTML) when you
want a markdown representation instead of raw file text.

## Usage

``` r
tool_read_markdown(path)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the file to convert (tool argument, not R function argument)

## Details

Requires:

- R package `reticulate`

- Python module `markitdown` (e.g., `pip install 'markitdown[all]'`)

## Examples

``` r
if (FALSE) { # \dontrun{
tool_read_markdown("report.pdf")
} # }
```
