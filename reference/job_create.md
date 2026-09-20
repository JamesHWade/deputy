# Create a durable host-owned Agent job

The Agent is inspected into a portable manifest. It is never serialized;
the host supplies a binder again when
[`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md)
consumes the job.

## Usage

``` r
job_create(
  directory,
  agent,
  task,
  owner_id,
  definition_revision,
  context_revision,
  usage_limits,
  associations = list(),
  max_bytes = 50 * 1024^2
)
```

## Arguments

- directory:

  Parent directory owned by the host.

- agent:

  Idle ordinary
  [Agent](https://jameshwade.github.io/deputy/reference/Agent.md) whose
  exact manifest is retained.

- task:

  Non-empty task text.

- owner_id:

  Host owner or tenant identifier.

- definition_revision:

  Host revision for the Agent definition.

- context_revision:

  Host revision for source context.

- usage_limits:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  reserved for this job.

- associations:

  Portable host conversation associations.

- max_bytes:

  Maximum bytes for each immutable store. Active job revisions must also
  leave 1 MiB + 128 KiB per revision for cleanup and terminal
  settlement; admission fails if the initial record and reserve cannot
  fit.

## Value

The committed job directory.
