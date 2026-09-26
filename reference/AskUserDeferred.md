# Defer answers to a later user turn

Return `AskUserDeferred()` from a
[`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)
handler when your app shows the questions without waiting for the
answers, as a chat interface does. The tool result tells the model that
the questions are on screen and that it should end its turn; the
person's answers arrive as their next message.

A handler that must wait within the run can instead return a
[`promises::promise()`](https://rstudio.github.io/promises/reference/promise.html)
for the answers. Deferring keeps runs short, and the answers arrive as
an ordinary user message. Subagents can't defer; their handler must
return the answers or a promise.

## Usage

``` r
AskUserDeferred(
  instructions = paste("The questions are now displayed to the person.",
    "End your turn with at most one short sentence.",
    "Do not answer the questions for them or assume a choice;",
    "their answers will arrive in their next message."),
  extra = list()
)
```

## Arguments

- instructions:

  One string telling the model what happens next. The default asks it to
  end its turn without answering for the person.

- extra:

  Optional named list stored in the tool result's `extra` field (see
  [`ellmer::ContentToolResult()`](https://ellmer.tidyverse.org/reference/Content.html)),
  for example data your app uses to display the questions.

## Value

A read-only `AskUserDeferred` S7 object.

## See also

[`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)

## Examples

``` r
handler <- function(questions, context) {
  # Show `questions` in your app, then return without waiting.
  AskUserDeferred()
}
tools <- tools_interactive(callback = handler)
```
