# Run a background job

Runs a queued job, or resumes one waiting for approval, in the current R
process and returns when the run ends. It calls `authorize` first; a
refusal errors and leaves the job untouched. It then calls `bind`; if
that fails, or the rebuilt agent doesn't match the setup saved by
[`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md),
the job fails. A running job is locked, so a second `job_run()` on it
errors.

## Usage

``` r
job_run(path, bind, authorize, decision = NULL, tool_input = NULL)
```

## Arguments

- path:

  Job directory returned by
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md).

- bind:

  Function that takes the
  [AgentJob](https://jameshwade.github.io/deputy/reference/AgentJob.md)
  and returns the rebuilt
  [Agent](https://jameshwade.github.io/deputy/reference/Agent.md), or
  `list(agent = , cleanup = )` where `cleanup` is a function that
  `job_run()` calls when it is done with the agent.

- authorize:

  Function that takes the
  [AgentJob](https://jameshwade.github.io/deputy/reference/AgentJob.md)
  and returns a list of your app's current `job_id`, `owner_id`,
  `definition_revision` and `context_revision` for it; the job runs only
  if they match the saved values. Look them up rather than copying them
  from the job, and signal an error to refuse.

- decision:

  `"approve"` or `"deny"`, to resume a job waiting for approval.

- tool_input:

  Optional edited tool arguments (a named list) to approve with.

## Value

The updated
[AgentJob](https://jameshwade.github.io/deputy/reference/AgentJob.md).

## Details

A finished job is returned unchanged, and so is a job waiting for
approval unless you pass `decision`. If a previous `job_run()` stopped
partway, for example because its process was killed, the job is marked
`"indeterminate"` and not run again: a tool may already have had
effects, so check what happened before creating new work.
