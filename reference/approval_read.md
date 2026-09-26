# Read a pending approval

Reads an approval directory and returns the paused tool call, its status
and the usage so far, without loading a chat or running tools. To act on
a pending approval, call `agent$resume_approval(path, "approve")` or
`"deny"`, passing any edited inputs as `tool_input`.

Only a `"pending"` approval can be resumed, and only once. A record
interrupted while `"resuming"`, `"executing"` or `"continuing"` can't be
resumed or retried: its tool may already have run, so check the effects
yourself. File locks stop two processes resuming the same approval at
once, but nothing guarantees that a tool runs exactly once.

Approval directories hold the conversation and tool inputs, so keep them
private; access control and clean-up are up to you. They never contain
tools, callbacks or chat clients.

## Usage

``` r
approval_read(path)
```

## Arguments

- path:

  Path to an approval directory, as given in the `approval` event.

## Value

An
[ApprovalContinuation](https://jameshwade.github.io/deputy/reference/ApprovalContinuation.md).
