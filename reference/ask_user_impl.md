# Ask user questions (internal implementation)

Ask user questions (internal implementation)

## Usage

``` r
ask_user_impl(questions, callback = NULL, context = list())
```

## Arguments

- questions:

  List of structured question objects

- callback:

  Optional instance-scoped handler. It receives `questions` and the
  resolved `context`. When omitted, the legacy process-wide fallback is
  used.

- context:

  Named routing context or a zero-argument function that returns it.

## Value

Named list mapping question text to selected answers
