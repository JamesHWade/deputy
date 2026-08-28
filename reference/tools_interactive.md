# Tools for interactive workflows

Returns a list of tools that enable human-in-the-loop interactions.
Currently includes `tool_ask_user` (`ask_user`) for asking clarifying
questions. Supply `callback` in non-interactive or concurrent hosts so
each Agent receives its own handler.

## Usage

``` r
tools_interactive(callback = NULL, context = list())
```

## Arguments

- callback:

  Optional handler with signature `function(questions, context)`. It
  should return a named list that maps each question text to the
  selected label or labels. When omitted, interactive sessions use
  [`readline()`](https://rdrr.io/r/base/readline.html) and
  non-interactive sessions may use the legacy callback from
  [`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md).

- context:

  Named list of stable host routing values, such as `agent_id` and
  `session_id`, or a zero-argument function returning that list. A
  function is resolved for each question request.

## Value

A list of tool definitions.

## See also

[tool_ask_user](https://jameshwade.github.io/deputy/reference/tool_ask_user.md),
[`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent_id <- "agent-review"
session_id <- "session-review"
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = c(
    tools_file(),
    tools_interactive(
      callback = function(questions, context) {
        collect_answers(questions, route = context$session_id)
      },
      context = list(agent_id = agent_id, session_id = session_id)
    )
  ),
  agent_id = agent_id,
  session_id = session_id
)
} # }
```
