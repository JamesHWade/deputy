# Parse user response as option number(s) or free text

A response made only of digits, commas, signs, dots and spaces is read
as option numbers. Each must be a whole number from 1 to the number of
options, and a single-select question takes exactly one. Any other text
is the person's own answer.

## Usage

``` r
parse_user_response(response, options, multi_select = FALSE)
```

## Arguments

- response:

  User's input string

- options:

  List of option objects with label and description

- multi_select:

  Whether multiple selections are allowed

## Value

A character vector: the chosen labels, in the order given, or the free
text response. `NULL` when the response is option numbers that can't all
be used, so the caller asks again.
