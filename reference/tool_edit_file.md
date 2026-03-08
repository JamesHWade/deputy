# Edit file contents by replacing text

Replace a specific text span in an existing file.

## Usage

``` r
tool_edit_file(path, old_text, new_text, replace_all = FALSE)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- path:

  Path to the file to edit (tool argument)

- old_text:

  Existing text to replace (tool argument)

- new_text:

  Replacement text (tool argument)

- replace_all:

  If TRUE, replace all matches instead of requiring a unique match (tool
  argument)
