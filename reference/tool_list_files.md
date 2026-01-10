# List files in a directory

A tool that lists files and directories within a specified path.

## Usage

``` r
tool_list_files(
  path = ".",
  pattern = NULL,
  recursive = FALSE,
  full_names = FALSE
)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Directory path to list (tool argument)

- pattern:

  Optional regex pattern to filter files (tool argument)

- recursive:

  If TRUE, list files recursively (tool argument)

- full_names:

  If TRUE, return full paths (tool argument)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = list(tool_list_files)
)
} # }
```
