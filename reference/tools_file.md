# File operation tools

Returns a list of tools for file operations:

- `read_file` - Read file contents

- `write_file` - Write content to files

- `list_files` - List directory contents

## Usage

``` r
tools_file()
```

## Value

A list of tool definitions

## See also

[tool_read_file](https://jameshwade.github.io/deputy/reference/tool_read_file.md),
[tool_write_file](https://jameshwade.github.io/deputy/reference/tool_write_file.md),
[tool_list_files](https://jameshwade.github.io/deputy/reference/tool_list_files.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = tools_file()
)
} # }
```
