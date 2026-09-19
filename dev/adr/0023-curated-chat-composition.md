# ADR-0023: Curated chat composition and bounded recursion

Status: curated composition implemented in #168 with ADR-0024 ownership.
Recursive execution remains tracked in #169.

## Problem

Will Landau's September 3 ellmer proposal starts with existing, heterogeneous,
carefully configured chats. Deputy's AgentDefinition path instead constructs a
fresh specialist from configuration. That path remains useful, but it does not
satisfy the requested small composition primitive. The descendant-stream request
also needs real recursive execution; synthetic lineage is only a renderer test.

## Decision

Design a small host-created delegation tool around an existing governed Agent,
with explicit adoption of a host-supplied ellmer Chat as a convenience. The caller
registers that tool on its orchestrator. Agent and LeadAgent stay the runtime
facades; the adapter must reuse their run, permission, budget and observation
machinery rather than introduce another executor. The exported adapter uses an Agent owner and an opaque retained handle:

```r
specialist <- adopt_chat(curated_chat, owner = orchestrator,
  permissions = permissions_readonly(), usage_limits = UsageLimits(max_requests = 8),
  history = "retain", callbacks = "replace")
tool <- delegation_tool(orchestrator, specialist, name = "analyst",
  description = "...", usage_limits = UsageLimits(max_requests = 2))
orchestrator$register_tool(tool)
```

Adoption must preserve the selected provider, model parameters, system prompt,
explicit executable registry and retained conversation. Any governing wrappers
and callback ownership must be explicit. Unsupported provider-native capabilities
fail closed when Deputy cannot interpose. A fresh copy is a separate host choice;
a model cannot request prompt replacement, new tools or a provider change.

The handle contract belongs with #152: one owner, one active-run lease per mutable
conversation, explicit release, expiry and continuation. A follow-up makes a new
run and delegation record while retaining conversation identity. Busy handles
reject; no implicit queue or interrupt-and-inject behavior is promised. Existing
specialist authority intersects with current caller authority. Usage is retained,
and root allocations prevent continuation from resetting the budget.

The runtime alone consumes a child's generator. Observers receive bounded,
authorized event envelopes and recover gaps through retained snapshots. The tool
returns a compact serializable result. A UI subscription, selection or replay
never advances execution or confers permission.

## Recursion is a separate in-process increment

#169 owns bounded recursive execution and descendant observation within one R
process. The root owns depth, admitted-child, concurrency and transitive usage
limits; each descendant records its parent delegation/run/tool call. Admission
reserves capacity before dispatch. Cancellation reaches queued and active
descendants, preserving partial results and terminal records.

A real three-level fixture and browser demonstration must show every descendant
without consuming any stream twice. Separate selected-child panels satisfy this
contract. Native live nesting inside shinychat tool cards is optional and remains
upstream work; its absence must not block separate descendant inspection.

#42 owns persistence, restart recovery and external-effect reconciliation. It
builds on the same bounded tree contract but no longer gates in-process recursion.
Neither a saved transcript nor an in-process handle promises restart recovery.

## Delivery and evidence

1. #154 demonstrates reviewed inputs and tool-owned authoritative results using
   the current public runtime, without claiming child approval continuation.
2. #168 implements curated composition with #152 ownership/continuation rules.
3. #169 implements bounded recursive execution and observable descendants.
4. #42 adds durable recovery; #155 evaluates quality and cost separately.

The trusted example uses a child only to propose inputs, then a separate
host-owned Agent for durable approval and computation. Existing child binding
rejects durable approval suspension, so this handoff is explicit. Its result
receipt records the proposing delegation and the execution Agent separately.

Sources refreshed 2026-09-19:
- https://github.com/tidyverse/ellmer/issues/821#issuecomment-5528123668
- https://github.com/posit-dev/shinychat/issues/378
- https://trustedminiagents.dev/definition.html
