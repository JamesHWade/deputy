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
