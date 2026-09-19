# Return resources owned by one delegation

Return resources owned by one delegation

## Usage

``` r
DelegationResources(tools = list(), cleanup)
```

## Arguments

- tools:

  List of ellmer function tools constructed for the supplied child.

- cleanup:

  Zero-argument synchronous function releasing all constructed
  resources. Deputy calls it once after settlement, cancellation, or
  subsequent setup failure, including rejected tools. It must not resume
  or approve work. Cleanup errors are retained separately in
  `list_subagents()$cleanup_error`. Cancellation is cooperative;
  borrowed resources are never closed by Deputy.

## Value

A read-only runtime `DelegationResources` value, not a portable receipt.

## See also

[DelegationPolicy](https://jameshwade.github.io/deputy/reference/DelegationPolicy.md)
