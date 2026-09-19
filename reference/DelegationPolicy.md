# Bind host policy and resources to delegated agents

A host-only, read-only policy for
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md).
It is runtime configuration, not model input or portable session state.
Callback environments remain owned by the host; fresh conversations do
not isolate their state.

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

  `"shared"` borrows definition and skill tool closures without closing
  them. `"exclusive"` borrows them while holding a process-local lease
  on `resource_key`; overlapping delegations fail before dispatch.
  `"owned"` uses `resources` to construct tools for each child.
  Definition tools and tools in skills are prohibited in this mode.

- resource_key:

  Required non-empty host identifier for exclusive resources. Hosts
  sharing a resource across leads must use the same key. This is a
  process-local concurrency guard, not a cross-process lock or access
  grant.

- resources:

  For owned mode, `function(agent, definition, context)` returning
  [DelegationResources](https://jameshwade.github.io/deputy/reference/DelegationResources.md).
  The fresh child supplies public identity and workspace APIs for
  constructing an
  [RSession](https://jameshwade.github.io/deputy/reference/RSession.md)
  or
  [McpConnection](https://jameshwade.github.io/deputy/reference/McpConnection.md).
  Do not start a run or mutate the child's policy, hooks or registry in
  the factory. Clean up partial construction on error before returning.
  Named MCP selections in definitions require this factory; delegation
  never opens a package-global MCP connection.

- human_input:

  Optional `function(questions, context)` used to rebind an explicitly
  selected local `ask_user` tool. It receives current Agent, session,
  run, parent and delegation identifiers, plus host scope and run
  context. It does not add a tool or approve an action. Without it,
  selecting `ask_user` fails before dispatch; the process-global
  fallback is never used by children.

- observers:

  Additional lead hook event names to forward live to children.
  `PreToolUse`, `PostToolUse`, and `PostToolUseFailure` always apply.
  Other lead observers are opt-in. `PermissionRequest` and delegation
  lifecycle events cannot be forwarded. The child has its own registry;
  forwarding shares the host callbacks explicitly, without cloning their
  captured resources.

## Value

A read-only `DelegationPolicy` S7 object.

## Details

Children keep the lead's admission-time permission ceiling and recheck
its current restrictions before each tool call. Definition restrictions
also apply to factory, skill and MCP tools. Provider-native tools are
rejected because Deputy cannot interpose on their execution. Workspaces
and checkpoint journals are shared with the lead; this policy provides
no OS sandbox.

Child durable approval/continuation is not supported yet. A lead
configured with `approval_dir` rejects delegation before resource
construction or provider work. A permission callback returning
[PermissionResultPending](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md)
in a child rejects the operation without executing it. Supplied text
cannot grant approval. Use the existing
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) approval
APIs for standalone approval workflows.

Stateless parallel responders receive governance but never invoke
resource factories or acquire tools, interactive handlers, or exclusive
leases. The initial
[DelegationManifest](https://jameshwade.github.io/deputy/reference/DelegationManifest.md)
records the effective binding without callbacks.
