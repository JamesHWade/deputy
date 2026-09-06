# Use S7 value contracts alongside R6 runtime owners

Decision date: 2026-09-06. Baseline: `9e9aa93`.
Follow-up: [ADR-0010](0010-s7-results-permissions.md) records the subsequent
AgentResult and Permissions migration.

Issues: [#59](https://github.com/JamesHWade/deputy/issues/59) and
[#58](https://github.com/JamesHWade/deputy/issues/58).

## Decision and scope

S7 is Deputy's direction for value contracts. This change converts
`HookMatcher` and `AgentEvent` and establishes the construction, validation,
printing, and upstream composition pattern. Mutable runtime owners (`Agent`,
`LeadAgent`, `HookRegistry`, and `FileCheckpointStore`) remain R6.

Choose S7 for a consistent value model and explicit property contracts, not
because stored properties become immutable for free. The research identified
costs, and the maintainer explicitly selected the S7 direction. We accept the
small API break and do not retain parallel constructors or an S3 event variant.
Existing value types should migrate in scoped follow-ups, starting with
`AgentResult` and `Permissions`; do not introduce new S3 value classes.

## What the spike established

At the baseline, `AgentEvent` was already an S3 list, and Deputy already
imported S7. The issue's R6 event premise and package-wide guard count were not
accurate measures of this migration. See the primary sources and installed
release probes in [the research note](../s7-research.md).

Released S7 0.2.2 offers two relevant designs. A getter without a setter is
read-only, but the getter's return value is not automatically type-validated.
Ordinary stored properties retain S7 validation but are writable unless a
setter protects them. An initial getter-based conversion worked inside the R6
registry with adapters, but moved backing storage and validation into the
constructor. The final implementation instead uses stored properties.

`readonly_property()` shares one setter implementation across both classes.
A separate construction marker freezes the object only after `new_object()`
has initialized and validated its properties. A marker is necessary because
`NULL` is a valid initialized matcher pattern; testing the current property's
value for NULL would leave that field writable. The four R6 active bindings
and four private backing fields disappear, but the write guard remains as an
explicit, shared S7 policy.

Callback arity, regex validity, and finite nonnegative timeout checks remain
in the HookMatcher constructor. S7 property types do not replace those domain
checks. AgentEvent validates one nonempty type string and uniquely named
payload fields, reserving envelope names. Its type remains open to host-defined
events; this migration does not invent a closed schema for every event payload.

Read-only properties protect the public record. Extracting an ordinary payload
list yields an independent value when modified. Embedded environments,
functions, provider objects, and original conditions retain their own identity
and reference semantics. Neither S7 nor R6 freezing is an execution sandbox.

## Public interface and registry boundary

Construct a matcher with `HookMatcher(...)`, inspect properties with
`S7::prop(hook, "event")` (or `hook@event` where supported), and call the S7
generic `hook_matches(hook, tool_name)`. `$new()` and `$matches()` are removed.
All package helpers, examples, and tests use the new API. The R6 registry uses
S7 class checks and the generic; callback execution and permission decisions
retain their existing behavior.

`AgentEvent(type, ...)` keeps its constructor shape, and now returns a
`deputy::AgentEvent` with read-only `type`, `timestamp`, and `data` properties.
The payload is available through `event$data` or `S7::prop(event, "data")`.
A small `$` read method preserves convenient streaming expressions such as
`event$text`; absent payload names return NULL. This is a method on the S7
class, not a retained S3 record. Whole-event list indexing and the derived
`AgentEventText`/`AgentEventStart` tags are removed. Select events by `type` and
check their class with `S7::S7_inherits(event, AgentEvent)`.

## Compose ellmer values rather than subclassing them

Deputy events are governance/lifecycle records. An event may contain an
ellmer `Content` or `Turn`, but permission, hook, start, and stop events are
neither model content nor conversation turns. Preserve those original objects
in the payload instead of copying their fields into a Deputy superset.

The released ellmer hierarchy has no Event, Permissions, Callback, or general
record class suitable as a parent here. Its `ToolDef` extends a callable
function; a host hook is not a model-callable tool. Its `Round` represents a
conversational input/response unit; an AgentResult can span multiple turns and
governance events. Tests explicitly verify composition and preservation of
original content, turns, and conditions. See the source-backed inheritance
comparison in the research note.

Subclass an ellmer class only for a genuine new kind of its parent, with a
requirement to work through that parent's existing APIs. These Deputy classes
have their own domain identity, so their parent is `S7_object`.

## Packaging, documentation, and R versions

Both classes use `package = "deputy"`, and `.onLoad()` calls released S7's
`methods_register()`. The external `$` method is registered in a local scope
so replacement assignment does not mask the base primitive in Deputy's
namespace or confuse static analysis. Source collation loads the property helper before class
definitions. Roxygen documents constructors, extra event properties, and the
matching generic; the pkgdown reference includes the new generic.

Require S7 >= 0.2.2, the tested release. Its R >= 3.5.0 dependency does not raise
Deputy's declared R >= 4.1.0 floor. The namespace conditionally imports S7's
`@` operator before R 4.3; public examples use `S7::prop()` where necessary.
S7-aware test expectations require testthat >= 3.2.2. Local validation used
R 4.6.1, ellmer 0.5.0, S7 0.2.2, and roxygen2 8.0.0 (the repository records
8.1.0). The metadata conclusion does not certify the full dependency set on
R 4.1. Do not adopt the unreleased registration APIs from the development S7
website without qualifying that dependency separately.

## Apply the decision to the requested follow-ups

| Type | Next boundary |
| --- | --- |
| AgentResult | Migrate to an S7 run result containing original ellmer turns and Deputy events. Decide and document whether the currently writable result fields become read-only; preserve result inspection helpers, original conditions/content, and canonical run context. Do not subclass ellmer Turn or Round. |
| Permissions | Migrate the configuration to an S7 value while keeping policy evaluation explicit. Preserve canonical grants, immutable authority ceilings, mode narrowing, callback behavior, and fail-closed evaluation. Test attempted widening through delegated runs and configuration replacement. |
| Skill | Separate a declarative S7 skill contract from caller-owned executable tools and services; avoid claiming deep immutability for closures. |
| Remaining value records | Migrate usage, limits, context policy, definitions, and result records in bounded slices using the same type and ownership rules. Preserve persistence formats deliberately. |
| Mutable runtime owners | Keep R6 reference identity and lifecycle ownership. Read-only identity fields on an Agent do not make the Agent a value object. |

These are concrete follow-up scopes, not reasons to keep creating S3 values.
The current change finishes the two-class scope of #59 before broadening it.
[Issue #117](https://github.com/JamesHWade/deputy/issues/117) tracks AgentResult
and Permissions with these acceptance criteria.

## Printing decision for #58

All object summaries render with `cli::cli_format_method()` and write formatted
lines using `cli::cat_line()`. This preserves stdout capture and invisible
returns while adding width, indentation, and theme/color handling. Calling
`cli_text()` directly changed stdout capture in the initial experiment; the
regression tests caught it.

User strings enter fixed templates as interpolated values, never as templates.
Tests cover literal braces, 36-column wrapping, stdout capture, invisible
returns, and nested formatting cleanup. Non-atomic event payloads print their
class instead of trying to coerce provider/runtime objects to text. File writes,
streamed token output, and CLI prompts keep their distinct output contracts.

## Validation

Reproduce the focused migration contracts with:

```r
devtools::test(filter = "s7-values|hook|agent-result|agent-tracing|print-output")
```

`test-s7-values.R` checks immutable NULL fields, payload copying and shared
reference state, ellmer composition, and serialization followed by class checks,
printing, matching, and assignment rejection in a fresh R process. Existing
registry, governance, async, streaming, delegation, and example tests exercise
the migrated objects. Full-suite, package-check, documentation, and remote CI
results are recorded on the PR for its exact head.
