# Bound the child activity observation buffer

One in-memory ring belongs to each LeadAgent. Subscribers hold only
cursors; they cannot block execution or accumulate private queues.
Retained transcript storage is separate from this transient buffer.

## Usage

``` r
DelegationObservation(
  max_events = 256L,
  max_bytes = 1024^2,
  max_event_bytes = 65536
)
```

## Arguments

- max_events:

  Maximum retained events, default 256.

- max_bytes:

  Maximum serialized bytes across retained envelopes, default 1 MiB. The
  buffer evicts oldest envelopes until both limits hold.

- max_event_bytes:

  Maximum bytes in one event, default 64 KiB. Oversized or nonportable
  content becomes an explicit omission envelope; hosts recover completed
  public content from an authorized snapshot.

## Value

Read-only observation limits for
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md).
