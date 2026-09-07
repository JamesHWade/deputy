# Inspect a durable approval continuation

Read an approval directory without loading a Chat or running any tools.
Snapshots are read-only S7 values; they are inspection records, not
grants. Use `agent$resume_approval(path, decision = "approve")` or
`"deny"` to consume a pending decision. Edited inputs are supplied
through `tool_input`.

Only `pending` records can resume. An `executing` record may have
produced effects; an interrupted `resuming` or `continuing` record also
requires host reconciliation. These records cannot automatically retry.
OS locks prevent concurrent consumers and are released when the owning
process exits.

Approval directories contain private conversation and tool data. The
host owns storage, access control, retention, and associations with its
conversation store. They never contain serialized tools, callbacks, or
Chat clients.

## Usage

``` r
approval_read(path)
```

## Arguments

- path:

  Path to an approval directory returned on the `approval` event.

## Value

An
[ApprovalContinuation](https://jameshwade.github.io/deputy/reference/ApprovalContinuation.md)
inspection value.
