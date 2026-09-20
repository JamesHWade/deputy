# AgentJob read-only durable inspection

AgentJob values are returned by job_read and job_run. They contain
portable lifecycle and outcome data, never Agents, Chats, tools,
callbacks, credentials, connections, promises or cleanup closures.

## Usage

``` r
AgentJob(
  path,
  revision,
  id,
  status,
  task,
  owner_id,
  definition_revision,
  context_revision,
  usage_limits,
  usage,
  associations = list(),
  manifest = list(),
  allocation = list(),
  reservations = list(),
  pending_approval = NULL,
  pending_decision = NULL,
  transitions = list(),
  events = list(),
  result = NULL,
  error = NULL,
  cleanup = list(),
  runtime = list(),
  graph = NULL,
  source = list(),
  control = list()
)
```

## Arguments

- path:

  Committed job directory.

- revision:

  Immutable record revision.

- id:

  Stable job identifier.

- status:

  Durable lifecycle status.

- task:

  Submitted task text.

- owner_id:

  Host owner identifier.

- definition_revision:

  Host Agent-definition revision.

- context_revision:

  Host source-context revision.

- usage_limits:

  Reserved usage ceiling.

- usage:

  Observed usage.

- associations:

  Portable host associations.

- manifest:

  Portable Agent and graph manifest.

- allocation:

  Original allocation reservation.

- reservations:

  Durable reservation state.

- pending_approval:

  Persisted approval inspection, or NULL.

- pending_decision:

  Persisted decision receipt, or NULL.

- transitions:

  Bounded lifecycle transitions.

- events:

  Bounded runtime events.

- result:

  Portable terminal result summary, or NULL.

- error:

  Portable terminal error summary, or NULL.

- cleanup:

  Cleanup ownership and ledger state.

- runtime:

  Portable runtime snapshot.

- graph:

  Portable graph snapshot, or NULL.

- source:

  Portable correlation metadata.

- control:

  Portable independent cancellation state.

## Value

A read-only S7 AgentJob value.
