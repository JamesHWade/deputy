# Apply multiple text edits to a file

A tool that applies several exact-text replacements to one file, in
order. Each edit follows the rules of
[tool_edit_file](https://jameshwade.github.io/deputy/reference/tool_edit_file.md).
If any edit fails, the file is left unchanged.

## Usage

``` r
tool_multi_edit(path, edits)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the file to edit.

- edits:

  A list of edits, or a JSON array. Each edit has `old_text`, `new_text`
  and, optionally, `replace_all`.

## Value

A status message with the number of edits and replacements.

## Examples

``` r
path <- tempfile(fileext = ".txt")
writeLines(c("alpha", "beta"), path)
tool_multi_edit(
  path,
  list(list(old_text = "alpha", new_text = "gamma"))
)
#> [1] "Successfully applied 1 edit(s) to /tmp/RtmpNLIVP4/file19802f205d95.txt (1 total replacement)"
unlink(path)
```
