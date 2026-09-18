# ADR-0018: Explicit delegation input and initial manifests

Status: Accepted for implementation in #149.

## Decision

Keep `AgentDefinition` reusable and preserve scalar string tasks. Add the read-only
S7 `DelegationInput(task, constraints, evidence, deliverable, stop_conditions)`.
Evidence is an ordered list of `{source_id, revision}` records. Extra fields,
executable objects and multimodal payloads are rejected; this first contract
supports UTF-8 text. Stop conditions are instructions, not executable controls.

Hosts configure `LeadAgent` with `delegation_sources`, `delegation_scope` and
`delegation_max_bytes`. Scope has explicit `owner_id` and `conversation_id`.
Each source has `source_id`, `revision`, `owner_id`, `conversation_id`, `text`,
and optional `allowed_agents`. These are copied text records, not paths or URLs
to fetch. The host authenticates owners and supplies authorized source snapshots;
matching identifiers is not authentication. Revisions are exact opaque host IDs.
Revision equality and eligibility are checked against this snapshot, not an
external store. This is not a live freshness or revocation guarantee. Each source
ID has one revision per owner/conversation pair. Missing or `NULL`
`allowed_agents` allows all registered definitions; an explicit empty character
vector allows none. Refresh requires constructing a new LeadAgent. Live revocation, retrieval
callbacks, forks and durable resource ownership remain separate work (#151/#62).

Model arguments can select references but cannot supply source bodies, scope,
permissions or byte ceilings. No parent/sibling turns, executable tools,
credentials or approval state become context implicitly. Provider credentials
remain inside the selected Chat configuration and never enter a manifest.

A shared preparation module normalizes input, checks exact scope/revision and
AgentDefinition eligibility, renders the initial message, creates the Subagent,
and freezes a read-only S7 `DelegationManifest`. Ordinary delegation and parallel
batches use this module. Batches validate all selected evidence before constructing
Subagents, and prepare the entire batch before any provider request. Missing,
stale, unauthorized, invalid and oversized inputs have typed preparation errors
and retained failed records; unstarted siblings remain explicit. Once batch routing
and definitions are valid, all items are admitted before brief normalization.
Malformed or oversized items use bounded text labels in records and run events;
arbitrary input objects are never retained as event payloads.

The first user message is a single JSON object (`deputy_delegation_v1`), including
for scalar string tasks and empty evidence. Definition initial instructions,
model-supplied brief fields, and the host's `resolved_evidence` array occupy
separate properties. JSON escaping keeps forged headers, quotes and nested
objects inside their original text fields; no markdown delimiter carries
provenance. The encoded message is retained verbatim in the manifest and counted
against admission bounds. This is an unambiguous representation of host source
selection, not a guarantee about model interpretation or prompt-injection
resistance. Source text remains untrusted data and does not grant authority.

The manifest records the normalized brief, resolved source content/provenance and
SHA-256 content digests, definition prompt/static memory/initial prompt/skill
names, prepared system prompt and initial message, model, registered tool names,
and fingerprints of the effective permission and context policies. Registration
is not blanket permission. Policy fingerprints describe configuration, not a
capability or a host approval. Transient per-wave usage reservations are not
misrepresented as immutable initial authority.

Use a finite host admission ceiling (64 KiB by default) for both the serialized
manifest and the initial system/message text. Enforce input/reference/catalogue
limits before rendering. Reject rather than truncate; use existing ContextPolicy
for later model-context compaction and tool-result offloading. A public complete
context estimate is recorded when available and checked against ContextPolicy
before any paid compaction or task request. Stateless children inherit the lead's
ContextPolicy too, so their receipt and admission check use the same token cap.
Their fresh conversation and one-request usage limit remain the stateless
execution contract. Unknown estimates remain `NULL`;
byte admission still applies, with no claimed initial token bound.
No second compaction or offloading engine is introduced.

Text fields and serialized input have 1 MiB absolute ceilings; instruction lists
and reference lists allow 64 items each. A source catalogue allows 128 records
and 16 MiB in aggregate. Host admission separately bounds serialized input,
resolved sources, rendered message, combined system/message text, and complete
manifest, rejecting rather than truncating. `manifest_bytes` is the exact byte
count of `S7::props(manifest)` encoded with `jsonlite::toJSON(auto_unbox = TRUE,
null = "null", digits = NA)` in UTF-8, including its own size field.

Policy fingerprints hash canonical key-sorted JSON of explicit primitive
projections: permission mode, file read/write, bash/R/web/install settings,
allow/deny lists and permission prompt tool name; context max tokens, compact
fraction, fallback mode and text/image result bounds. They exclude permission
callbacks, fallback Chat objects, credentials and offload paths. Callback
presence is recorded separately. Equal fingerprints do not imply equal runtime
behavior or transferable authorization.

## Inspection and serialization

`get_subagent_contexts(view = "initial")` returns manifests in admission order.
`view = "current"` returns available current system prompts and working turns;
`get_subagent_messages()` continues returning retained conversation histories.
Reading these does not run a model, change context, resume work or approve tools.
Current context is retained at settlement. Unprepared records have `NULL`
manifests; records without an available child have `NULL` current context.
Status/result polling never materializes transcripts. Initial manifests do not
change after compaction. Current snapshots reflect available turns, not every
in-flight token. Hosts authorize user-facing disclosure.

The initial manifest is a preparation receipt, not the provider wire payload:
provider framing, later request hooks, compaction and tool results may change
working context. `redact = TRUE` on initial inspection returns an explicitly
redacted portable view with content removed, not a supposedly complete prompt.
The underlying manifest is retained. Metadata also needs host disclosure policy.

Input and manifest `S7::props()` contain only portable values; the manifest stores
a plain normalized input record rather than executable or nested mutable objects.
The manifest includes `schema_version = 1L`. Hosts can serialize these records
with JSON or RDS. Input reconstruction via `do.call(DelegationInput, record)`
supports JSON decoded with `simplifyVector = FALSE`; manifest records are
portable exports, with property-record reconstruction supported directly in R.
Restoring a record never installs tools, policy or runtime state;
LeadAgent conversation snapshots do not yet persist the delegation registry.

## Alternatives

A callback resolver can support current remote authorization and multiple stores,
but adds fetch limits, deadlines, async preparation and revocation semantics.
There is no concrete consumer requiring that complexity yet. Hosts can materialize
scoped evidence snapshots from their own stores without a Deputy storage adapter.
A graph of evidence, policy and brief value classes would add more constructors
without improving the common string-task path. Plain validated reference/source
records and two immutable values provide the needed inspection contract.
