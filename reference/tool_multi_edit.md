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

## Value

When called directly, a character status message describing the edits
and total replacement count.

## Examples

``` r
path <- tempfile(fileext = ".txt")
writeLines(c("alpha", "beta"), path)
tool_multi_edit(
  path,
  list(list(old_text = "alpha", new_text = "gamma"))
)
#> [1] "Successfully applied 1 edit(s) to /tmp/RtmpJa6vmy/file1b6240e4b534.txt (1 total replacement)"
unlink(path)
```
