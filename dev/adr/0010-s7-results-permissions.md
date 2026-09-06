# Use S7 values for completed results and permission policies

Decision date: 2026-09-06. Baseline: `980a8d9`.
Issue: [#117](https://github.com/JamesHWade/deputy/issues/117).
Builds on [ADR-0009](0009-s7-value-contracts.md).

## Decision

`AgentResult(...)` and `Permissions(...)` are Deputy-owned S7 values with
read-only stored properties. They use the shared construction marker and
setter introduced by #59, namespaced class identities, and released S7's
method registration. No R6 constructor or instance-method facade remains.

AgentResult records the outcome of a governed run. Every property is read-only,
including response, turns, events, usage, structured output, and identity
fields that were writable in the R6 representation. Runtime state stays in
Agent; callers construct a separate result when they need a different record.

Permissions records an explicit configuration. Policy evaluation is the
`permissions_check()` generic; its internal functions live separately in
`R/permission-evaluation.R`. The move retains gating precedence, native tool
identity rules, callback vetoes and overrides, conservative annotation defaults,
canonical directory grants, and the differences between permission modes.
It does not turn a value constructor into the owner of an active Agent's
permission transitions.

## Public interface

| Previous interface | S7 interface |
| --- | --- |
| `AgentResult$new(...)` | `AgentResult(...)` |
| `result$n_turns()` | `result_n_turns(result)` |
| `result$tool_calls()` | `result_tool_calls(result)` |
| `result$tool_results()` | `result_tool_results(result)` |
| `result$text_chunks()` | `result_text_chunks(result)` |
| `result$is_success()` | `result_is_success(result)` |
| `Permissions$new(...)` | `Permissions(...)` |
| `policy$check(name, input, context)` | `permissions_check(policy, name, input, context)` |
| Writable result fields | Read-only S7 properties |

Both classes retain `$` property reads for normal result inspection and policy
reporting. This method returns properties only; it does not recreate instance
methods. `S7::prop()` and `@` expose the same values. Print methods use the cli
stdout/width/invisible-return convention established in ADR-0009.

Result inspection keeps event objects intact. `result_text_chunks()` returns
`character()` when there are no text events, consistently with its documented
character-vector result. Events must be Deputy AgentEvents, while the turns
list preserves supplied provider turns without converting them to a Deputy
subtype. Costs retain incomplete totals and coverage metadata.

## Validation and ownership

Permission capability flags must be scalar non-missing logical values.
The custom callback must be NULL or a function, tool-name vectors cannot
contain missing entries, and prompt names must be scalar non-missing strings.
Existing normalization removes blank tool names and duplicates. NULL and an
empty allowlist remain distinct: NULL disables the gate; an empty list denies
all tools. The callback's result and exceptions still pass through the existing
fail-closed evaluation path.

Results validate scalar text and identity metadata, finite nonnegative durations,
event membership, property types, and canonical run context. Constructors use
the original ellmer turns, content, conditions, and usage. They do not subclass
ellmer Turn or Round because a governed run can span multiple conversation units.

Read-only stored properties block assignment, including initially NULL fields
and bulk property replacement. Extracted ordinary lists follow R value
semantics. Nested closures, environments, and other reference objects retain
their own identity; these records are not deep immutability or execution
sandboxes. Canonical run context has its own stricter value-only validation.

Agent accepts only a Permissions value and keeps its policy in private runtime
state. `set_permission_mode()` constructs a narrower value without modifying
an earlier policy held by a caller. Delegation intersects capabilities and
preserves tool restrictions, so child values cannot widen their lead's ceiling.
Direct policy replacement remains rejected by Agent's active binding.

RDS serialization preserves value class identity and configuration, including
canonical directory grants and callback closures. It does not create a new
portable authority mechanism, rebind filesystem roots, or allow a saved value
to replace an active Agent's policy. Hosts remain responsible for the authority
of new Agent construction and for executable callback state.

## Evidence and remaining scope

Existing permission, callback, mode transition, delegation, result, streaming,
and runnable-example tests exercise the new API. Added regressions cover
nullable and bulk assignment, malformed configuration, original evidence and
list copying, caller-owned callback state, and replacement attempts against
existing Agents and delegated children. Fresh-process RDS tests cover both
classes, public generics, printing, original ellmer turn identity, callbacks,
canonical grants, and assignment rejection; the same test exercises installed
packages during R CMD check.

Validation uses released ellmer 0.5.0 and S7 0.2.2. The PR records full suite,
installed-package, documentation, and remote CI results for its exact head.
The declared R 4.1 floor is unchanged; the local gates do not directly test R 4.1.

Skill, AgentUsage, UsageLimits, ContextPolicy, definitions, and other result
records remain separate migration work under ADR-0009, tracked in
[issue #119](https://github.com/JamesHWade/deputy/issues/119). Mutable runtime
owners remain R6.
