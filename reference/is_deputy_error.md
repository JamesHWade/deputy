# Check whether a condition is a Deputy error

Tests whether `x` is an error signalled by Deputy, optionally of a
specific class. See
[deputy-errors](https://jameshwade.github.io/deputy/reference/deputy-errors.md)
for the classes.

## Usage

``` r
is_deputy_error(x, class = NULL)
```

## Arguments

- x:

  Object to test.

- class:

  Optional error class to check for, without the `"deputy_"` prefix,
  such as `"budget"`.

## Value

`TRUE` if `x` has class `deputy_error` (and `deputy_<class>` when
`class` is given), otherwise `FALSE`.

## Examples

``` r
if (FALSE) { # \dontrun{
result <- tryCatch(
  agent$run_sync("Summarise the logs"),
  error = function(e) e
)
if (is_deputy_error(result, "budget")) {
  message("A usage limit stopped the run.")
}
} # }
```
