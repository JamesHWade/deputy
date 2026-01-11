# Fetch web page content

A tool that fetches the content of a web page and returns it as text or
markdown. Requires the httr2 package for HTTP requests.

For JavaScript-rendered pages, consider using the chromote package with
a custom tool implementation.

## Usage

``` r
tool_web_fetch(url)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- url:

  The URL of the web page to fetch (tool argument)

## Details

This tool uses httr2 to fetch web content and extracts text from HTML.
If the rvest package is available, it extracts the main content more
intelligently. If pandoc is available via rmarkdown, HTML is converted
to markdown.

The tool respects a 30-second timeout and follows redirects.

## See also

[`tools_web()`](https://jameshwade.github.io/deputy/reference/tools_web.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = list(tool_web_fetch),
  permissions = Permissions$new(web = TRUE)
)
} # }
```
