# Permission callbacks refine the policy in every mode

Decision date: 2026-09-26. Replaces the callback override that ADR-0010
retained; the rest of ADR-0010 stands. Amended 2026-09-27 (#227): readonly and
plan modes also allow `delegation_tool()` and graph route tools.

## Context

`Permissions(can_use_tool = )` meant something different in each mode. In
standard mode an allow was final and skipped the capability and annotation
checks, so a callback written to add one rule widened the policy as soon as it
returned `PermissionResultAllow()` for everything else: `run_r_code` ran with
`r_code = FALSE`, and writes escaped the `file_write` directory. Readonly mode
treated the callback as a veto. Plan and full modes never called it, so a
denial or a durable `PermissionResultPending()` configured on those policies
had no effect. The documented workaround called `permissions_check()` on a
copy of the policy without the callback.

Readonly and plan modes also denied the lead's own `delegate_to_agent`, even
though a definition cannot use a less strict mode than its lead and every
child tool call is rechecked against the lead's current policy. Read-only
reviews had to use standard mode with `file_write = FALSE` to delegate.

Retained specialists had the same problem. `delegation_tool()` and graph route
tools are annotated `read_only_hint = FALSE`, so readonly mode allowed them
only through `tool_allowlist` and plan mode denied them outright. A retained
specialist keeps its own policy, which may be wider than its owner's, but each
of its tool calls must also pass the owner's current policy (ADR-0024), and in
a graph every ancestor's (ADR-0025).

## Decision

- Every mode evaluates in the same order: tool gating, the permission prompt
  tool, mode and capability checks, then the callback. The callback runs only
  for calls that are already allowed. Allow keeps the decision; deny and
  pending replace it; any other value or an error denies with a warning.
- The internal tool-result reader keeps its allowlist exemption and stays
  vetoable, because it takes the same path.
- `PermissionRequest` hooks remain the explicit way to allow a denied call.
- Readonly and plan modes allow an agent's own delegation tools: a LeadAgent's
  `delegate_to_agent`, and the `delegation_tool()` and graph route tools that
  call its retained specialists. The runtime identifies each by a private
  marker, as it does the tool-result reader, because any registered, skill or
  MCP tool can use the same name; those gain nothing. The lead's marker counts
  only on a tool named `delegate_to_agent`; the composition marker needs no
  name check because hosts name those tools.
- This cannot widen what runs. Every tool call a subagent makes is checked
  against its lead's current policy, and a subagent cannot use a less strict
  mode. Every tool call a retained specialist makes is checked against its
  owner's full current policy, including the callback, and in a graph against
  every ancestor's. A retained specialist cannot be a LeadAgent, hold
  delegation tools or own conversations, and graph members own no nested
  registries, so no descendant escapes those checks.

## Consequences

- A callback that relied on allow to bypass capability checks now sees those
  calls denied before it runs. Hosts widen the capability flags, or use a
  `PermissionRequest` hook to allow individual denied calls.
- Plan and full policies can deny calls through the callback and suspend them
  with `PermissionResultPending()`.
- An owner in readonly or plan mode can call its retained specialists. A
  `tool_allowlist`, if set, must still include the tools, and the deny list
  and the callback can still block them. Continuing a specialist spends its
  budget and extends its history, which readonly mode does not prevent.
- Provider-native tools remain incompatible with any callback.
