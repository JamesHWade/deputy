# Read file contents

A tool that reads a file and returns its contents as text. Reading PDFs
needs the pdftools package (or the Python module pypdf through
reticulate).

## Usage

``` r
tool_read_file(path, pages = NULL)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the file to read.

- pages:

  Optional PDF page selection, such as `"1,3-5"`. Only valid for PDF
  files.

## Value

The file contents as one string. When `pages` is given, a list with the
page count and the text of each selected page.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = list(tool_read_file)
)
} # }
```
