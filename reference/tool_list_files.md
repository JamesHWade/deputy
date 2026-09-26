# List files in a directory

A tool that lists the files and directories in a directory, with sizes.

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

  Directory to list. Defaults to the working directory.

- pattern:

  Optional regular expression to filter file names.

- recursive:

  If `TRUE`, include subdirectories.

- full_names:

  If `TRUE`, show full paths.

## Value

A text listing of names and sizes.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = list(tool_list_files)
)
} # }
```
