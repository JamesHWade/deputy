# Stateless fan-out uses governed asynchronous child runs

Issue #39 separates one-request, tool-free responders from future tool-using
background agents. The first tier is a host API on LeadAgent:
`parallel_delegate(tasks, max_active = 2, mode = "stateless")`, plus an async
method returning a promise. Tasks select unique registered AgentDefinitions.
Definitions containing tools, skills, or MCP servers are rejected. Each child
has fresh history, a fresh session, no automatic context compaction, and at
most one model dispatch. Explicit definition memory and initial prompts remain
part of its supplied context. Stateless describes execution, not absence of
host-supplied context.

## Backend decision

The original issue proposed `ellmer::parallel_chat()` for tier 1. The released
[bulk helper](https://ellmer.tidyverse.org/reference/parallel_chat.html) manages
its own request loop around one Chat prototype. Inspection of ellmer 0.5.0
shows that loop also invokes tools directly. Since Deputy now has a governed
async kernel, routing through the bulk loop would require a second lifecycle
and accounting adapter. Instead each responder uses `Agent$run_async()` and
the batch joins its promises. This supports the released ellmer 0.4.2 minimum
and 0.5.0 without adopting an unreleased concurrency API.

Model runs and batches share run initialization and finalization. A batch
owns the lead's active-run slot but does not alter its conversation. Child
definitions retain the lead's permission ceiling. Inherited Chats are deep
cloned; copied tool callback managers are cleared before the child Agent
binds its own runtime callbacks. The definition supplies the complete child
tool registry. All children are prepared before the first provider dispatch,
so invalid configuration cannot lose already-paid sibling responses.

## Scheduling and accounting

The scheduler uses bounded waves. A wave reserves its request slots before
dispatch, divides remaining token/cost ceilings, and waits for settlement
before scheduling more work. Children receive at most one request and zero
tool calls. Their limits use stop behavior so sibling results survive; the
aggregate honors the caller's stop/error preference. Failed dispatches count
toward requests even if no assistant turn was recorded. Missing cost data is
unknown, and a configured cost ceiling fails closed.

Token/cost caps are observed limits, not provider preflight estimates. A wave
may overrun by one response per active child. Cancelling a batch stops queued
work immediately and requests cooperative cancellation from active children;
cleanup waits for them to settle. There is no process kill or provider request
refund guarantee. Reservations are released on all worker exits.

Each outcome retains its input key, status, result, and condition. Partial
failures do not discard siblings. Child runs retain existing correlation,
SubagentStart/Stop hooks, and inspection APIs. The aggregate has its own
AgentResult and usage events. Synthesis is an explicit later run with an
explicit separate budget.

## Deferred boundary

There is no `mode = "agentic"`, tool-using parallel worker tier, persistent
inbox, wake scheduler, cross-run budget, or transitive agent tree in this
change. Issue #42 tracks background-agent lifecycle and transitive limits.
Issue #40 builds an opposing-perspective example on the completed tier-1
contract. The wave scheduler is deliberately small; a continuously replenished
queue or provider-specific rate limiter can follow measured need.
