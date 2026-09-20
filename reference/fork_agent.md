# Retain a host-authorized context fork for explicit continuation

The child must be a standalone Agent with an independent empty Chat. Its
own tools, prompt and resources remain host-configured; the fork only
seeds inert selected history and uses the ordinary retained-conversation
governance.

## Usage

``` r
fork_agent(parent, agent, fork, authorize, usage_limits, max_runs = 32L)
```

## Arguments

- parent:

  Owning Agent.

- agent:

  Standalone empty child Agent.

- fork:

  A host-selected ContextFork.

- authorize:

  Function receiving the portable fork snapshot and returning the exact
  current `owner_id`, `conversation_id`, `branch_id`, and `revision`
  record.

- usage_limits:

  Cumulative UsageLimits ceiling for the retained handle.

- max_runs:

  Maximum explicit continuations, default 32.

## Value

An owner-local retained conversation handle.
