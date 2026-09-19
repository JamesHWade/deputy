# ADR-0022: Optional child conversation inspection

Status: accepted for implementation in #158, layered on #153 and #157.

## Decision

Provide `subagent_chat_ui()` and `subagent_chat_server()` as an optional Shiny
module. The host composes it beside its lead chat and supplies authenticated
request context. Core delegation does not depend on Shiny or shinychat.

The module reads authorized snapshots and bounded event cursors. Runtime code
remains the only consumer of the child generator. Selection and replay cannot
run tools, change the lead's context, approve an action or continue a child.
Closing a view releases its cursor. Explicit cancellation delegates to a
separately authorized host callback.

Use released shinychat 0.5.0 public content conversion and message APIs. Group
adjacent assistant content, including tool results carried by user turns, to
preserve native request/result pairing. Render assistant Markdown with commonmark,
then use xml2 and htmltools to rebuild an inert HTML tree with allowed tags and
URL schemes. This preserves literal characters in code and typed attachments.
Native plain-text user messages, tool values and errors stay in their text/code
rendering paths. Scoped CSS hides the
composer; no prompt handler is installed. Do not use private shinychat state or
copy its renderer. Native nested tool streams remain an upstream concern.

Reauthorize and reapply redaction on every poll, including without new runtime
events. Clear cached choices, cards and transcripts when access fails. Saved
history is reauthorized against an independent trusted host scope and is always
read-only. Buffer gaps recover via retained snapshots; missing references,
unknown cost and unresolved model claims remain explicit.

## Consequences

Hosts retain ownership of identity, access policy, durable storage and action
authorization. The adapter supports optional UI packages without broadening the
runtime's dependency boundary. Browser tests must cover native cards and
attachments, safe markup, concurrent/repeated children, lifecycle failures,
selection, cancellation, replay and denied access. Synthetic nested lineage can
be inspected; real recursive lifecycle and durable recovery remain #42.
