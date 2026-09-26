# Read a background job

Returns the job's saved state. It doesn't rebuild the agent, call the
model or run tools, so it's safe to use for status displays.

## Usage

``` r
job_read(path)
```

## Arguments

- path:

  Job directory returned by
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md).

## Value

An
[AgentJob](https://jameshwade.github.io/deputy/reference/AgentJob.md).
