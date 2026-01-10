# Create a SessionEnd hook result

Return this from a SessionEnd hook callback. This hook fires once at the
end of an agent session, after the agent stops for any reason.

## Usage

``` r
HookResultSessionEnd(handled = TRUE)
```

## Arguments

- handled:

  If TRUE, indicates the hook handled the session end event

## Value

A `HookResultSessionEnd` object

## Examples

``` r
# Log session end
HookResultSessionEnd()
#> $handled
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "HookResultSessionEnd" "HookResult"           "list"                

# Mark as handled
HookResultSessionEnd(handled = TRUE)
#> $handled
#> [1] TRUE
#> 
#> attr(,"class")
#> [1] "HookResultSessionEnd" "HookResult"           "list"                
```
