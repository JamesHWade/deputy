# Create a PreCompact hook result

Return this from a PreCompact hook to cancel compaction or to supply the
summary yourself.

## Usage

``` r
HookResultPreCompact(continue = TRUE, summary = NULL)
```

## Arguments

- continue:

  `TRUE` or `FALSE`. `FALSE` cancels the compaction.

- summary:

  Optional summary to use instead of generating one.

## Value

A `HookResultPreCompact` object.

## See also

[CallbackResult](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
for reading result fields.

## Examples

``` r
# Allow compaction
HookResultPreCompact()
#> <deputy::HookResultPreCompact>
#>  @ continue: logi TRUE
#>  @ summary : NULL

# Cancel compaction
HookResultPreCompact(continue = FALSE)
#> <deputy::HookResultPreCompact>
#>  @ continue: logi FALSE
#>  @ summary : NULL

# Provide custom summary
HookResultPreCompact(summary = "Previous conversation discussed X, Y, Z.")
#> <deputy::HookResultPreCompact>
#>  @ continue: logi TRUE
#>  @ summary : chr "Previous conversation discussed X, Y, Z."
```
