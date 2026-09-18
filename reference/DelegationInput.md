# Describe a task-specific delegation input

[AgentDefinition](https://jameshwade.github.io/deputy/reference/agent_definition.md)
describes a reusable role. `DelegationInput` supplies one task,
instructions and ordered evidence references without granting authority.
String tasks remain supported and are equivalent to
`DelegationInput(task)`.

## Usage

``` r
DelegationInput(
  task,
  constraints = character(),
  evidence = list(),
  deliverable = NULL,
  stop_conditions = character()
)
```

## Arguments

- task:

  One non-empty UTF-8 task string. Whitespace is preserved.

- constraints:

  Task constraints, as a character vector.

- evidence:

  Ordered unnamed list of plain records with `source_id` and exact
  `revision`. References resolve only against the LeadAgent's host-owned
  scoped source snapshot. They are not paths, URLs or access grants.

- deliverable:

  Optional description of the expected output.

- stop_conditions:

  Text instructions about when to stop. These do not install runtime
  limits, permissions or approval decisions.

## Value

A read-only `DelegationInput` S7 value.

## Details

This read-only S7 value contains only portable text and lists. There are
at most 64 entries in each vector/reference list and a 1 MiB
serialized-input ceiling. A LeadAgent enforces its smaller configured
admission ceiling on resolved context. Unsupported multimodal or
executable content is rejected.
[`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
gives a portable record; `do.call(DelegationInput, record)` validates it
again. JSON readers should preserve record lists, for example
`jsonlite::fromJSON(json, simplifyVector = FALSE)`. No runtime state is
restored.

## Examples

``` r
DelegationInput("Review the contrast", constraints = "Preserve units")
#> <deputy::DelegationInput>
#>  @ task           : chr "Review the contrast"
#>  @ constraints    : chr "Preserve units"
#>  @ evidence       : list()
#>  @ deliverable    : NULL
#>  @ stop_conditions: chr(0) 
DelegationInput("Review the contrast", evidence = list(
  list(source_id = "assay-17", revision = "r3")
))
#> <deputy::DelegationInput>
#>  @ task           : chr "Review the contrast"
#>  @ constraints    : chr(0) 
#>  @ evidence       :List of 1
#>  .. $ :List of 2
#>  ..  ..$ source_id: chr "assay-17"
#>  ..  ..$ revision : chr "r3"
#>  @ deliverable    : NULL
#>  @ stop_conditions: chr(0) 
```
