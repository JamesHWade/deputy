# Inspect a compact delegation outcome

Runtime identity and stop facts are separate from model-authored answer
and claims. `completed` means execution ended normally, not verified
task success. Outcomes are produced by
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
and are read-only portable values.

## Usage

``` r
DelegationOutcome(runtime, answer = "", references = list(), claims = list())
```

## Arguments

- runtime:

  Plain runtime identity, status and stop-reason record.

- answer:

  Bounded model-authored answer text.

- references:

  Scoped artifact locators, with provenance and availability. References
  never confer authorization, verification or approval.

- claims:

  Model-authored missing-evidence and unresolved-work claims. `NULL`
  means not supplied, not that no work or evidence is missing.

## Value

A read-only `DelegationOutcome`.
