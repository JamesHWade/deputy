# ADR-0021: Bounded child observation independent of execution

Status: Accepted for implementation in #157.

## Decision

Append public AgentEvents to one bounded in-memory lead buffer. Never hand child
generators to consumers and never invoke subscriber callbacks from execution.
DelegationSubscription owns a cursor and authenticated host context; snapshot,
poll and close are synchronous read/detach operations. Each read reauthorizes and
redacts. Host redactors must not yield or drive execution.

Snapshots copy child records at a cursor boundary before disclosure callbacks.
Per-stream sequences, independent cursors, explicit eviction gaps and oversized
content omissions support reconnect without silent loss. Filters preserve child
identity while conservatively reporting stream-level gaps. Defaults are 256
records, 1 MiB aggregate and 64 KiB per envelope. Conversation retention remains
separate. Foreign/future cursors fail; clones receive fresh stream identities.

Native public ellmer Content records preserve tools and attachments. Hidden
thinking, transport objects and callback closures never enter the observation
buffer. The existing tool-call record suppresses duplicate callback/stream start
events. No tool execution is duplicated. Internal observation failures are retained
separately and cannot prevent settlement or resource release. Host redaction
failures leave the cursor unchanged and do not affect execution.

The delegation `settled` envelope follows final governance status; child `stop`
is a separate earlier run event. IDs and ancestry are locators, not authority.
Fixture lineage may be nested, but recursive execution and durable recovery stay
with #42. Targeted interruption is a separate trusted host control method; view
selection, closure and replay never invoke it or imply approval/continuation.
