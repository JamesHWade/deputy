# Pending approval record

A read-only snapshot of a saved approval, returned by
[`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md)
and `agent$pending_approval()`. Read fields with `$`. You rarely need to
create one yourself; doing so doesn't save it or approve anything.

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

  Approval ID.

- status:

  One of `"pending"`, `"resuming"`, `"executing"`, `"continuing"`,
  `"completed"`, `"stopped"` or `"indeterminate"`.

- request:

  List describing the paused call: `tool_call_id`, `name`, `tool_input`,
  `reason`, and `kind` (`"tool"`, or `"budget"` when a usage limit
  caused the pause).

- decision:

  The recorded decision (`decision` and `tool_input`), or `NULL` if
  there is none yet.

- context:

  The run's `run_context`.

- usage:

  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  so far, including work before the pause.

- usage_limits:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  of the paused run. Resuming reuses them unless you pass others.

- budget_ceiling:

  The agent's
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  from the original run. Limits passed to `resume_approval()` can't go
  beyond these or the agent's current limits.

- permissions:

  The saved permission policy, as a list. Resumed tool calls must be
  allowed by both it and the agent's current policy. `callback_required`
  says whether `can_use_tool` must be set again before resuming.

- effects:

  Log of tool calls the run has executed, with their status.

- source:

  IDs of the session, agent and run that paused.
  [`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md)
  adds `path`, the approval directory.

## Value

An `ApprovalContinuation` object.
