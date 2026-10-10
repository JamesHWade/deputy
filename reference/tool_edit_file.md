# Edit file contents by replacing text

A tool that replaces exact text in an existing file. Unless
`replace_all` is `TRUE`, `old_text` must appear exactly once. Line
endings and the rest of the file are left as they were.

## Usage

``` r
tool_edit_file(path, old_text, new_text, replace_all = FALSE)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the file to edit.

- old_text:

  Text to replace.

- new_text:

  Replacement text.

- replace_all:

  If `TRUE`, replace every occurrence of `old_text`.

## Value

A status message with the number of replacements.

## Examples

``` r
path <- tempfile(fileext = ".txt")
writeLines("alpha", path)
tool_edit_file(path, "alpha", "beta")
#> [1] "Successfully edited /tmp/RtmpQtZYWH/file1a622e2431c1.txt (1 replacement)"
unlink(path)
```
