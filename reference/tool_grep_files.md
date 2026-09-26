# Search file contents with grep-like matching

A tool that searches the lines of files under a directory with a
Perl-compatible regular expression.

## Usage

``` r
tool_grep_files(
  pattern,
  path = ".",
  recursive = TRUE,
  ignore_case = FALSE,
  max_matches = 100
)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- pattern:

  Regular expression to search for.

- path:

  Directory to search. Defaults to the working directory.

- recursive:

  If `TRUE` (the default), search subdirectories.

- ignore_case:

  If `TRUE`, ignore case.

- max_matches:

  Maximum number of matching lines to return. Defaults to 100.

## Value

Matching lines formatted as `file:line: text`.

## Examples

``` r
directory <- tempfile()
dir.create(directory)
writeLines("needle", file.path(directory, "example.txt"))
tool_grep_files("needle", directory)
#> [1] "Pattern: needle\nMatches: 1\n\nexample.txt:1: needle"
unlink(directory, recursive = TRUE)
```
