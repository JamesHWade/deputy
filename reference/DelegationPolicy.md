# Configure subagent tools, hooks and user input

Tells a
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
how subagents get their tools, which lead hooks run for subagent events,
and how subagents ask the user questions. Pass it as
`LeadAgent$new(delegation_policy = )`. See
[`vignette("delegation")`](https://jameshwade.github.io/deputy/articles/delegation.md).

## Usage

``` r
DelegationPolicy(
  resource_mode = "shared",
  resource_key = NULL,
  resources = NULL,
  human_input = NULL,
  observers = character()
)
```

## Arguments

- resource_mode:

  How subagents get their tools. `"shared"` (the default) uses the tool
  objects from the definition and its skills directly, so any state they
  hold is shared between subagents. `"exclusive"` does the same, but
  only one delegation at a time may hold `resource_key`; an overlapping
  one fails before it starts. `"owned"` calls `resources` to build new
  tools for each subagent, and the definition and its skills may not
  have tools. Deputy never closes shared or exclusive tools.

- resource_key:

  Resource name for `"exclusive"` mode, required there and not allowed
  otherwise. Leads sharing a resource must use the same key. The lock
  works within one R process only.

- resources:

  For `"owned"` mode, a `function(agent, definition, context)` that
  builds tools for the new subagent `agent` (for example with an
  [RSession](https://jameshwade.github.io/deputy/reference/RSession.md)
  or
  [McpConnection](https://jameshwade.github.io/deputy/reference/McpConnection.md))
  and returns them, with a cleanup function, as
  [DelegationResources](https://jameshwade.github.io/deputy/reference/DelegationResources.md).
  Don't run or modify `agent`; Deputy registers the tools itself. If the
  function fails, it should first clean up anything it created.
  Definitions with `mcp_servers` need this mode.

- human_input:

  Optional `function(questions, context)` that answers `ask_user`
  questions from subagents whose definition includes that tool.
  `context` holds the subagent's IDs, the lead's `delegation_scope` and
  the run context. Return the answers or a promise of them;
  [`AskUserDeferred()`](https://jameshwade.github.io/deputy/reference/AskUserDeferred.md)
  isn't supported. Without it, delegating to a definition with
  `ask_user` fails. Subagents never use
  [`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md).

- observers:

  Extra hook events for which the lead's hooks also run when a subagent
  fires them. The lead's `PreToolUse`, `PostToolUse` and
  `PostToolUseFailure` hooks always do. `PermissionRequest`,
  `SubagentStart` and `SubagentStop` can't be added.

## Value

A `DelegationPolicy` object.

## Details

A subagent never has more permissions than the lead had when the
delegation started, and each of its tool calls is also checked against
the lead's current permissions. `disallowed_tools` also removes tools
from skills and `resources`. Provider-native tools, such as a provider's
built-in web search, aren't allowed because Deputy can't check their
calls. Subagents share the lead's working directory and file
checkpoints; this is not an OS sandbox.

Subagents can't pause for durable approval: a lead with `approval_dir`
can't delegate, and a
[PermissionResultPending](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md)
result for a subagent's tool call rejects the call. Use a standalone
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) for
durable approvals.

Subagents started by `$parallel_delegate()` have no tools, so
`resources`, `human_input` and `resource_key` don't apply to them.
