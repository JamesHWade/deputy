# Search the web

A tool that searches the web with DuckDuckGo's HTML search page and
returns the title, URL and snippet of each result. Needs the httr2
package. For better results, use a provider's own search tool (see
[`tools_web()`](https://jameshwade.github.io/deputy/reference/tools_web.md))
or a dedicated search API.

## Usage

``` r
tool_web_search(query, num_results = 10)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- query:

  The search query.

- num_results:

  Maximum number of results to return. Defaults to 10.

## Value

The numbered results as one string.

## See also

[`tools_web()`](https://jameshwade.github.io/deputy/reference/tools_web.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = list(tool_web_search),
  permissions = Permissions(web = TRUE)
)
} # }
```
