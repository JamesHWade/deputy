# Validate questions structure

Checks the typed questions array. A string is never parsed or read: it
is rejected like any other malformed value. Each failure is a tool
rejection whose message tells the model what to fix.

## Usage

``` r
validate_questions(questions)
```

## Arguments

- questions:

  List of question objects

## Value

The questions, each with exactly `question`, `header`, `options` (each
with `label` and `description`) and a logical `multiSelect`.
