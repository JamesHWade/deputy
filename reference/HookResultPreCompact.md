# Create a PreCompact hook result

Return this from a PreCompact hook callback to control whether
compaction should proceed.

## Usage

``` r
HookResultPreCompact(continue = TRUE, summary = NULL)
```

## Arguments

- continue:

  One non-missing logical value. If FALSE, cancels the compaction

- summary:

  Optional custom summary to use for compaction

## Value

A `HookResultPreCompact` S7 object

## See also

[CallbackResult](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
for read-only properties and S7 inspection.

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
