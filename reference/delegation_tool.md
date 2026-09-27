# Create a tool that calls a retained agent

Lets `owner`'s model send a task to a retained agent. The model writes
only the task; you control the rest, including the agent's model,
prompt, tools and budget. Each call continues the same conversation,
like `owner$continue_agent()`, and returns a
[DelegationOutcome](https://jameshwade.github.io/deputy/reference/DelegationOutcome.md)
as JSON. Use the owner's inspection methods, such as
`$inspect_subagents()`, for the full history.

## Usage

``` r
delegation_tool(owner, handle, name, description, usage_limits)
```

## Arguments

- owner:

  The [Agent](https://jameshwade.github.io/deputy/reference/Agent.md)
  that owns the retained agent. Register the tool on this agent only.

- handle:

  Handle returned by
  [`adopt_chat()`](https://jameshwade.github.io/deputy/reference/adopt_chat.md)
  or `owner$retain_agent()`.

- name:

  Tool name, unique among the owner's tools.

- description:

  Tells the model when to use this agent.

- usage_limits:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for each call. A call also can't exceed the retained agent's remaining
  budget or the calling run's.

## Value

An ellmer tool. Calling it outside a run of `owner`, or registering it
on another agent, is an error.

## Details

The retained agent keeps its own permissions, and each of its tool calls
is also checked against the owner's current permissions. An owner in
read-only or plan mode can use the tool, and the retained agent is then
held to that mode too.
