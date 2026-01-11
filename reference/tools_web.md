# Web tools

Returns a list of tools for web operations. When a `chat` object is
provided, automatically selects the best tools for that provider:

- **Claude (Anthropic)**: Uses native `claude_tool_web_search()` and
  `claude_tool_web_fetch()` for higher quality results (requires admin
  enablement and incurs extra cost)

- **Google (Gemini/Vertex)**: Uses native `google_tool_web_search()` and
  `google_tool_web_fetch()`

- **OpenAI**: Uses native `openai_tool_web_search()`

- **Other providers**: Falls back to universal tools using httr2 and
  DuckDuckGo

Without a `chat` argument, returns universal tools that work with any
provider.

## Usage

``` r
tools_web(chat = NULL, use_native = TRUE)
```

## Arguments

- chat:

  Optional ellmer Chat object. If provided, returns provider-specific
  tools when available for better quality results.

- use_native:

  Logical. If `TRUE` (default), use native provider tools when
  available. Set to `FALSE` to always use universal tools.

## Value

A list of tool definitions

## See also

[tool_web_fetch](https://jameshwade.github.io/deputy/reference/tool_web_fetch.md),
[tool_web_search](https://jameshwade.github.io/deputy/reference/tool_web_search.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Universal tools (work with any provider)
agent <- Agent$new(
  chat = ellmer::chat_ollama(),
  tools = tools_web(),
  permissions = Permissions$new(web = TRUE)
)

# Provider-specific tools (auto-detected)
chat <- ellmer::chat_claude()
agent <- Agent$new(
  chat = chat,
  tools = tools_web(chat),  # Uses Claude's native web tools
  permissions = Permissions$new(web = TRUE)
)

# Force universal tools even with Claude
agent <- Agent$new(
  chat = chat,
  tools = tools_web(chat, use_native = FALSE),
  permissions = Permissions$new(web = TRUE)
)
} # }
```
