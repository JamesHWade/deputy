# Get web tools

Returns a `web_search` and a `web_fetch` tool. By default these are
[tool_web_search](https://jameshwade.github.io/deputy/reference/tool_web_search.md)
(DuckDuckGo) and
[tool_web_fetch](https://jameshwade.github.io/deputy/reference/tool_web_fetch.md),
which work with any provider. If you pass `chat`, the provider's own
tools are used where available:

- Anthropic: `claude_tool_web_search()` and `claude_tool_web_fetch()`.
  These cost extra and may need to be enabled by your organization's
  admin.

- Google Gemini and Vertex: `google_tool_web_search()` and
  `google_tool_web_fetch()`.

- OpenAI: `openai_tool_web_search()`, plus
  [tool_web_fetch](https://jameshwade.github.io/deputy/reference/tool_web_fetch.md).

- Other providers: the default tools.

Provider tools run on the provider's servers, so the agent checks them
once, at registration, not on each call. It accepts them only if its
permissions set `web = TRUE`, list the tool names in `tool_allowlist`,
and have no `can_use_tool` callback.

## Usage

``` r
tools_web(chat = NULL, use_native = TRUE)
```

## Arguments

- chat:

  Optional ellmer Chat, used to pick the provider's own tools.

- use_native:

  If `FALSE`, always return the default tools.

## Value

A list of tools.

## See also

[tool_web_fetch](https://jameshwade.github.io/deputy/reference/tool_web_fetch.md),
[tool_web_search](https://jameshwade.github.io/deputy/reference/tool_web_search.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Default tools, for any provider
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = tools_web(),
  permissions = Permissions(web = TRUE)
)

# Anthropic's own web tools
chat <- ellmer::chat("anthropic/claude-sonnet-5")
agent <- Agent$new(
  chat = chat,
  tools = tools_web(chat),
  permissions = Permissions(
    web = TRUE,
    tool_allowlist = c("web_search", "web_fetch")
  )
)

# Default tools, even with Anthropic
agent <- Agent$new(
  chat = chat,
  tools = tools_web(chat, use_native = FALSE),
  permissions = Permissions(web = TRUE)
)
} # }
```
