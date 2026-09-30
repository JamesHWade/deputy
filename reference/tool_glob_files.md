# Find files using a glob pattern

A tool that finds files and directories matching a glob pattern such as
`"*.R"` or `"R/*.R"`. `*` and `?` don't match `/`; `**` matches across
directories.

## Usage

``` r
tool_glob_files(pattern = "*", path = ".", recursive = TRUE)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- pattern:

  Glob pattern to match.

- path:

  Directory to search. Defaults to the working directory.

- recursive:

  If `TRUE` (the default), search subdirectories.

## Value

A text listing of matching paths, relative to `path`.

## Examples

``` r
directory <- tempfile()
dir.create(directory)
writeLines("example", file.path(directory, "example.txt"))
tool_glob_files("*.txt", directory)
#> [1] "Base path: /tmp/RtmpuVp1hk/file1b0434791dc3\nMatches: 1\n\nexample.txt"
unlink(directory, recursive = TRUE)
```
