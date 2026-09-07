# Request a durable tool approval

Return this from a
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
`can_use_tool` callback to suspend before execution. The Agent must have
an `approval_dir`. Resumable tools must be registered with
`convert = FALSE`; their functions accept raw JSON arguments. Tool
outputs should be strings, explicit JSON, or ellmer Content values. Raw
JSON shaped like a content record (`version`, `class`, `props`) is
rejected because ellmer replay would reinterpret it as an S7
constructor. No approval is granted by constructing this value.

## Usage

``` r
PermissionResultPending(reason = "Approval required")
```

## Arguments

- reason:

  One non-empty string explaining the pending decision.

## Value

A read-only S7 permission result.

## See also

[`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md),
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md)
