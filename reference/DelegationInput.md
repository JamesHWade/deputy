# Describe a task for a subagent

An
[AgentDefinition](https://jameshwade.github.io/deputy/reference/agent_definition.md)
describes a reusable subagent; a `DelegationInput` describes one task
for it: what to do, constraints, evidence, the expected deliverable and
when to stop. A plain string task is the same as
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

  The task, as a single non-empty string.

- constraints:

  Constraints on the task, as a character vector.

- evidence:

  Sources to give the subagent: an unnamed list of lists, each with the
  `source_id` and exact `revision` of a record passed to
  [LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
  as `delegation_sources`. They are not file paths or URLs.

- deliverable:

  Optional description of the expected output.

- stop_conditions:

  When to stop, as a character vector. These are instructions for the
  model; use
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  to enforce limits.

## Value

A `DelegationInput` object.

## Details

`constraints`, `evidence` and `stop_conditions` hold up to 64 entries
each, and the whole input must be under 1 MiB. A
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
also applies its `delegation_max_bytes` limit, 64 KiB by default.

The object is read-only; read its fields with `$`. To store it, save
`S7::props(x)` and rebuild it with `do.call(DelegationInput, record)`.
When reading the record from JSON, keep lists intact with
`jsonlite::fromJSON(json, simplifyVector = FALSE)`.

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
