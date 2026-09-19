# ADR-0024: Owned in-process conversation continuation

Status: implemented for #152; consumed by curated composition (#168).

An Agent owns retained specialist handles in a private instance-local registry.
`retain_agent()` transfers execution ownership of a standalone Agent and keeps
its selected conversation, provider, prompt and executable registry. No definition
is reconstructed and no package-global conversation cache is introduced. Handles
are opaque locators: another Agent cannot resolve them. These are trusted host
control APIs; applications authenticate and authorize user control requests before
routing them. Disclosure uses the independent `DelegationDisclosure` policy.

`continue_agent_async(handle, task, usage_limits)` takes a new bounded brief and an
explicit allocation. It returns the promise to await. The synchronous counterpart
waits on the same promise. One lease is acquired before returning; busy follow-ups
reject. The runtime alone drains the governed stream. Direct runs and delayed
streams created before ownership transfer cannot bypass the owner. Neither side
may be cloned while retaining a conversation.

Public history, prompt, model and tool-registry mutations also reject while the
conversation is retained, including through pre-existing Agent aliases. Release
the idle handle before changing its configuration or loading another session.
Governed execution and automatic compaction use the internal runtime paths.

Each continuation has a new delegation and run identity, with a predecessor link;
Agent and session identity stay stable. The existing lifecycle, observation ring,
authorized snapshots, and child panel work on ordinary Agents as well as leads.
Runtime completion remains distinct from task success. Per-invocation transcript
snapshots retain what was visible at settlement, and cumulative usage is separate
from the new invocation's usage.

Budgets intersect the requested allocation, specialist run ceiling, remaining
handle lifetime ceiling, and the caller's unreserved allowance. Reservations are
made before dispatch. Failed requests count, missing cost fails closed, and
observed token/cost limits retain the one-response overshoot semantics of the
existing runtime. Continuation does not reset lifetime usage. A host may explicitly
release and adopt again with a new ceiling; that is a new host authorization, never
a model-facing budget reset.

Both specialist policy and the caller's current policy govern child tools. Caller
PreToolUse/PostToolUse/PostToolUseFailure hooks are forwarded through a temporary
registry while preserving specialist hooks. Changed prompt/provider/registry
configuration between calls rejects until explicit re-adoption. Runtime compaction
and its internal reader remain part of the retained conversation. Tool closures
and their resources are borrowed: the host must keep them alive and their own
closed-resource checks remain authoritative. Deputy never imports another owner's
resource lease. Mutable host closures are not a sandbox or a credential boundary.

Cancellation is cooperative, idempotent, and never schedules a retry. A failed or
cancelled conversation can be explicitly continued with the preserved partial
history. It provides no process-kill or refund guarantee. Owner interruption also
asks active children to stop. Parent completion does not release idle specialists.
A new owner run cannot start while independently launched children remain active.

Retention is bounded to 32 live handles per owner and a host-specified finite
invocation count per handle (32 by default). `release_agent()` invalidates an idle
handle and removes its invocation snapshots; export any needed history first.
The bounded observation ring may retain events until eviction. Host-owned artifacts
and borrowed resources follow their own retention rules. Without release, handles
last for the owning object's lifetime. There is no timer, background job, automatic
continuation, or promise of survival across R restart.

Durable approval, fallback provider changes, recursive ownership, and LeadAgent
specialists are rejected in this first increment. Approval suspension must use the
standalone approval protocol. Recursive admission and transitive budgets remain
#169; restart recovery remains #42. Existing AgentDefinition delegation still
creates fresh children by default.
