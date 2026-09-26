# Background job record

A read-only snapshot of a background job, returned by
[`job_read()`](https://jameshwade.github.io/deputy/reference/job_read.md),
[`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md)
and
[`job_cancel()`](https://jameshwade.github.io/deputy/reference/job_cancel.md).
Read fields with `$`. It holds plain data only, never an agent, chat,
tools, callbacks or credentials.

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

  The job directory.

- revision:

  Revision number; it goes up with each update.

- id:

  Job ID.

- status:

  One of `"queued"`, `"running"`, `"resuming"`, `"approval_pending"`,
  `"completed"`, `"failed"`, `"cancelled"` or `"indeterminate"`. The
  last four are final.

- task:

  The task text.

- owner_id:

  The `owner_id` given to
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md).

- definition_revision:

  The `definition_revision` given to
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md).

- context_revision:

  The `context_revision` given to
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md).

- usage_limits:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for the job.

- usage:

  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  so far.

- associations:

  The `associations` list given to
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md).

- manifest:

  The agent setup saved by
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md),
  which
  [`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md)
  checks the rebuilt agent against.

- allocation:

  The usage limits set aside when the job was created.

- reservations:

  Whether that allocation is still held or has been released.

- pending_approval:

  Details of the approval the job is waiting for, including its `path`,
  or `NULL`.

- pending_decision:

  The approval decision being applied (`decision`, `tool_input`,
  `recorded_at`), or `NULL`.

- transitions:

  Status changes, each with `from`, `to`, `at` and `reason`. Only the
  latest 128 are kept.

- events:

  Simplified run events: at most the latest 512, fewer if needed to stay
  within the storage limit.

- result:

  Summary of the final
  [AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
  (`response`, `stop_reason`, `usage` and so on), or `NULL`.

- error:

  Summary of the error that ended the job (`class`, `message` and so
  on), or `NULL`.

- cleanup:

  Who is responsible for cleaning up the job's resources, and whether
  cleanup has run.

- runtime:

  State saved while the job ran, such as the tool calls it executed.

- graph:

  Usage and limits of the retained agent graph, or `NULL` for a single
  agent.

- source:

  IDs of the agents, sessions and runs involved.

- control:

  Cancellation state: whether
  [`job_cancel()`](https://jameshwade.github.io/deputy/reference/job_cancel.md)
  was called, and its reason.

## Value

An `AgentJob` object.
