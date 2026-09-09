# Preserve the selected conversation independently of model context

Accepted for implementation 2026-09-09; issue #146.

## Problem

An Agent implements ellmer's Chat interface for hosts including shinychat.
Previously its `get_turns()` forwarded the wrapped Chat's working context.
Compaction could shrink a 46-turn conversation to four turns. shinychat's native
history appends new turns after the length of its selected branch, so later
completed replies could remain visible while never reaching durable history.
An explicit history save used the same view and did not repair the omission.

## Decision

`Agent$get_turns()` and `turns()` return the complete selected conversation.
`get_context_turns()` returns the current model context, which may shrink.
Providers, context estimation, usage, compaction, and run accounting continue to
use the wrapped Chat. Retention does not add old turns to provider requests.

When compaction successfully replaces a context prefix with a summary, Deputy
retains that prefix in memory. It uses the accepted compaction plan rather than
trying to rediscover newly completed turns from the current context length.
Failed or cancelled compaction does not add a prefix. Repeated compaction appends
only newly removed turns; the retained suffix is never copied into the prefix.
Archived tool requests retain their public evidence and display metadata but
lose executable tool references. Completed tools are never replayed by retention.

`set_turns()` replaces the selected conversation and working context together,
clearing the former prefix and summary. This supports host branch selection,
new conversations, and native history restoration through the existing public
Chat protocol. Clones have independent prefixes and context. `last_turn()` reads
the complete selected conversation, including after all model turns compact.

Snapshot schema 3 stores `compacted_turns` and working `turns` separately. The
loader validates retained turns before changing live state and restores both
views only after successful installation. As with previous development schema
changes, older schemas are rejected rather than presented as complete history.
Existing native host history remains owned and readable by that host. Restore
it through the host and write a new snapshot when upgrading.

## Ownership and limits

ADR-0003's host-owned storage boundary remains. This is one in-memory selected
path, not a conversation database, branch tree, identity service, or retrieval
API. Hosts own persistence and access control. A host may persist snapshots
explicitly; Deputy does not open a history store or call private shinychat APIs.
Headless shinychat branching remains a separate upstream question under #66.

Retaining history uses memory proportional to the selected conversation and
increases snapshot size. `ContextPolicy(max_tokens)` bounds model input, not
history memory. Applications choose conversation lifetime and storage limits.
Restoring a transcript or snapshot does not restore permissions, grant approval,
or resume live tools. Internal recovery-catalog retirement continues to follow
live model references; retaining the display transcript does not pin superseded
internal catalogs indefinitely.

## Verification

A real ellmer HTTP fixture and shinychat's native file store reproduce the old
loss with 46 initial turns, repeated automatic compaction, and two later tool
exchanges. Tests require all 54 turns after save/switch/restore, smaller provider
requests, unchanged tool-effect counts, native branch editing and navigation,
fresh-session restoration, and workspace-scope isolation. Runtime-only tests
cover both views, empty context, cloning, replacement, snapshot validation, and
saved native plot evidence without executable tool references. A durable approval
regression compacts an already completed effect, pauses a later effect, restores
display evidence without consuming approval, then explicitly resumes once.
Approval records encode both turn lists as portable ellmer records and replay
the compacted prefix without executable tools.

The native store integration is optional: tests skip it when the installed
shinychat lacks its public history exports. Core transcript behavior is covered
on released ellmer 0.5.0 without that development-only host feature.
