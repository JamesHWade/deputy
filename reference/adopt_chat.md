# Turn an ellmer chat into a retained agent

Copies a configured ellmer chat into a new agent that `owner` keeps for
later calls, for example through a
[`delegation_tool()`](https://jameshwade.github.io/deputy/reference/delegation_tool.md).
The copy keeps the provider, model settings, system prompt, tools and,
optionally, turns, but drops callbacks such as `on_tool_request()`; the
new agent's permissions and hooks apply instead. The original chat is
unchanged but shares its tools, and any state they hold, with the copy.
To keep an existing `Agent`, use `owner$retain_agent()`. See
[`vignette("retained-agents")`](https://jameshwade.github.io/deputy/articles/retained-agents.md).

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

  A configured ellmer `Chat`.

- owner:

  The [Agent](https://jameshwade.github.io/deputy/reference/Agent.md)
  that will own and call the new agent.

- permissions:

  [Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
  for the new agent. The owner's current permissions also apply to every
  call.

- usage_limits:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for all calls combined.

- history:

  `"retain"` to copy the chat's turns, or `"fresh"` to start with an
  empty history.

- callbacks:

  Must be `"replace"`, to confirm that the chat's callbacks are dropped.

- name:

  Optional display name for the new agent.

- max_runs:

  Maximum number of calls. Defaults to 32.

## Value

A handle for
[`delegation_tool()`](https://jameshwade.github.io/deputy/reference/delegation_tool.md)
and for `owner`'s `$continue_agent()`, `$cancel_agent()` and
`$release_agent()`. It only works with `owner`.
