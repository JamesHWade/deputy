# Start a retained agent from a conversation fork

Gives `agent` the turns in `fork` as its history and makes `parent` its
owner, as `parent$retain_agent()` does; continue it with
`parent$continue_agent()`. `agent` must be a standalone `Agent` with an
empty chat of its own and no `approval_dir` or fallback chats. It keeps
its own tools, system prompt and permissions: the fork brings only the
conversation. See
[`vignette("retained-agents")`](https://jameshwade.github.io/deputy/articles/retained-agents.md).

## Usage

``` r
fork_agent(parent, agent, fork, authorize, usage_limits, max_runs = 32L)
```

## Arguments

- parent:

  The `Agent` that will own the new conversation.

- agent:

  A new `Agent` whose agent and session IDs differ from `parent`'s.

- fork:

  A
  [ContextFork](https://jameshwade.github.io/deputy/reference/ContextFork.md).

- authorize:

  A function that receives the fork as a plain list and checks that its
  source may be used. To allow it, return a list with exactly the fork's
  `owner_id`, `conversation_id`, `branch_id` and `revision`; return
  `NULL` or `FALSE`, or throw an error, to deny it. It is called again
  before every continuation.

- usage_limits:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for all runs of the retained agent combined.

- max_runs:

  Maximum number of continuations. Defaults to 32.

## Value

A handle for `parent`'s `$continue_agent()`, `$cancel_agent()` and
`$release_agent()`. It only works with `parent`.
