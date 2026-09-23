# deputy

A provider-agnostic framework for building agentic AI workflows in R, built on ellmer. This glossary fixes the vocabulary used in issues, commits, and documentation.

## Language

### Agents

**Agent**:
The runtime object that drives a conversation with an LLM, executes tool calls, and enforces permissions. Always the R6 object, never a spec or a role.
_Avoid_: assistant, bot, LLM

**AgentDefinition**:
A declarative specification of an agent — name, prompt, tools, model, skills — loaded from a Deputy definition file or constructed in code. A definition is not runnable on its own; it describes an Agent that a LeadAgent can instantiate.
_Avoid_: agent config, agent spec, custom agent

**LeadAgent**:
An Agent that can delegate work to subagents. The only kind of Agent that acts on an AgentDefinition.
_Avoid_: orchestrator, supervisor, parent agent

**Subagent**:
An Agent instantiated by a LeadAgent to carry out one delegated task, with its own conversation and its own permissions. Subordinate for the duration of the delegation only.
_Avoid_: child agent, worker, sub-agent (hyphenated)

**Delegation**:
The act of a LeadAgent handing a task to a subagent and receiving its result.
_Avoid_: dispatch, handoff, spawning

### Conversation state

**Run**:
One invocation of an Agent against a task, ending when the model stops, a limit is reached, or it is interrupted. An Agent may perform many runs over its lifetime.
_Avoid_: execution, invocation, call

**Turn**:
A single exchange within a run — one model response and any tool calls it requested.
_Avoid_: step, iteration, round

**Conversation snapshot**:
The serialized contents of an Agent's selected conversation and model context,
written to and read from disk by `save_session()` and `load_session()`. Concerns
what was said, not who is saying it. The host owns durable storage and branches.
_Avoid_: session, session file, saved session, conversation state

**Compaction**:
Replacing older turns in model context with a summary to reduce input size.
The complete selected conversation remains available through `get_turns()`;
`get_context_turns()` exposes only the current model context.
_Avoid_: truncation, pruning, summarization

**Checkpoint**:
A recorded state of the files in the workspace, restorable by rewinding. Concerns the filesystem, never the conversation.
_Avoid_: snapshot, save point

### Control

**Tool**:
A function exposed to the model, carrying a description and annotations that declare its effects.
_Avoid_: function, capability, action

**Tool annotation**:
A declaration of a tool's effects — whether it reads only, destroys, reaches outside the workspace, or is safe to retry. Annotations are what permissions reason about; they describe the tool, not the caller.
_Avoid_: tool metadata, hints, flags

**Permission mode**:
The policy governing which tools an Agent may call in a run.
_Avoid_: security level, access mode, sandbox mode

**Trusted-code tool**:
A tool that executes model-supplied R or shell code with the current user's
authority. A separate process may improve fault isolation, but does not make
the code untrusted or confined.
_Avoid_: sandboxed tool, safe execution

**Trusted tool**:
The one tool an Agent's `TrustedResults` policy designates to produce a named
kind of result. Its verbatim return value reaches the host as a
`trusted_result` event and callback before any model output. Registration
fails when another tool could bypass it (ADR-0030).
_Avoid_: safe tool, verified tool, authoritative model output

**Trusted result**:
The value a trusted tool returned, together with its result ID, type, tool
call and arguments. It is host evidence, not model text; a receipt may stand
in for it in the conversation.
_Avoid_: answer, model result, summary


A platform-enforced boundary that constrains an already authorized process.
Deputy delegates this boundary to mcp-repl and verifies the requested policy;
permission modes do not substitute for it.
_Avoid_: permission mode, subprocess isolation

**Hook**:
A callback fired at a named point in an Agent's lifecycle, able to observe a run and, at some points, alter or block it.
_Avoid_: callback, middleware, listener, interceptor

**Callback result**:
A read-only S7 decision returned by a hook or permission callback. Concrete
HookResult and PermissionResult classes carry continuation, denial, context,
and presentation fields. The Agent and HookRegistry interpret these values;
nested output objects retain their own reference semantics (ADR-0015).

**Approval continuation**:
A durable Deputy control record for one pending tool operation. It carries the
source correlation, saved authority, observed usage, host decision, and completed
effect journal. Inspection does not execute tools; only a pending record can be
consumed under current authority. Its supporting transcript uses the existing
session payload and ellmer content records. The host owns conversation
associations and reconciliation of indeterminate effects (ADR-0016).
_Avoid_: saved coroutine, conversation database, exactly-once execution

**Hook event**:
The named lifecycle point a hook is registered against.
_Avoid_: trigger, lifecycle stage

**Skill**:
A read-only configuration value bundling prompt text, tools, and metadata that
can be loaded into an Agent to specialize it. Executable tools retain their
caller-owned state.
_Avoid_: plugin, extension, module, capability pack

**DelegationInput**:
An immutable task-specific brief: task, constraints, evidence references,
deliverable and stop conditions. Evidence selects exact revisions from a scoped
host snapshot; instructions do not grant authority.

**DelegationManifest**:
An immutable receipt for a delegation's prepared initial context, including
resolved evidence and declarative policy fingerprints. It is distinct from the
current working context, retained child transcript and provider wire framing.

## Delegation host binding

`DelegationPolicy` is host runtime configuration for child governance, interactive
routing and shared, exclusive or owned resources. `DelegationResources` transfers
cleanup responsibility for factory-created tools to one delegation. These runtime
objects are separate from the portable binding receipt in `DelegationManifest`.

### Delegation inspection

`DelegationOutcome` separates bounded model answers and claims from execution
facts. `DelegationDisclosure` is the host authorization/redaction boundary for
child snapshots and artifacts. A saved child history is read-only public ellmer
evidence, never a continuation or an access grant. See ADR-0020.

`DelegationObservation` bounds a lead's transient event stream. A
`DelegationSubscription` is an authorized read cursor, not a job, conversation
owner or cancellation handle. Gaps require snapshot recovery.
