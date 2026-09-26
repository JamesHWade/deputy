# Set limits for the subagent event buffer

Each agent keeps recent subagent events in an in-memory buffer that
`$observe_subagents()` readers poll. When it is full, the oldest events
are dropped: a slow reader never holds up a run, but sees a gap.
Subagent transcripts are kept separately and don't count toward these
limits.

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

  Maximum number of events kept. Defaults to 256.

- max_bytes:

  Maximum total size of the kept events, in bytes. Defaults to 1 MiB.

- max_event_bytes:

  Maximum size of one event, in bytes: between 2048 and `max_bytes`, 64
  KiB by default. Larger content is replaced by a marker; get it from a
  [DelegationSubscription](https://jameshwade.github.io/deputy/reference/DelegationSubscription.md)
  snapshot instead.

## Value

A `DelegationObservation` object for the `delegation_observation`
argument of
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) or
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md).
