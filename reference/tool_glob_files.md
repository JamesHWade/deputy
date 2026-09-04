# Find files using a glob pattern

Search for files under a directory using shell-style glob matching.

## Usage

``` r
tool_glob_files(pattern = "*", path = ".", recursive = TRUE)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- pattern:

  Glob pattern to match (tool argument)

- path:

  Base directory to search (tool argument)

- recursive:

  If TRUE, search subdirectories recursively (tool argument)

## Value

When called directly, a character summary of paths matching the glob
pattern.

## Examples

``` r
directory <- tempfile()
dir.create(directory)
writeLines("example", file.path(directory, "example.txt"))
tool_glob_files("*.txt", directory)
#> [1] "Base path: /tmp/Rtmp9MNH2i/file1a472c07cd41\nMatches: 1\n\nexample.txt"
unlink(directory, recursive = TRUE)
```
