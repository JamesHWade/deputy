# Search file contents with grep-like matching

Search text files under a directory and return matching lines.

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

  Regex pattern to search for (tool argument)

- path:

  Base directory to search (tool argument)

- recursive:

  If TRUE, search subdirectories recursively (tool argument)

- ignore_case:

  If TRUE, ignore case when matching (tool argument)

- max_matches:

  Maximum matching lines to return (tool argument)
