# Adopt a curated Chat for owned delegation

Makes an independent conversation copy and explicitly replaces its tool
and request callbacks with Deputy governance. Provider configuration,
model parameters, system prompt and executable tools are preserved. Tool
closures remain shared host resources; copying a Chat is not a sandbox.
The original Chat is unchanged. Use `owner$retain_agent()` to transfer
an existing Agent.

## Usage

``` r
adopt_chat(
  chat,
  owner,
  permissions,
  usage_limits,
  history,
  callbacks,
  name = NULL,
  max_runs = 32L
)
```

## Arguments

- chat:

  A configured ellmer Chat with a public `clone()` method.

- owner:

  The host-owned
  [Agent](https://jameshwade.github.io/deputy/reference/Agent.md) that
  will invoke and inspect this specialist.

- permissions:

  Explicit specialist
  [Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md),
  also bounded by the caller's current policy on every invocation.

- usage_limits:

  Explicit cumulative
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for the retained handle.

- history:

  Explicit `"retain"` or `"fresh"` choice for copied turns.

- callbacks:

  Must be `"replace"` to acknowledge Deputy callback ownership.

- name:

  Optional specialist display name.

- max_runs:

  Maximum retained invocations, default 32.

## Value

An owner-local conversation handle for
[`delegation_tool()`](https://jameshwade.github.io/deputy/reference/delegation_tool.md)
and the owner's continuation, cancellation and release methods.
