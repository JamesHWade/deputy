# Return tools from a resource factory

The value returned by a
[DelegationPolicy](https://jameshwade.github.io/deputy/reference/DelegationPolicy.md)
`resources` function: the tools built for one subagent and a function
that releases them.

## Usage

``` r
DelegationResources(tools = list(), cleanup)
```

## Arguments

- tools:

  List of ellmer tools built for this subagent.

- cleanup:

  A function with no arguments that releases what the factory created.
  Deputy calls it once when the delegation ends, including after a
  failure during setup such as a rejected tool. Errors are recorded in
  the `cleanup_error` column of `$list_subagents()`.

## Value

A `DelegationResources` object.

## See also

[DelegationPolicy](https://jameshwade.github.io/deputy/reference/DelegationPolicy.md)
