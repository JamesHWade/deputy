# Create a background job

Saves a task in a new job directory so that
[`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md)
can run it later, possibly in another R process. The agent isn't saved:
Deputy records its setup (model, system prompt, tools, permissions,
conversation and so on), and
[`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md)
checks that the agent you rebuild matches it.

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

  Directory to create the job directory in. It is created if needed.

- agent:

  The [Agent](https://jameshwade.github.io/deputy/reference/Agent.md) to
  describe. `bind` in
  [`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md)
  must rebuild an agent with the same setup.

- task:

  The task, as one non-empty string.

- owner_id:

  ID of the user or tenant that owns the job.

- definition_revision:

  Your label (a string or number) for the current version of the agent's
  configuration.
  [`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md)
  runs the job only if `authorize` returns the same value.

- context_revision:

  Your label (a string or number) for the current version of the context
  the agent works from, checked the same way.

- usage_limits:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for the job.

- associations:

  Optional plain list of your own data to keep with the job, such as a
  conversation ID.

- max_bytes:

  Size limit for the job's saved record, in bytes (50 MiB by default).
  While the job is active, the record must stay below half this limit
  minus about 1.1 MiB, which is kept free for the final result and
  cleanup. `job_create()` errors if the first record is too big.

## Value

The path to the new job directory. Keep it to run, read or cancel the
job.

## Details

The agent must be idle and must be a plain
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) (not a
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md))
or the root of a graph from `agent$retain_agent_graph()`. Fallback chats
and provider-native tools aren't supported.

## See also

[`vignette("background-jobs")`](https://jameshwade.github.io/deputy/articles/background-jobs.md)
