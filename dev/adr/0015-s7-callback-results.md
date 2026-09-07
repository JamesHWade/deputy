# Use S7 values for hook and permission callback results

Status: Accepted

## Decision

HookResultPreToolUse, HookResultPostToolUse, HookResultPreCompact,
PermissionResultAllow, and PermissionResultDeny are Deputy-owned S7 values.
Their existing function names and argument order remain the constructors.
HookResult and PermissionResult are abstract S7 bases for family membership;
use `S7::S7_inherits()` with the concrete class to select a decision type.
They do not inherit ellmer classes or expose an S3 list compatibility API.

Every stored property is read-only after construction, including properties
initialized to NULL. Read through `@`, `S7::prop()`, or `$`; `$` returns NULL
for absent fields, as existing cross-event hook consumers require. Obtain a
plain record with `S7::props()` and construct a new value to revise a decision.
Freezing protects supported property updates, not arbitrary attribute tampering.

Continuation and interruption flags must be single non-missing logical values.
Text fields must be a single non-missing string; optional text also accepts
NULL, and empty strings remain valid. A denial requires its reason argument.
PreToolUse permission retains `match.arg()` behavior, including its allow
default and unambiguous abbreviations. PostToolUse suppress_output retains
`isTRUE()` coercion. These constructors reject malformed control fields before
runtime consumers encounter them. Errors raised inside hooks or permission
callbacks still follow their existing error handling paths and error classes.

The arbitrary updated_tool_output payload retains the original R object.
Environments, conditions, functions, and ellmer objects inside that property
keep their own semantics and reference identity. Results do not copy, invoke,
serialize, or close those objects during construction.

## Lifecycle boundaries

Agent and HookRegistry remain mutable R6 owners. The registry still returns
its first non-NULL callback result, without globally coercing or restricting
other event-specific callback protocols. PreCompact's existing plain-list
cancellation and summary path remains available. The typed PreToolUse,
PostToolUse, and PermissionRequest branches now test S7 class membership.
The custom permission callback accepts PermissionResult family values;
untyped or legacy S3 lookalikes follow its existing invalid-result denial.

Permission ceilings, callback vetoes, interruption, request overrides, tool
rejection, hook-requested stops, compaction cancellation, custom summaries,
and error logging retain their runtime interpretation. PostToolUse replacement
and suppression continue to affect Deputy's emitted tool_end event, without
rewriting ellmer's model-visible tool result.

## Serialization and verification

RDS retains concrete and family membership, property reads, and frozen state
when Deputy is loaded in the receiving process. Serializable object graphs
retain shared references within that process; this is not a portable transport
for live connections or services. Timed HookRegistry callbacks use the existing
callr subprocess and must load or qualify their package dependencies.

Focused tests cover malformed constructor fields, immutable decisions, original
payload references, permission callback rejection, hook error handling, and
existing lifecycle scenarios. Fresh-process tests verify RDS and the real timed
registry path. R CMD check repeats these against the installed package. Public
examples and vignettes show property inspection without a provider call.
This completes the value families listed in #119; mutable runtime owners retain
reference identity.
