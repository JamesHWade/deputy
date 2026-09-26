# Result of a delegation

How one delegation ended. The runtime's record (IDs, `status`,
`stop_reason`) is kept apart from what the subagent's model said
(`answer` and `claims`). A `"completed"` status means the run ended
normally, not that the task succeeded.
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
returns outcomes from `$parallel_delegate()` and, as JSON, from the
`delegate_to_agent` tool. Fields are read with `$`.

## Usage

``` r
DelegationOutcome(runtime, answer = "", references = list(), claims = list())
```

## Arguments

- runtime:

  List of IDs, `status`, `stop_reason` and other facts recorded by the
  runtime.

- answer:

  The subagent's final reply, cut to 8 KiB. A longer reply is saved in
  full in `references`.

- references:

  Saved artifacts, such as the full answer or large tool results, with
  their origin and whether they are still available.

- claims:

  The subagent's report of `missing_evidence` and `unresolved_work` from
  its structured output. `NULL` means it didn't report, not that nothing
  is missing.

## Value

A `DelegationOutcome` object.
