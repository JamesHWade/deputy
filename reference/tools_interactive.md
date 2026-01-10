# Tools for interactive workflows

Returns a list of tools that enable human-in-the-loop interactions.
Currently includes `tool_ask_user` (AskUserQuestion) for asking
clarifying questions.

## Usage

``` r
tools_interactive()
```

## Value

A list of tool definitions.

## See also

[tool_ask_user](https://jameshwade.github.io/deputy/reference/tool_ask_user.md),
[`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = c(tools_file(), tools_interactive())
)
} # }
```
