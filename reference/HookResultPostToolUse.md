# Create a PostToolUse hook result

Return this from a PostToolUse hook callback.

## Usage

``` r
HookResultPostToolUse(
  continue = TRUE,
  suppress_output = FALSE,
  updated_tool_output = NULL,
  additional_context = NULL,
  stop_reason = NULL
)
```

## Arguments

- continue:

  If FALSE, stop the agent after this hook

- suppress_output:

  Whether to suppress the result on Deputy's emitted `tool_end` event.
  This does not remove the result from model context.

- updated_tool_output:

  Optional replacement value for Deputy's emitted `tool_end` event.
  ellmer does not support rewriting the model-visible in-flight result
  from this callback.

- additional_context:

  Optional text to append to the running context

- stop_reason:

  Optional stop reason used when `continue = FALSE`

## Value

A `HookResultPostToolUse` object

## Examples

``` r
# Continue execution
HookResultPostToolUse()
#> $continue
#> [1] TRUE
#> 
#> $suppress_output
#> [1] FALSE
#> 
#> $updated_tool_output
#> NULL
#> 
#> $additional_context
#> NULL
#> 
#> $stop_reason
#> NULL
#> 
#> attr(,"class")
#> [1] "HookResultPostToolUse" "HookResult"            "list"                 

# Stop after this tool
HookResultPostToolUse(continue = FALSE)
#> $continue
#> [1] FALSE
#> 
#> $suppress_output
#> [1] FALSE
#> 
#> $updated_tool_output
#> NULL
#> 
#> $additional_context
#> NULL
#> 
#> $stop_reason
#> NULL
#> 
#> attr(,"class")
#> [1] "HookResultPostToolUse" "HookResult"            "list"                 
```
