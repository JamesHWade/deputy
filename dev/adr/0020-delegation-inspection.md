# ADR-0020: Compact outcomes and authorized child inspection

Status: Accepted for implementation in #153.

## Decision

Keep one lead model conversation and independent child conversations. The
ordinary delegation tool emits bounded JSON from a read-only DelegationOutcome;
stateless batches expose the same values alongside existing AgentResults.
Runtime status/identity never means task success, verification or approval.
Model answers and optional structured claims occupy separate fields.

Large answers use existing ContextPolicy artifacts, preserving source child,
run, parent tool call, storage session and host scope. Tool-result offloads retain
child/tool provenance. References are locators. The model projection caps answers
at 8 KiB, claims at 2 KiB per field and references at eight; omissions are explicit.
Host inspection keeps the retained reference set and checks storage availability.

DelegationDisclosure authorizes against fixed host scope before lookup and
redacts before delivery. It defaults to deny. Host authentication, trusted source
history and application policy remain external. Existing low-level getters are
host APIs, not end-user disclosure endpoints. Artifact chunks pass through the
same disclosure policy and must appear in the authorized redacted child view.

Native ellmer contents_record/contents_replay supply the portable history
contract. Replay uses a closed set of public content constructors and no tools.
Provider JSON, hidden thinking, tool closures and arbitrary UI extras are omitted.
Saved history is observational and settled; replay cannot resume a child. Hosts
supply current authorization and trusted scope independently of saved metadata.
Snapshots are bounded; exceeding the host byte ceiling fails explicitly.

## Consequences

A selected-child panel can render public ellmer turns without appending them to
the lead. Observation (#157), rendering (#158), continuation (#152), durable job
recovery (#42) and rich-widget persistence (#144) remain distinct contracts.
Current children have one run, so per-run and cumulative child usage coincide.
Missing storage is explicit, and saved availability is never considered current.
