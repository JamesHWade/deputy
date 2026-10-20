# Create a Stop hook result

Return this from a Stop hook to send the run on: the model is asked
again with `message`, in the same run, which keeps its run ID, limits
and usage. Only an answered run is sent on, and never a batch from
`$parallel_delegate()`. `Stop` fires again at the next stop, with
`context$stop_hook_active` set to `TRUE`; check it so a hook doesn't
send the run on for ever.

## Usage

``` r
HookResultStop(message)
```

## Arguments

- message:

  The text the model is asked. It must not be empty.

## Value

A `HookResultStop` object.

## See also

[CallbackResult](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
for reading result fields.

## Examples

``` r
# Ask the model to fix its answer
HookResultStop("Fix the table.")
#> <deputy::HookResultStop>
#>  @ message: chr "Fix the table."

# A hook that sends the run on once, and never again in the same run
function(reason, context, ...) {
  if (isTRUE(context$stop_hook_active)) {
    return(NULL)
  }
  HookResultStop("Check the units and answer again.")
}
#> function (reason, context, ...) 
#> {
#>     if (isTRUE(context$stop_hook_active)) {
#>         return(NULL)
#>     }
#>     HookResultStop("Check the units and answer again.")
#> }
#> <environment: 0x564197703fc0>
```
