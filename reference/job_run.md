# Consume one durable Agent job

The host controls authorization, Agent reconstruction, and resource
cleanup. The execution lock is held from the durable running transition
through runtime detachment and terminal persistence.

## Usage

``` r
job_run(path, bind, authorize, decision = NULL, tool_input = NULL)
```

## Arguments

- path:

  Committed directory returned by
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md).

- bind:

  Function receiving an
  [AgentJob](https://jameshwade.github.io/deputy/reference/AgentJob.md)
  and returning an Agent or a list with fields agent and cleanup.

- authorize:

  Function receiving an
  [AgentJob](https://jameshwade.github.io/deputy/reference/AgentJob.md)
  and returning the exact identity receipt with job_id, owner_id,
  definition_revision, and context_revision.

- decision:

  Approval decision, approve or deny, for a pending job.

- tool_input:

  Optional edited raw input for a pending approval.

## Value

A read-only
[AgentJob](https://jameshwade.github.io/deputy/reference/AgentJob.md)
inspection value.
