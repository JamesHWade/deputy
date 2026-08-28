# Set callback for non-interactive user input

Sets a legacy process-wide callback for non-interactive sessions. This
fallback cannot isolate concurrent Agents or Shiny sessions. New code
should bind a handler to a tool instance with
[`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md).

## Usage

``` r
set_ask_user_callback(callback)
```

## Arguments

- callback:

  A function that takes `questions` in Deputy's structured question
  format. Each question has `question`, `header`, `options` (list with
  `label` and `description`), and `multiSelect`. Should return a named
  list mapping question text to selected label(s). For multi-select,
  join labels with ", ". Set to NULL to clear the callback.

## Value

Invisibly returns the previous callback (or NULL).

## Examples

``` r
if (FALSE) { # \dontrun{
# Legacy fallback for a single-Agent script:
set_ask_user_callback(function(questions) {
  # Display questions in modal and collect answers
  answers <- list()
  for (q in questions) {
    # Collect one answer for each question.
    answers[[q$question]] <- selected_label
  }
  answers
})
} # }
```
