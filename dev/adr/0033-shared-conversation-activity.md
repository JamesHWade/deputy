# ADR-0033: Descendant tool activity in the shared conversation

Status: accepted for implementation in #238. Builds on ADR-0017, ADR-0021,
ADR-0022 and ADR-0032.

## Context

posit-dev/shinychat#423 and posit-dev/commons#398 ask for one user-facing
conversation that shows the tool calls of every subagent, with their actual
results, and that replays faithfully from saved history, while each
specialist keeps its own model context. Commons relies on those visible,
deterministic tool cards to tell people which numbers came from a trusted
calculation. Before this decision the lead's chat showed only the delegation
call; descendant calls were visible in a separate panel (ADR-0022).

shinychat 0.5.0 derives both its live rendering and its saved UI from ellmer
contents: `chat_append()` renders each streamed content with
`contents_shinychat()`, and history records `client$get_turns()` with
`contents_record()` and rebuilds each saved message from those turns. Anything
not in the client's turns is lost on reload, and the public API cannot insert
into an earlier message.

## Decision

- **Activity lives in the lead's user-facing transcript.** ADR-0017 already
  separates `get_turns()` (the selected conversation) from the model context.
  When activity is shown, each descendant call becomes an inert
  `ContentToolRequest` and `ContentToolResult` pair, marked with a versioned
  `deputy_activity` record in `extra`, appended to the lead's assistant turn
  that holds the depth-one delegation call. `get_turns()` merges these pairs
  into the transcript, and `last_turn()` into the turn it returns; the wrapped Chat, `get_context_turns()`, provider
  requests, usage counts and compaction never contain them. `set_turns()` and
  context forks separate marked contents again, so a restored shinychat
  conversation or a copied history cannot hand them to a model; a fork given
  portable records (`ellmer::contents_record()`) finds the marker in the
  records, before a sanitized replay would clear it. `save_session()` keeps
  the shown cards beside the turns (`activity`: each card with the index of
  its turn), never among them, and `load_session()` restores them after
  checking each is a marked card in one of the loaded assistant turns; a
  malformed entry fails the load before anything changes. `set_chat()` keeps
  each card with its turn when moving drops an assistant turn that held only
  reasoning. Replacing the
  conversation (`set_turns()`, or a successful `load_session()`, which drops
  the previous conversation's cards) restarts the presenter's queue, labels and counts, and drops
  results a stopped presenter left for the reply streaming; that reply's
  calls are no longer shown, since they belong to the replaced conversation.
  Clones do not inherit the presenter.
- **Identity is the delegation and the call's place in it.** An activity ID
  is `deputy_activity_<key>_<n>`, where `key` is an opaque token drawn once
  per delegation and `n` numbers the delegation's own tool requests in the
  order they are first shown (turns before the delegation are excluded, so a
  retained specialist's earlier history doesn't shift it). A call keeps its
  number from one poll to the next by its provider ID, tool and arguments, so
  a redaction that later hides an earlier call can't move a later call onto
  its card. Identical calls are told apart by what their cards show: a call
  still running, or one whose result no identical card has shown, takes the
  earliest card still waiting; then a call whose result an identical card has
  shown takes a waiting card if one is left, since a redaction that hides one
  of two identical calls far more often hides the earlier, finished one. A
  call no card matches as shown keeps its card by provider ID and tool alone
  when no other request in the delegation's record or in the view has them,
  so a redactor that shows a call's arguments or result differently from one
  view to the next doesn't give it a second card; the card then follows the
  call as shown (a provider ID reused within the delegation still needs the
  arguments to match). The record is read only for this count, never shown. A
  shown call that the view no longer includes is closed with a note when the
  delegation settles. shinychat pairs request and result by
  that ID, so concurrent children, repeated specialist names and provider
  tool-call IDs reused across conversations cannot collide, and the ID reveals
  nothing a redactor removed. The marker keeps the provider-independent
  lineage (agent, conversation, delegation, parent delegation, depth, run and
  the root tool call) as the redacted view reports it; the root tool call
  comes from the depth-one delegation's redacted view.
- **Attribution goes in the activity row label.** The display keeps the tool's
  own title, icon and HTML. `label` names the subagent by the name its
  redacted view gives; later delegations to the same name are numbered and a
  descendant names its parent ("reviewer (via analyst)") when its redacted
  view still reports one. The label is worked out again from each read's
  redacted view, so a redactor that stops showing the name or the parent
  stops them appearing on later cards; the number is drawn once, for the name
  first shown, and is used only while the view still shows that name. An
  ancestor's part of a descendant's card (the parent's label, the lead's
  call ID) comes from the ancestor's view as read for the same refresh, never
  an earlier one, so a viewer or redaction that changed while the ancestor's
  record stood still sees only what it allows now.
- **The consumer side computes it.** `Agent$stream_async(stream = "content")`
  merges activity into the lead's stream only while a presenter is enabled. It
  races the lead's next chunk with a short timer; on each tick it reads the
  delegation records through the lead's `DelegationDisclosure` (authorize, then
  the host's `redact`, on a view shaped like an inspection view with only the
  delegation's own turns) and yields new cards. Before it yields any tool
  result, and when the reply ends, it rereads every open delegation, so all of
  a delegation's cards precede its result. Runtime execution remains the only
  consumer of each child stream; reading never runs a tool or resumes an agent.
  Disclosure errors leave the lead's run untouched and show no activity. A
  redacted view over the disclosure's `max_bytes` is not read further: its
  calls already shown get a "Not shown" result and one note card says the rest
  aren't shown. Each card is bounded on its own as well: arguments to 16 KiB,
  a result value to 256 KiB, an error to 4 KiB, a label to 1 KiB and the tool
  name to 256 bytes, so many delegations can't each fill a card up to
  `max_bytes`.
- **Nothing is left running in saved history.** A call whose delegation
  settles without a result, or that is still open when the lead's reply ends,
  gets a "Not completed" result card; one still open when the presenter stops
  (its `stop()` or the Shiny session ending), or when the reply ends and the
  records can't be read (access withdrawn, a redactor that fails), gets a
  "Not shown" result, which a reply still streaming also receives. Each reply shows at most 256 calls; a marker card
  replaces the rest.
- **Display HTML is inert before it is stored.** Cards go through the adapter
  allowlist of ADR-0032 before they enter the transcript, because shinychat
  replays stored UI without the adapter.
- **The public entry point is the optional Shiny adapter.**
  `subagent_chat_activity(chat, lead, requester)` checks that `chat` is the
  `chat_server()` result whose client is `lead`, enables the presenter and
  disables it when the session ends. A lead has one presenter: enabling a
  second before the first stops is an error, since it would show the same
  calls again under new keys and leave the first one's cards running. Each
  `stop()` stops only its own presenter. A reply's stream reads and drains
  only the presenter it started with: once that presenter stops, the stream
  gets the "Not shown" results it settled for that reply and reads nothing
  more, so a presenter shown during a reply (with its own requester) shows
  cards from the next reply on, and never in a stream it didn't start.

Tool-call correlation also stopped assuming provider IDs are unique within a
run: a finished call no longer claims a later call with the same ID, which
providers that number calls per response produce. Durable approvals keep
refusing a reused ID within one continuation, as before: their effect receipts
are keyed by tool-call ID across suspension and resume, where only the
provider's ID comes back.

## Consequences

- One conversation shows every descendant call, live and after reload, through
  public shinychat rendering. Request/result pairing and display survive
  because the saved turns contain them.
- The lead's `get_turns()` grows by the shown cards while a presenter is in
  use. Hosts that copy that transcript into another Chat must pass it through
  an Agent's `set_turns()` or drop marked contents; `get_context_turns()` is
  the model's view.
- Activity from runs the host starts directly (`continue_agent()` outside a
  lead reply, `parallel_delegate()`) has no reply to attach to and stays in the
  subagent panel and records.
- Token-level streaming of descendants (posit-dev/shinychat#378) remains
  separate; the panel's partial-output preview is unchanged.
