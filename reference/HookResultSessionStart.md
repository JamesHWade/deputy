# Create a SessionStart hook result

Return this from a SessionStart hook callback. This hook fires once at
the beginning of an agent session, before the first turn begins.

## Usage

``` r
HookResultSessionStart(handled = TRUE)
```

## Arguments

- handled:

  If TRUE, indicates the hook handled the session start event

## Value

A `HookResultSessionStart` object

## Examples

``` r
# Log session start
HookResultSessionStart()
#> $handled
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "HookResultSessionStart" "HookResult"             "list"                  

# Mark as handled
HookResultSessionStart(handled = TRUE)
#> $handled
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "HookResultSessionStart" "HookResult"             "list"                  
```
