# Request durable cooperative cancellation of an Agent job

The small control store is independent from the execution store, so a
cancellation request can be recorded while a worker owns the execution
lock. The worker observes it at runtime checkpoints and through its
bounded interrupt poller.

## Usage

``` r
job_cancel(path, authorize, reason = "cancelled")
```

## Arguments

- path:

  Committed directory returned by
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md).

- authorize:

  Function returning the exact job identity receipt.

- reason:

  Host cancellation reason.

## Value

A read-only
[AgentJob](https://jameshwade.github.io/deputy/reference/AgentJob.md)
inspection value.
