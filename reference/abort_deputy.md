# Abort with a structured deputy error

Creates and signals a structured deputy error using cli formatting. All
deputy errors include a message, optional context, and inherit from the
`deputy_error` condition class.

## Usage

``` r
abort_deputy(message, class = NULL, ..., .envir = parent.frame())
```

## Arguments

- message:

  The error message (supports cli formatting)

- class:

  Additional classes to add (will be prefixed with "deputy\_")

- ...:

  Additional fields to include in the error condition

- .envir:

  Environment for cli interpolation

## Value

Does not return; signals an error condition

## Examples

``` r
if (FALSE) { # \dontrun{
# Signal an error
abort_deputy("Something went wrong", class = "custom")

# Catch deputy errors
tryCatch(
  abort_deputy("test"),
  deputy_error = function(e) message("Caught: ", conditionMessage(e))
)
} # }
```
