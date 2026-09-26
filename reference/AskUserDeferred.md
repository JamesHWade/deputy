# Defer answers to a later user turn

Return `AskUserDeferred()` from a
[`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)
handler when the host shows the questions without waiting for them, as a
chat interface does. The tool result tells the model that the questions
are displayed and that it should end its turn; the person's answers then
arrive in their next message.

A handler that must wait inside the current run can instead return a
[`promises::promise()`](https://rstudio.github.io/promises/reference/promise.html)
resolving to the named answers list. Deferred answers keep the run short
and make the reply an ordinary user turn, which a host can persist,
quote and cancel like any other message.

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

  Optional named list stored as
  [`ellmer::ContentToolResult()`](https://ellmer.tidyverse.org/reference/Content.html)
  `extra`, for example a host display for the questions.

## Value

A read-only `AskUserDeferred` S7 object.

## See also

[`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)

## Examples

``` r
handler <- function(questions, context) {
  # Show `questions` in the host UI, then return without waiting.
  AskUserDeferred()
}
tools <- tools_interactive(callback = handler)
```
