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
  into the transcript; the wrapped Chat, `get_context_turns()`, provider
  requests, usage counts and compaction never contain them. `set_turns()` and
  context forks separate marked contents again, so a restored shinychat
  conversation or a copied history cannot hand them to a model. Clones do not
  inherit the presenter.
- **Identity is the delegation and the call's position in it.** An activity ID
  is `deputy_activity_<key>_<n>`, where `key` is an opaque token drawn once
  per delegation and `n` counts the delegation's own tool requests in order
  (turns before the delegation are excluded, so a retained specialist's
  earlier history doesn't shift it). shinychat pairs request and result by
  that ID, so concurrent children, repeated specialist names and provider
  tool-call IDs reused across conversations cannot collide, and the ID reveals
  nothing a redactor removed. The marker keeps the provider-independent
  lineage (agent, conversation, delegation, parent delegation, depth, run and
  the root tool call) as the redacted view reports it.
- **Attribution goes in the activity row label.** The display keeps the tool's
  own title, icon and HTML. `label` names the subagent by the name its
  redacted view gives; later delegations to the same name are numbered and a
  descendant names its parent ("reviewer (via analyst)").
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
  redacted view over the disclosure's `max_bytes` is not read further: one
  note card says its calls aren't shown.
- **Nothing is left running in saved history.** A call whose delegation
  settles without a result, or that is still open when the lead's reply ends,
  gets a "Not completed" result card. Each reply shows at most 256 calls; a
  marker card replaces the rest.
- **Display HTML is inert before it is stored.** Cards go through the adapter
  allowlist of ADR-0032 before they enter the transcript, because shinychat
  replays stored UI without the adapter.
- **The public entry point is the optional Shiny adapter.**
  `subagent_chat_activity(chat, lead, requester)` checks that `chat` is the
  `chat_server()` result whose client is `lead`, enables the presenter and
  disables it when the session ends.

Tool-call correlation also stopped assuming provider IDs are unique within a
run: a finished call no longer claims a later call with the same ID, which
providers that number calls per response produce.

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
