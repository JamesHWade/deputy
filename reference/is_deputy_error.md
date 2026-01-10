# Check if an object is a deputy error

Tests whether an object is a deputy error condition.

## Usage

``` r
is_deputy_error(x, class = NULL)
```

## Arguments

- x:

  Object to test

- class:

  Optional specific error class to check for (without "deputy\_" prefix)

## Value

Logical indicating if `x` is a deputy error (of the specified class)

## Examples

``` r
if (FALSE) { # \dontrun{
tryCatch(
  abort_deputy("test"),
  error = function(e) {
    is_deputy_error(e)
    # TRUE
  }
)
} # }
```
