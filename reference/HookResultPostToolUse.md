# Create a PostToolUse hook result

Return this from a PostToolUse hook callback.

## Usage

``` r
HookResultPostToolUse(continue = TRUE)
```

## Arguments

- continue:

  If FALSE, stop the agent after this hook

## Value

A `HookResultPostToolUse` object

## Examples

``` r
# Continue execution
HookResultPostToolUse()
#> $continue
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "HookResultPostToolUse" "HookResult"            "list"                 

# Stop after this tool
HookResultPostToolUse(continue = FALSE)
#> $continue
#> [1] FALSE
#> 
#> attr(,"class")
#> [1] "HookResultPostToolUse" "HookResult"            "list"                 
```
