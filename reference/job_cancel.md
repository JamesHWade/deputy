# Cancel a background job

Records a request to cancel the job. A queued job, or one waiting for
approval, is cancelled straight away. A job that is running stops at the
next point where its process checks for cancellation, so the job
returned here may still be `"running"`. A job left `"running"` by a
process that died is marked `"indeterminate"`. Cancelling a finished job
does nothing.

## Usage

``` r
job_cancel(path, authorize, reason = "cancelled")
```

## Arguments

- path:

  Job directory returned by
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md).

- authorize:

  Function that checks the request, as in
  [`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md).

- reason:

  Reason to record, as one string.

## Value

The updated
[AgentJob](https://jameshwade.github.io/deputy/reference/AgentJob.md).
