# Web tools

Returns a list of tools for web operations:

- `web_fetch` - Fetch web page content

- `web_search` - Search the web

**Note:** These tools require the `web` permission to be enabled and the
httr2 package to be installed.

## Usage

``` r
tools_web()
```

## Value

A list of tool definitions

## See also

[tool_web_fetch](https://jameshwade.github.io/deputy/reference/tool_web_fetch.md),
[tool_web_search](https://jameshwade.github.io/deputy/reference/tool_web_search.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = tools_web(),
  permissions = Permissions$new(web = TRUE)
)
} # }
```
