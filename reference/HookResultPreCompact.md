# Create a PreCompact hook result

Return this from a PreCompact hook callback to control whether
compaction should proceed.

## Usage

``` r
HookResultPreCompact(continue = TRUE, summary = NULL)
```

## Arguments

- continue:

  If FALSE, cancels the compaction

- summary:

  Optional custom summary to use for compaction

## Value

A `HookResultPreCompact` object

## Examples

``` r
# Allow compaction
HookResultPreCompact()
#> $continue
#> [1] TRUE
#> 
#> $summary
#> NULL
#> 
#> attr(,"class")
#> [1] "HookResultPreCompact" "HookResult"           "list"                

# Cancel compaction
HookResultPreCompact(continue = FALSE)
#> $continue
#> [1] FALSE
#> 
#> $summary
#> NULL
#> 
#> attr(,"class")
#> [1] "HookResultPreCompact" "HookResult"           "list"                

# Provide custom summary
HookResultPreCompact(summary = "Previous conversation discussed X, Y, Z.")
#> $continue
#> [1] TRUE
#> 
#> $summary
#> [1] "Previous conversation discussed X, Y, Z."
#> 
#> attr(,"class")
#> [1] "HookResultPreCompact" "HookResult"           "list"                
```
