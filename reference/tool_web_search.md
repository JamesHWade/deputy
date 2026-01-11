# Search the web

A tool that performs a web search and returns results. Uses DuckDuckGo's
HTML search results by default.

## Usage

``` r
tool_web_search(query, num_results = 10)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- query:

  The search query (tool argument)

- num_results:

  Maximum number of results to return (tool argument)

## Details

This tool searches the web using DuckDuckGo and returns a list of
results with titles, URLs, and snippets. For more sophisticated search
needs, consider using a dedicated search API.

## See also

[`tools_web()`](https://jameshwade.github.io/deputy/reference/tools_web.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = list(tool_web_search),
  permissions = Permissions$new(web = TRUE)
)
} # }
```
