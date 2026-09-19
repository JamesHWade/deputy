# Delegate through a host-curated specialist

Register this tool only on its owning Agent. The model supplies a new
task brief; ownership, provider, prompt, tools and budgets are fixed by
the host. Every call uses the same continuation implementation as host
follow-ups. Results are compact serializable delegation outcomes; full
child history and live activity use the owner's independently authorized
inspection APIs.

## Usage

``` r
delegation_tool(owner, handle, name, description, usage_limits)
```

## Arguments

- owner:

  The [Agent](https://jameshwade.github.io/deputy/reference/Agent.md)
  owning the retained conversation.

- handle:

  Handle returned by
  [`adopt_chat()`](https://jameshwade.github.io/deputy/reference/adopt_chat.md)
  or `owner$retain_agent()`.

- name:

  Unique tool name selected by the host.

- description:

  Description telling the caller when to use the specialist.

- usage_limits:

  Explicit per-invocation allocation, intersected with the remaining
  conversation and caller budgets.

## Value

An ellmer tool. Direct calls outside its owner's governed tool runtime
reject. Registering the tool on another Agent also rejects.
