# ADR-0034: Subagent records saved with the host conversation

Status: accepted for implementation in #238. Builds on ADR-0017, ADR-0020,
ADR-0022, ADR-0032 and ADR-0033.

## Context

ADR-0033 puts descendant tool cards in the lead's shown transcript, so
shinychat saves and replays them with the conversation. The rest of a child's
evidence (its task, its outcome as Deputy observed it, its full transcript with
tool displays, usage, manifest and lineage) lived only in the lead's in-memory
delegation records, so a reload kept the cards and lost the records behind
them. #238, following the subagent workflow proposals in
posit-dev/shinychat#423 and posit-dev/commons#398, asks for child records,
display evidence and lineage to persist with the parent conversation and to
restore read-only, repeating no tool.

shinychat 0.5.0 exposes `chat$history$on_save(fn)`, `$on_restore(fn)` and
`$conversation_id()`. `on_save` gets an empty list each time the active
conversation is saved (after each response and before a switch) and its result
is stored beside the turns; `on_restore` gets it back after a conversation
becomes active. Before each reply, `chat_server()` also sets the client's
`conversation_id` binding when the client has one, so in-flight work keeps the
conversation it started in. The file store writes `values` with
`jsonlite::toJSON(auto_unbox = TRUE)` and reads them with
`fromJSON(simplifyVector = FALSE)`, which loses R's types. Saved values come
back from storage Deputy doesn't control.

## Decision

- **Delegations record their host conversation.** `Agent$conversation_id` is a
  settable field, `NULL` by default, that shinychat sets before each reply.
  Admission copies the lifecycle owner's value into the delegation record as
  `host_conversation_id`; graph descendants are admitted by the root, so they
  carry the root's value. The outcome's runtime facts include it for hosts;
  the compact outcome the model reads drops it. Deputy's wrapped Chat keeps
  using the session ID for ellmer's own `conversation_id`.
- **One adapter saves and restores.** `subagent_chat_history(chat, lead,
  requester)` registers `on_save` and `on_restore`. A save exports, through the
  lead's disclosure (authorize, then `redact`), every settled delegation whose
  depth-one ancestor ran in the active conversation, after the children
  restored for it earlier, and stores them as one record. Children still
  running are named and saved next time.
- **Records are scoped to the conversation, not the process.** The record is a
  `$export_subagents()`-shaped history whose `scope` is the lead's
  `delegation_scope` plus `chat_conversation_id`. Agent and session IDs change
  on reload, so they are not part of it. Reading checks the scope and the
  conversation ID exactly and authorizes the requester against that scope.
- **A typed encoding survives any store.** The record is saved as one JSON
  string inside a versioned envelope (`format`, `version`, `codec`,
  `conversation_id`, `data`). The codec covers exactly the portable data
  inspection allows (NULL, logical, integer, double, complex, character, raw,
  lists, and names/dim/dimnames), with doubles (and each part of a complex
  number) as `%.17g` text, NA, NaN and infinities spelled out, and raw vectors
  as base64, so a round trip is exact. Decoding builds only those types; it
  never uses `unserialize()` or `jsonlite::unserializeJSON()`, which can load
  namespaces or construct closures from stored text.
- **Restore validates everything and runs nothing.** The envelope, the decoded
  record, its scope and keys, every child's settled status (where the redacted
  view still reports one) and every transcript record (through
  `inspection_replay()`) are checked before anything reads them. A
  record that fails is dropped and reported; the next save starts from the
  conversation's live children. A record from a newer format version is saved
  back unchanged and not added to. Restored records never create delegation
  records, handles or agents; they are read through `delegation_history()`,
  which authorizes again every time.
- **Bounded, with omissions counted.** `max_bytes` (16 MiB by default) bounds
  a conversation's whole record, scope and bookkeeping included, so a saved
  record is always readable; a scope alone over the bound saves no record.
  Children are also kept within what the lead's disclosure `max_bytes` lets
  `delegation_history()` replay (each view, and its transcript again as
  replayed turns). Children are kept in order; one that doesn't fit is kept
  without its transcript (`retention$transcript = "omitted"`) or left out,
  newest first if the whole record is still too large, and the record counts
  both; a child whose outcome alone is over the disclosure bound is left out
  and counted. A transcript the redactor removes, from a live child or a
  saved one, is marked and counted as omitted the same way, so
  `retention$transcript` never says `"included"` without one. Counts survive
  later saves: the record lists the live children
  it left out (running, oversized or dropped for space) by the same digest
  as its saved children. A later save counts each again from the lead's
  records while the lead still has it, and otherwise, as for another
  session's lead or a child released since, keeps it counted as left out, as
  it does saved children it drops. The disclosure budget starts from the
  empty history's own size
  (schema, scope, containers), and a record that can't fit even that saves
  nothing. A record saved under a larger disclosure bound than the lead now has
  is restored without transcripts rather than refused, with as many of its
  oldest outcomes as the current bound holds (found by bisection, since fewer
  children only make the history smaller); children listed without their
  transcripts on request stay marked `"not_requested"`. A save that fails (for
  example, a requester the disclosure refuses) keeps the last good record for
  that conversation, since shinychat rebuilds `values` from scratch on every
  save.
- **Saved children are redacted again on every save.** Children carried from
  an earlier save pass through the current `redact` before they are written
  back, so a stricter policy also cleans what is stored. Every save needs a
  requester the disclosure authorizes for the conversation's own scope, the
  one `delegation_history()` reads the record with, and, when the lead has
  live records in the conversation, for the lead's live scope as well (so a
  reopened conversation whose new lead has none saves on the first alone);
  otherwise the save keeps the last good record without showing anything to
  the redactor. Children saved under
  another scope (a lead moved since with `set_delegation_sources(scope = )`)
  are not carried, redacted or counted: the save replaces them with the
  current scope's live children. Children are matched
  across saves by a SHA-256 digest of their delegation ID, kept beside the
  views, so matching survives a redactor that removes the ID itself. A live
  child always replaces its saved copy: when it can't be saved now (running,
  or over the disclosure bound) the copy goes and the child is counted once,
  as pending.
- **The panel follows the open conversation.** `subagent_chat_server(conversation
  = )` shows live children whose `host_conversation_id` is the open
  conversation and saved children that aren't live, listing saved ones without
  transcripts and replaying a transcript only when that child is selected. It
  reads and bounds only the open conversation's live records, so other
  conversations' children can't push its list over the disclosure bound, and
  it doesn't read the lead-wide event stream, whose other conversations'
  events could; it reads the selected child's events on their own.
  Saved children are authorized for the conversation's own scope, so a
  requester the lead's live scope refuses (after a reload changed its agent
  and session IDs, say) still sees them, with no live reader, and a
  requester refused the saved records still sees the live ones.

## Consequences

- Reopening a conversation brings back its cards (ADR-0033) and the subagent
  records behind them. The model-facing delegation outcomes stay in the lead's
  model context as tool results, separate from both.
- Host-started runs (`continue_agent()`, `parallel_delegate()`) are saved with
  the conversation in `conversation_id` when they start; a host starting them
  outside a reply sets it first.
- Artifacts a child offloaded to disk are kept as references
  (`availability = "unresolved"` on replay); their bytes are not copied into
  conversation storage.
- A host that changes its `delegation_scope`, in shape or by moving the lead,
  can no longer read earlier records; the next save replaces them with the
  live children.
- Each save rewrites the conversation's whole record. Hosts with many large
  displays should lower `max_bytes` or rely on the named omissions.
