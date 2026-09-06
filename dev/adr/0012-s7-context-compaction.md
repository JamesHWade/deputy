# Use S7 values for context policy and compaction outcomes

Decision date: 2026-09-06. Baseline: `f7c3417`.
Issue: [#123](https://github.com/JamesHWade/deputy/issues/123), a bounded slice of
[#119](https://github.com/JamesHWade/deputy/issues/119).
Builds on [ADR-0009](0009-s7-value-contracts.md) and
[ADR-0011](0011-s7-usage-limits.md).

## Decision and interface

`ContextPolicy(...)` and `DeputyCompaction(...)` are Deputy-owned S7 classes
with read-only stored properties. ContextPolicy retains its constructor
arguments and defaults. The exported DeputyCompaction constructor replaces the
internal S3 list constructor; Agent compaction methods and PostCompact hooks
return this same value. There is no parallel S3 constructor or R6 facade.

`$`, `S7::prop()`, and `@` read properties. `S7::props()` returns a plain list
for deliberate reconstruction or reporting; it is not a recursive serializer.
The shared frozen marker protects both initialized and NULL properties,
including bulk updates and nested list replacement. Printing retains stdout,
cli formatting, and invisible return.

Context thresholds remain positive whole numbers or NULL, compact_to remains
a fraction strictly between zero and one, and offload paths are anchored at
construction. Compaction outcomes validate the existing method vocabulary,
logical automatic flag, nonnegative turn counts, optional token estimate,
optional scalar summary and run ID, and AgentUsage type. Their timestamp is
created once. Unknown summary costs remain unknown.

## Runtime and provider boundaries

A read-only policy does not make an ellmer Chat immutable. The policy constructor
clones caller templates after checking that they have no turns or tools.
Agent construction and its policy getter reconstruct the value and clone its
templates again. Thus mutations of a caller's original template, a standalone
policy's nested Chat, or a returned policy snapshot do not change the Agent's
configured destinations. A standalone `S7::props(policy)` projection retains
its nested Chats' reference semantics.

Automatic summary dispatch still clones the selected Chat and clears history,
tools, system prompt, and inherited callbacks. Ordered summary fallbacks remain
separate from task fallbacks, and summary selection does not change the active
task Chat. Manual compaction retains its existing active-Chat/text fallback
behavior. No provider, callback, retry, cancellation, permission, or scheduling
logic changes in this migration.

Compaction usage composes AgentUsage directly. Summary attempts remain ordinary
records of fallback index, provider, model, usage, and original condition.
Conditions and any embedded reference objects retain their own semantics;
Deputy neither subclasses nor rewrites producer evidence. Attempt-list copies
can be edited independently, but reference objects inside them are not deep
frozen. Consumers must choose which evidence to persist or disclose.

## Persistence and validation

RDS round trips of data-only context policies and compaction outcomes preserve
S7 identities, frozen NULL properties, timestamps, unknown usage costs, and
original condition data. Fresh-process tests load Deputy before reading the
values; R CMD check exercises the same test against the installed package.
Policies containing live Chats are runtime configuration, not a portable
credential or client transport contract.

Session schema 2 continues to store turns, installed summary, and recoverable
evidence; it does not store context policy, fallback destinations, or the last
compaction value. Loading a session retains the receiving Agent's policy.

The external history-recovery evaluation now projects compaction properties
before cleaning attempts and projecting nested usage for JSON. It still records
condition classes instead of complete provider conditions. Its deterministic
paired scenarios verify compaction and attempt usage after JSON round trip.

Focused regressions cover construction, replacement rejection, independent
property-list edits, template isolation, original condition identity, and fresh
process dispatch. Existing real-ellmer fixtures verify summary callbacks,
fallback selection, fail-closed behavior, cancellation, budget settlement,
completed tool effects, evidence catalogs, and session restoration. Full tests,
R CMD check, documentation builds, and remote CI verify the delivered commit.
