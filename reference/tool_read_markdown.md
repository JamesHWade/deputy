# Convert a file to Markdown using MarkItDown

A tool that converts a local document, such as DOCX, PPTX, PDF or HTML,
to Markdown with the Python library
[MarkItDown](https://github.com/microsoft/markitdown).

## Usage

``` r
tool_read_markdown(path)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the file to convert.

## Value

The Markdown text as one string.

## Details

Needs the reticulate package and the Python module `markitdown`
(`pip install 'markitdown[all]'`).

## Examples

``` r
if (FALSE) { # \dontrun{
tool_read_markdown("report.pdf")
} # }
```
