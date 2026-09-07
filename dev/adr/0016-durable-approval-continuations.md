# Durable approvals are control state

Deputy persists pending tool decisions in a small control envelope. The host
continues to own its conversation archive, identity, branch selection, private
storage and retention under ADR-0003. An approval is neither a saved coroutine
nor permission reconstructed from a transcript.

## Producer and consumer

An Agent configured with an existing `approval_dir` runs tools sequentially.
Its `can_use_tool` callback may return `PermissionResultPending(reason)` for a
tool or custom policy gate. A limit encountered at a pending tool boundary also
suspends for a budget decision. `approval` events expose the stable approval ID,
path and tool-call ID; `pending_approval()` and `approval_read(path)` return
read-only S7 inspection values. Reading a record does not load a Chat or run a
tool. Permission callbacks in `mode = "full"` retain their existing bypass
semantics; use a constrained mode for approval gates.

`Agent$resume_approval()` accepts `approve` or `deny`, optional edited inputs,
and optional explicit `UsageLimits`. The host reattaches the Chat, raw-argument
tool definitions and required permission callback. Saved and current static
permission ceilings both apply before the current callback and hooks. Tool
name, schema, source body/formals, conversion and metadata must match the saved
fingerprint. Captured closure state remains the host's responsibility; a
fingerprint does not establish that an external service or resource is unchanged.

Provider-native tools are rejected when durable approvals are enabled because
Deputy cannot journal or gate their execution inside the provider.
Resumable function tools must originally use ellmer's `convert = FALSE`. Their functions
accept raw JSON arguments and validate their own schema/domain inputs. The
durable boundary checks finite JSON-representable inputs, but does not duplicate
ellmer's private conversion machinery. It never silently changes an existing
tool's conversion setting. Unsupported runtime objects fail before persistence.
Record-shaped ordinary JSON (`version`, `class`, `props`) is rejected because
ellmer replay would otherwise reinterpret it as an S7 constructor. Structured
tool output should use `jsonlite::toJSON()`; actual ellmer Content values retain
public record/replay semantics.

## Envelope and association

The version-1 envelope contains source run/session/Agent/delegation IDs, canonical
run context, pending request identity and inputs, permission and budget ceilings,
observed usage, decisions, effect journal, and state. Transcript support is the
existing version-2 session payload with turns recorded through public
`ellmer::contents_record()` and restored through `contents_replay()`. It does not
contain executable tools, callbacks, provider clients, or promises.

A host can associate `{approval_id, path}` with its own owner, conversation,
selected branch and revision. It should supply those immutable identifiers in
`run_context`, authorize the caller against its own store, then bind the receiving
Agent to the same session, Agent, workspace and context before calling resume.
Deputy checks correlation and rejects conflicting context; correlation values
are not credentials. Delegation correlation is retained and must match the
receiving runtime. Reconstructing a LeadAgent's durable job tree remains outside
this headless API.

The embedded session is the same execution snapshot used by `save_session()` /
`load_session()`, captured before ellmer fills an interrupted batch with error
results. Loading a separately saved Chat does not consume an approval or replay
its tool. Hosts retain their complete conversation archive separately; no second
conversation tree is introduced. A shinychat adapter remains optional and must
use a supported public released contract tracked in #66, never private fields.

Session offloads and checkpoint metadata preserve serializable S3 data, including
data frames, factors, dates and custom classed lists, with their attributes.
These values stay in the session's RDS payload; transcript content still uses
ellmer's content format. Runtime objects, functions, environments and references
hidden in attributes are rejected. This is not a general object-graph snapshot.

## Effect and consumption protocol

An immutable initial revision records `pending`. Resume acquires a nonblocking
OS lock for the entire operation, checks identity and current authority, and
commits `resuming` before execution. The journal commits `executing` before each
effect and `continuing` after its result. Completed sibling results are retained;
later siblings receive explicitly unexecuted results. One complete result turn
preserves every original tool-call ID before a new model request starts.

Only `pending` can resume. Duplicate delivery, concurrent consumption, reused
tool-call IDs and repeated executed/denied operation signatures are rejected.
A new host edit is rechecked before execution. A changed pending gate produces a
new approval; the previous record points to it. No approval grants future model
operations automatically.

`completed` and `stopped` record terminal outcomes. A journal entry left in
`executing`, or an interrupted `resuming` / `continuing` state, cannot retry.
Finalization labels unresolved executing entries `indeterminate`. The host must
inspect its external effect receipt, reconcile outside Deputy, and explicitly
start any replacement workflow. The API intentionally offers no reset-to-pending
operation and makes no exactly-once claim.

Records use private directories, atomic revision commits and SHA256 integrity
checks. The latest revision contains the complete cumulative effect journal.
Superseded revisions are pruned under the writer lock after a successful commit;
old files can remain temporarily after a crash or while a Windows reader holds
one open. The store is not a historical revision archive. Each serialized revision must fit
within half of the aggregate byte limit, reserving capacity for the current and
replacement revisions together. The default 50 MiB store therefore permits a
25 MiB revision. Oversized initial snapshots are rejected before publication.
Actual growth of the journal or session can still exhaust the bound.

A reader whose selected revision was pruned retries the latest revision; a
corrupt latest revision still fails closed. Atomic rename protects against
partial writes and process interruption; no fsync/power-loss durability is
claimed. The host owns filesystem access and backups. These are trusted local R
records, not an untrusted upload interchange format.

## Usage and limits

Prior observed usage is retained across suspension. The restored pending call
is not counted a second time. By default resume keeps the suspended run's
limits. A host may explicitly increase them within both the original and current
Agent limits; it cannot grant a larger saved authority ceiling through a budget
decision. A request without sufficient allowance stays pending and can instead
be denied. Token and cost limits remain observed-response thresholds and may
overrun by one response. A model boundary without a pending tool retains the
ordinary limit-stop behavior.

## Evidence

Local real-ellmer HTTP fixtures cover batch interruption, IDs and result ordering,
approval/denial/edit, current policy, registry rebinding, budget carryover,
duplicate delivery, process restart and termination during an external effect.
Storage tests cover lock release on process exit, corrupt latest revisions,
bounded storage and failed commit preservation. These tests use released ellmer
interfaces and make no external model calls.
