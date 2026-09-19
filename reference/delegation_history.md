# Replay authorized settled child history

Replays host-owned snapshots from `LeadAgent$export_subagents()` using
public ellmer Content records. No Chat, model request, tools, or active
execution is restored. Hosts own durable storage and authenticate the
supplied history; this function does not treat stored scope or IDs as
authorization.

## Usage

``` r
delegation_history(history, requester, disclosure, scope)
```

## Arguments

- history:

  A portable snapshot produced by `export_subagents()`.

- requester:

  Authenticated host request context.

- disclosure:

  A freshly host-bound
  [DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md).

- scope:

  Current host scope, matched exactly against the saved scope after
  authorization. Obtain it from the host's own durable ownership record.

## Value

Authorized, redacted child views with native ellmer `turns` added for
read-only rendering. Artifact availability is `unresolved` until the
host checks its retained storage; saved availability is never treated as
current.
