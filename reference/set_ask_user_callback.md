# Set a process-wide handler for ask_user

Sets a callback that answers questions for every `ask_user` tool without
its own handler, including
[tool_ask_user](https://jameshwade.github.io/deputy/reference/tool_ask_user.md).
It is used instead of
[`readline()`](https://rdrr.io/r/base/readline.html), even in
interactive sessions. Because it is shared by the whole R process, it
can't tell concurrent agents or Shiny sessions apart; for those, give
each agent its own handler with
[`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md).

## Usage

``` r
set_ask_user_callback(callback)
```

## Arguments

- callback:

  A function that takes `questions`, a list in which each question has
  `question`, `header`, `options` (each with `label` and `description`)
  and `multiSelect`. It returns a named list mapping each question's
  text to the chosen label; join several labels with `", "`. `NULL`
  removes the callback.

## Value

The previous callback (or `NULL`), invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
# For a single-agent script: always pick the first option
set_ask_user_callback(function(questions) {
  answers <- list()
  for (q in questions) {
    answers[[q$question]] <- q$options[[1]]$label
  }
  answers
})
} # }
```
