# All built-in tools

Returns all built-in tools. Use with
[`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md)
if you want to allow all operations.

## Usage

``` r
tools_all()
```

## Value

A list of all tool definitions

## Examples

``` r
if (FALSE) { # \dontrun{
# Allow all tools with full permissions
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = tools_all(),
  permissions = permissions_full()
)
} # }
```
