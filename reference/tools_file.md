# Get the basic file tools

Returns `read_file`, `read_markdown`, `write_file` and `list_files`. The
editing and search tools, such as
[tool_edit_file](https://jameshwade.github.io/deputy/reference/tool_edit_file.md)
and
[tool_grep_files](https://jameshwade.github.io/deputy/reference/tool_grep_files.md),
are separate.

## Usage

``` r
tools_file()
```

## Value

A list of tools.

## See also

[tool_read_file](https://jameshwade.github.io/deputy/reference/tool_read_file.md),
[tool_read_markdown](https://jameshwade.github.io/deputy/reference/tool_read_markdown.md),
[tool_write_file](https://jameshwade.github.io/deputy/reference/tool_write_file.md),
[tool_list_files](https://jameshwade.github.io/deputy/reference/tool_list_files.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = tools_file()
)
} # }
```
