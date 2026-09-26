# Get the data reading tools

Returns `read_csv`, `read_file` and `read_markdown`.

## Usage

``` r
tools_data()
```

## Value

A list of tools.

## See also

[tool_read_csv](https://jameshwade.github.io/deputy/reference/tool_read_csv.md),
[tool_read_file](https://jameshwade.github.io/deputy/reference/tool_read_file.md),
[tool_read_markdown](https://jameshwade.github.io/deputy/reference/tool_read_markdown.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = tools_data()
)
} # }
```
