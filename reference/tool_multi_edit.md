# Apply multiple text edits to a file

Apply a sequence of exact-match text replacements to a file.

## Usage

``` r
tool_multi_edit(path, edits)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the file to edit (tool argument)

- edits:

  List or JSON string of edit operations (tool argument)
