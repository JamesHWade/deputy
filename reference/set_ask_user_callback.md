# Set callback for non-interactive user input

In non-interactive sessions (scripts, Shiny apps, etc.), set a callback
function that will be called when the agent needs user input via
`AskUserQuestion`.

## Usage

``` r
set_ask_user_callback(callback)
```

## Arguments

- callback:

  A function that takes `questions` (list matching the AskUserQuestion
  format). Each question has `question`, `header`, `options` (list with
  `label` and `description`), and `multiSelect`. Should return a named
  list mapping question text to selected label(s). For multi-select,
  join labels with ", ". Set to NULL to clear the callback.

## Value

Invisibly returns the previous callback (or NULL).

## Examples

``` r
if (FALSE) { # \dontrun{
# For a Shiny app:
set_ask_user_callback(function(questions) {
  # Display questions in modal and collect answers
  answers <- list()
  for (q in questions) {
    # Show q$question with q$options
    # Collect user selection
    answers[[q$question]] <- selected_label
  }
  answers
})
} # }
```
