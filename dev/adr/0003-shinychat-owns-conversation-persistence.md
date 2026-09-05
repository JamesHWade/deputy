# Hosts own conversation persistence

Revised 2026-09-05: shinychat integration is optional. Its upstream history API
discussion does not block Deputy implementation or evaluation.

The host owns durable conversation history, identity, branch selection and
storage. Deputy consumes the selected context and owns permissions, run limits,
execution state and session snapshots. A host using shinychat can retain
shinychat's conversation format and branch semantics when a supported adapter
is available.

## Why

An Agent's compacted context and session snapshot are not a complete conversation
archive. A host must retain original evidence independently if later runs need
to recover it. Coupling this boundary to an unreleased shinychat API would block
headless workers and history-recovery work that already runs with caller-owned
records and released ellmer APIs.

The original decision chose shinychat as the universal persistence owner. This
revision retains host ownership without requiring every host to use that store.
It does not introduce a Deputy conversation database or copy shinychat's tree.

## Implementation boundary

- Continue bounded recovery with caller-owned records, as exercised in
  `inst/examples/history-recovery/`. This example is the current producer, not
  a new public persistence API.
- The host binds owner, conversation, Agent and selected branch before exposing
  history tools. Stable source IDs and revisions support stale-reference checks;
  reads preserve provenance and enforce per-response and aggregate budgets.
- Retrieved history supplies evidence. Current host policy supplies execution
  authority; conversation text and saved metadata cannot restore permissions.
- `Agent$save_session()` and `load_session()` remain supported execution
  snapshots. Removed turns are recoverable only if the host retained them
  independently. Session IDs and host conversation IDs require explicit mapping.
- Branch restoration and hosted resume must be proved against the chosen host's
  history producer. The recovery fixture alone does not establish durable
  storage, branch editing or restart behavior for a production host.

## Optional shinychat integration

Await the upstream outcome tracked in #66 and
[`dev/shinychat-history-consumer.md`](../shinychat-history-consumer.md). Only the
adapter is gated on a supported, released public R contract and focused
integration tests under ADR-0004. Use public APIs; do not depend on private tree
fields or store helpers. A future adapter must preserve the same authorization,
revision and bounded-read behavior as other host-supplied history.

Implementation and evaluation under #112 can proceed independently. Live-model
quality conclusions still require authorized repeated trials; removing the
shinychat prerequisite does not supply that evidence.
