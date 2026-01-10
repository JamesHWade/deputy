# AskUserQuestion tool

A tool that allows the agent to ask the user clarifying questions and
receive their responses. This enables human-in-the-loop workflows where
the agent can request clarification or choices from the user.

## Usage

``` r
tool_ask_user(questions)
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Details

This tool follows the Anthropic Agent SDK format:

**Input format:**

- `questions`: Array of 1-4 question objects

- Each question has:

  - `question`: The full question text

  - `header`: Short label (max 12 chars)

  - `options`: Array of 2-4 options, each with `label` and `description`

  - `multiSelect`: Whether multiple selections are allowed

**Output format:**

- Returns a list with two elements:

  - `questions`: The original questions array (echoed back)

  - `answers`: Named list mapping question text to selected label(s)

- For multi-select, labels are joined with ", "

- Users can also type free-form responses

In interactive R sessions, the tool uses
[`readline()`](https://rdrr.io/r/base/readline.html) to get input. For
non-interactive use (scripts, Shiny apps), set a callback with
[`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md).

## See also

[`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)
for non-interactive usage

## Examples

``` r
if (FALSE) { # \dontrun{
# Add to agent's tools
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
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
