# Ask the user questions

A tool that lets the model ask the user one to four multiple-choice
questions and wait for the answers.

## Usage

``` r
tool_ask_user(questions)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- questions:

  A JSON string or list of 1 to 4 questions. Each has `question` (the
  full text), `header` (a label of at most 12 characters), `options` (2
  to 4, each with `label` and `description`) and, optionally,
  `multiSelect`.

## Value

A list with the `questions` and a named `answers` list that maps each
question's text to the chosen label. Several labels are joined with
`", "`, and a person can also type their own answer.

## Details

This tool asks through the callback set with
[`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)
if there is one, and otherwise with
[`readline()`](https://rdrr.io/r/base/readline.html) in an interactive
session. With neither, the call errors. In a Shiny app, or anywhere
several agents share one R process, use
[`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)
to give each agent its own handler.

## See also

[`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)
to give each agent its own handler.

## Examples

``` r
if (FALSE) { # \dontrun{
# Add to agent's tools
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = c(tools_file(), tool_ask_user)
)

# The agent can ask structured questions like:
# {
#   "questions": [{
#     "question": "How should I format the output?",
#     "header": "Format",
#     "options": [
#       {"label": "Summary", "description": "Brief overview"},
#       {"label": "Detailed", "description": "Full explanation"}
#     ],
#     "multiSelect": false
#   }]
# }
} # }
```
