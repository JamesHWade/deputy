# Durable approval inspection value

A read-only view of a durable approval. Normally obtained with
[`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md).
Constructing a value does not persist it or authorize execution.

## Usage

``` r
ApprovalContinuation(
  id,
  status,
  request,
  decision = NULL,
  context = list(),
  usage = AgentUsage(),
  usage_limits = UsageLimits(),
  budget_ceiling = UsageLimits(),
  permissions = list(),
  effects = list(),
  source = list()
)
```

## Arguments

- id:

  Stable approval identifier.

- status:

  Pending, executing, or terminal state.

- request:

  Named record containing tool name, inputs, and reason.

- decision:

  Recorded host decision, or NULL.

- context:

  Canonical host run context.

- usage:

  Observed
  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md),
  including work before suspension.

- usage_limits:

  Governing
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md).

- budget_ceiling:

  Original Agent budget ceiling for explicit escalation.

- permissions:

  Saved static permission ceiling and callback requirement.

- effects:

  Execution journal entries.

- source:

  Session, Agent, and source-run correlation.

## Value

An `ApprovalContinuation` S7 value.
