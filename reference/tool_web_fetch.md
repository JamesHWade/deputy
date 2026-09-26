# Fetch web page content

A tool that downloads a web page and returns its content as text or
Markdown. Needs the httr2 package. For pages rendered with JavaScript,
write your own tool with chromote.

## Usage

``` r
tool_web_fetch(url)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- url:

  URL of the page to fetch.

## Value

The page content as one string, cut at 50,000 characters.

## Details

Requests follow redirects and time out after 30 seconds. With rvest and
xml2 installed, the tool drops navigation, headers and footers and keeps
the main content; with rmarkdown and pandoc available, it converts that
HTML to Markdown. Otherwise it strips the tags. Content that isn't HTML
is returned as is.

## See also

[`tools_web()`](https://jameshwade.github.io/deputy/reference/tools_web.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = list(tool_web_fetch),
  permissions = Permissions(web = TRUE)
)
} # }
```
