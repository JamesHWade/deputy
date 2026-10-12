# Create an ask_user tool with its own handler

Returns a list holding one `ask_user` tool (see
[tool_ask_user](https://jameshwade.github.io/deputy/reference/tool_ask_user.md))
that sends questions to `callback`. Give each agent its own tool when
several agents or Shiny sessions share one R process, or when the
session isn't interactive.

## Usage

``` r
tools_interactive(callback = NULL, context = list())
```

## Arguments

- callback:

  A function of `questions` and `context` that returns the answers, a
  promise for them, or
  [`AskUserDeferred()`](https://jameshwade.github.io/deputy/reference/AskUserDeferred.md)
  when the answers will come in the person's next message. Shiny apps
  can't wait for input, so they return a promise or
  [`AskUserDeferred()`](https://jameshwade.github.io/deputy/reference/AskUserDeferred.md).
  If `NULL`, the tool uses the
  [`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)
  callback if one is set, and otherwise
  [`readline()`](https://rdrr.io/r/base/readline.html) in an interactive
  session. See "Answers" below.

- context:

  A named list passed to `callback`, such as `agent_id` and `session_id`
  values that tell your app where to show the questions, or a function
  with no arguments that returns one. A function is called each time the
  model asks.

## Value

A list of tools.

## Answers

The answers are a named list. Each name is the exact text of a question,
and each value is a character vector:

- the chosen option labels: one for an ordinary question, any number for
  a question with `multiSelect = TRUE`;

- at most one other string, the answer the person typed themselves. For
  an ordinary question it takes the place of a label.

Leave a question out, or give it
[`character()`](https://rdrr.io/r/base/character.html), if it wasn't
answered. Give each chosen label as its own element; a string that isn't
a label is the person's own answer. A name that isn't one of the
questions, a value that isn't a character vector, or too many answers
for a question is an error, and the model is told the answers couldn't
be collected.

The model receives, for each question, the `selected` labels and the
`other_text`; see
[tool_ask_user](https://jameshwade.github.io/deputy/reference/tool_ask_user.md)
for the exact result.

## See also

[tool_ask_user](https://jameshwade.github.io/deputy/reference/tool_ask_user.md),
[`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)

## Examples

``` r
if (FALSE) { # \dontrun{
agent_id <- "agent-review"
session_id <- "session-review"
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
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
