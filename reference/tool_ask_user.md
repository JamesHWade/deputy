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

  A list of 1 to 4 questions. Each has `question` (the full text),
  `header` (a label of at most 12 characters), `options` (2 to 4, each
  with `label` and `description`) and, optionally, `multiSelect` (`TRUE`
  to allow several options). Every text is a non-empty string, no two
  questions have the same text, and no two options of a question have
  the same label. Questions that break these rules, or that arrive as a
  string such as JSON text, are sent back to the model to fix.

## Value

JSON text, which is what the model reads. It holds the `questions` and
an `answers` array with one entry per question, in the same order:
`question`, `selected` (an array of the chosen option labels, empty if
none was chosen) and `other_text` (the answer the person typed instead
of, or for a multi-select question as well as, choosing options; `null`
if none). Read it in R with
[`jsonlite::parse_json()`](https://jeroen.r-universe.dev/jsonlite/reference/read_json.html).
If the handler returns
[`AskUserDeferred()`](https://jameshwade.github.io/deputy/reference/AskUserDeferred.md),
the result is instead a list with the `questions`, `status` `"deferred"`
and `instructions` for the model.

## Details

This tool asks through the callback set with
[`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)
if there is one, and otherwise with
[`readline()`](https://rdrr.io/r/base/readline.html) in an interactive
session. With neither, the call errors. In a Shiny app, or anywhere
several agents share one R process, use
[`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)
to give each agent its own handler.

At the [`readline()`](https://rdrr.io/r/base/readline.html) prompt, the
person enters an option number, several numbers separated by commas for
a multi-select question, or their own answer. A number that doesn't
match an option asks again.

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
