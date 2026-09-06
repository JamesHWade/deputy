# Use S7 values for usage accounting and run limits

Decision date: 2026-09-06. Baseline: `b556b2d`.
Issue: [#121](https://github.com/JamesHWade/deputy/issues/121), a bounded slice of
[#119](https://github.com/JamesHWade/deputy/issues/119).
Builds on [ADR-0009](0009-s7-value-contracts.md) and
[ADR-0010](0010-s7-results-permissions.md).

## Decision and interface

`AgentUsage(...)` and `UsageLimits(...)` are Deputy-owned S7 values with
read-only stored properties. Their constructor arguments and `$` property
reads retain their names. S7 namespaced identities replace the S3 list classes;
there are no parallel list constructors or mutable compatibility facades.
AgentResult's usage property and runtime limit checks require the S7 values.

`S7::prop()` and `@` provide property access. `S7::props()` produces a plain
named-list snapshot for reporting, JSON projection, and explicit new-value
construction. It replaces whole-object list indexing and `unclass()`; it does
not serialize class identity or automatically reconstruct a value. Stored
properties use the construction marker and setter from ADR-0009, including
initially NULL limits and the derived total-token count. Printing retains
stdout capture, cli width handling, and invisible return.

## Accounting invariants

Requests and tool calls normalize to nonnegative scalar integers within R's
integer range. Input, output, and cached token counts normalize to nonnegative
finite scalar doubles. Total tokens are computed from input plus output at
construction; cached input is recorded separately and is not added twice.
Costs are nonnegative finite doubles or `NA_real_` for incomplete provider
reporting. An unknown cost remains unknown through sums and applicable
differences, and configured cost limits still fail closed.

Provider conversation snapshots retain their internal cost-record and token
evidence attributes. These numeric records let a later run exclude incomplete
costs from earlier turns, distinguish an unreported dispatch from no new work,
and preserve a newly reported zero cost. `S7::props()` exposes only the public
metric properties. These implementation attributes are ordinary R values,
not mutable provider environments or an additional public value class.
Original ellmer turns, token evidence, and cost reports remain producer-owned.

Accounting functions construct new usage records. After context replacement,
preserved usage subtracts the authoritative runtime tool counter from its
external subtotal without changing a caller's record. Automatic compaction
counts requests at dispatch and constructs a settlement record with zero
requests before adding reported resources, so request counts are not doubled.

## Budget invariants

Limit fields retain their scalar validation and NULL-versus-zero distinction.
Merging per-run overrides constructs a new validated value: non-NULL fields
override defaults, unset fields inherit defaults, and `on_exceed` comes from
the override. This is configuration resolution, not an authority intersection.

Delegation still subtracts current usage and outstanding reservations, then
intersects the remaining request allowance with the child definition. Parallel
waves divide remaining token and cost budgets into separate child values and
release reservations on settlement. Source limits remain unchanged. Child
limits use stop behavior; the aggregate retains its configured stop/error
behavior. An Agent's default limits remain read-only after construction.

Request and tool boundaries still enforce discrete counts. Token and cost
limits remain observed thresholds: a response, or a response from each active
child in a wave, can exceed a threshold before it is reported. The S7 migration
does not introduce preflight token estimates or change this scheduling rule.

## Persistence and verification

RDS serialization preserves the S7 class, frozen properties, NULL limits,
unknown costs, nested result/event values, and internal numeric accounting
evidence. Fresh-process tests load Deputy before reading and exercising these
objects; R CMD check runs the same contract against the installed package.
Old S3 RDS records are not silently accepted as new S7 values. Callers can
construct new values from validated fields; total tokens are recomputed rather
than accepted as a separate constructor argument.

Session schema version 2 is unchanged: it persists conversation and evidence,
not usage limits or an active run's spent budget. Restoring a session keeps the
receiver's limits and obtains usage from the restored provider turns.

The external history-recovery experiment projects usage in run records, trial
rows, events, compactions, and summary attempts to plain properties before
writing JSON. Its manifest remains serializable without registering a global
jsonlite method or persisting internal provider evidence attributes. JSON
round-trip tests retain metric values and unknown costs as null rather than zero.

Regression tests cover read-only and bulk assignment, plain projections,
rejection of S3 lookalikes, unknown and zero costs, compaction accounting,
default inheritance, parallel allocation, and delegated reservations. Existing
streaming, fallback, tracing, resumed-session, and observed-limit tests exercise
the same runtime paths. The PR records local and remote validation at its exact
head using released dependencies. Remaining value families stay in #119.
