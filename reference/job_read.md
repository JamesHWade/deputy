# Read a durable Agent job without binding or executing it

Read a durable Agent job without binding or executing it

## Usage

``` r
job_read(path)
```

## Arguments

- path:

  Committed directory returned by
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md).

## Value

A read-only
[AgentJob](https://jameshwade.github.io/deputy/reference/AgentJob.md)
inspection value.
