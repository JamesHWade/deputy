# ADR-0019: Bind child governance and resource ownership

Status: Accepted for implementation in #151.

## Decision

`LeadAgent(delegation_policy = DelegationPolicy(...))` performs one host binding
before dispatch. Its portable projection is `DelegationManifest$policies$binding`.
The model cannot provide the policy, resource factory, handler or approval store.
Definition files remain inert and use the existing explicit host registries.

Every child keeps its admission-time permissions and definition restrictions.
Before each tool call it also checks the lead's current static permissions. The
original permission callback remains attached to the child, with child correlation.
These checks precede child permission-request hooks. Narrowing the lead while a
child is active cannot leave the child's old static authority effective.

The live lead registry supplies PreToolUse, PostToolUse and PostToolUseFailure
callbacks. These are shared host callbacks, not cloned resource environments.
Their normal matching, first-result, timeout and error semantics remain unchanged.
Other lifecycle observers are opt-in through `observers`; the binding records the
selected events. PermissionRequest is not forwarded because it can override a
permission denial. SubagentStart/Stop describe the lead's delegation boundary and
are not forwarded as child lifecycle events. A fresh child registry does not
import arbitrary lead observers. Native provider tools fail preparation because
the runtime cannot interpose on their effects.

## Resource ownership

- `shared` (the compatibility default) borrows definition/skill tool closures.
  They may capture shared mutable state. Deputy does not close them.
- `exclusive` borrows those closures under a process-local `resource_key` lease.
  Concurrent admission with that key fails; there is no hidden queue. Hosts using
  the same resource in multiple leads must use the same key. Direct host use and
  other processes are outside this lease, which grants no authority.
- `owned` calls a trusted host factory with a fresh Agent, definition and routing
  context. It returns `DelegationResources(tools, cleanup)`. This supports public
  `RSession$new(agent)` and `McpConnection$new(..., agent)` ownership checks.
  Definition/skill tool closures are disallowed in owned mode. MCP definition
  selections require an owned factory instead of a package-global connection.

Factories construct resources, not runs. They clean up their own partial failure
before returning. After a valid resource value returns, Deputy retains cleanup
before validating/registering its tools. Normal settlement, cooperative
cancellation, later preparation failure and unused batch preparation all release
runtime-owned resources once. Cleanup errors remain in `cleanup_error` separately
from execution errors. All exclusive leases release even if cleanup fails.
Borrowed resources are never closed by delegation cleanup.

The workspace and checkpoint journal remain shared with the lead. R workers have
independent process state, but neither fresh Chat history nor this binding is an
OS sandbox. Arbitrary factory code and borrowed closures are trusted host code.
Stateless fan-out does not invoke factories, acquire exclusive resources or gain
tools/handlers; it receives only applicable governance and context policy.

## Human input and approvals

A selected local `ask_user` is rebound to `human_input(questions, context)` with
current child Agent/session/run/delegation/parent identity, immutable run context
and host scope. The callback replaces any captured handler; the process-global
fallback is unavailable. Selecting the tool without a handler rejects preparation.
The host authenticates owners and routes the request; identifiers are locators,
not credentials. Scope and run context remain separate host-owned records.

Durable delegated approval and continuation are deliberately unsupported here.
Configuring `approval_dir` on a lead rejects delegation before resource/provider
work. A child callback returning PermissionResultPending stops without an effect;
brief text or human answers do not approve it. Standalone Agent approval APIs keep
ADR-0016's journal and current-policy checks. #152 owns in-process continuation;
#42 owns durable tree recovery and transitive budgets. Neither is silently enabled
by forwarding an approval directory to a child that cannot be resumed safely.

## Validation

Public API fixtures cover concurrent owner handlers and permission callbacks,
lead hook vetoes, current-policy narrowing, shared closure state, cross-lead
exclusive contention/recovery, owned resource cleanup on setup failure and
cancellation, stateless non-acquisition, real ellmer R worker calls, owned MCP
selection, and unapproved effects. Tests use ellmer 0.5.0; MCP worker integration
uses one of the adapter's explicitly qualified mcptools releases (1.0.2, 1.0.3).
