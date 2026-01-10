# Data reading tools

Returns a list of tools for reading data files:

- `read_csv` - Read CSV files with summary

- `read_file` - Read any file as text

## Usage

``` r
tools_data()
```

## Value

A list of tool definitions

## See also

[tool_read_csv](https://jameshwade.github.io/deputy/reference/tool_read_csv.md),
[tool_read_file](https://jameshwade.github.io/deputy/reference/tool_read_file.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = tools_data()
)
} # }
```
