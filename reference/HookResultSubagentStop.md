# Create a SubagentStop hook result

Return this from a SubagentStop hook callback. This hook fires when a
sub-agent (delegated from a LeadAgent) completes its task.

## Usage

``` r
HookResultSubagentStop(handled = TRUE)
```

## Arguments

- handled:

  If TRUE, indicates the hook handled the sub-agent completion

## Value

A `HookResultSubagentStop` object

## Examples

``` r
# Basic handler
HookResultSubagentStop()
#> $handled
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "HookResultSubagentStop" "HookResult"             "list"                  

# Mark as handled
HookResultSubagentStop(handled = TRUE)
#> $handled
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "HookResultSubagentStop" "HookResult"             "list"                  
```
