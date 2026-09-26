# Permission callbacks refine the policy in every mode

Decision date: 2026-09-26. Replaces the callback override that ADR-0010
retained; the rest of ADR-0010 stands.

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

## Decision

- Every mode evaluates in the same order: tool gating, the permission prompt
  tool, mode and capability checks, then the callback. The callback runs only
  for calls that are already allowed. Allow keeps the decision; deny and
  pending replace it; any other value or an error denies with a warning.
- The internal tool-result reader keeps its allowlist exemption and stays
  vetoable, because it takes the same path.
- `PermissionRequest` hooks remain the explicit way to allow a denied call.
- Readonly and plan modes allow a LeadAgent's own `delegate_to_agent` tool.
  The runtime identifies it by a private marker, as it does the tool-result
  reader, because any registered, skill or MCP tool can use the same name;
  those gain nothing. `delegation_tool()` and graph route tools are
  unchanged: readonly mode allows them only through `tool_allowlist`, and
  plan mode denies them because they are not annotated read-only.

## Consequences

- A callback that relied on allow to bypass capability checks now sees those
  calls denied before it runs. Hosts widen the capability flags, or use a
  `PermissionRequest` hook to allow individual denied calls.
- Plan and full policies can deny calls through the callback and suspend them
  with `PermissionResultPending()`.
- Provider-native tools remain incompatible with any callback.
