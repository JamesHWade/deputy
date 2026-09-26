# Ask user questions (internal implementation)

Ask user questions (internal implementation)

## Usage

``` r
ask_user_impl(questions, callback = NULL, context = list())
```

## Arguments

- questions:

  List of question objects.

- callback:

  Optional handler for this tool. It receives `questions` and the
  resolved `context`. When omitted, the callback from
  [`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)
  is used, then [`readline()`](https://rdrr.io/r/base/readline.html).

- context:

  Named list, or a function with no arguments that returns one.

## Value

Named list mapping question text to selected answers
