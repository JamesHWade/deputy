# Subagent chats: current ellmer and shinychat direction

Checked 2026-09-17 against live GitHub issue bodies, comments, timelines, releases,
and pinned source. This is source/API research, not a running UI verification.

## What Will Landau is asking for

- [ellmer #821, Subagent ideas](https://github.com/tidyverse/ellmer/issues/821)
  was opened by Hadley Wickham on 2025-10-31 and remains open. The recent material
  is Will Landau's [September 2 comment](https://github.com/tidyverse/ellmer/issues/821#issuecomment-5516269236)
  and [September 3 clarification](https://github.com/tidyverse/ellmer/issues/821#issuecomment-5528123668).
  Will already composes chats as asynchronous tools. The missing pieces are
  streaming child output during execution and routing it to appropriate UI.
  Simply returning `stream_async()` from a tool fails because a coroutine
  generator is not a serializable tool result. His preferred composition retains
  a finite collection of curated heterogeneous chats, their system prompts, and
  tools that must be explicitly enabled. He wants a small delegation primitive,
  not automatic reconfiguration of each specialist by the lead model.
- In a [September 2 reply](https://github.com/tidyverse/ellmer/issues/821#issuecomment-5516644738),
  Garrick Aden-Buie pointed to btw's subagent tools and continuation and explicitly
  supported shinychat subagent streaming on an **unofficial** roadmap. This is
  maintainer intent, not an implemented contract or delivery promise.
- [shinychat #378, Subagent token streams](https://github.com/posit-dev/shinychat/issues/378)
  was opened by Will on 2026-09-03, last updated September 10, and remains open
  with zero comments. It asks to expose nested children at arbitrary depth. The
  example currently shows delegation tool blocks but no child activity inside.
  Current issue metadata has Priority: Low. The inspected timelines for #821 and
  #378 do not identify an implementation PR; #821 cross-references #378.
- Adjacent [ellmer #1152](https://github.com/tidyverse/ellmer/issues/1152), opened by
  Will on September 15, requests provider-native server compaction and remains
  open with zero comments. It is a distinct context-maintenance concern and must
  not block child chat inspection or imply provider compaction already exists.

## Released capability versus proposed work

Latest release verification: [ellmer 0.5.0](https://github.com/tidyverse/ellmer/releases/tag/v0.5.0)
was published September 4; [shinychat R 0.5.0](https://github.com/posit-dev/shinychat/releases/tag/r/v0.5.0)
September 13. Current heads were ellmer `b6a8bbd4ced3922cf9397b392db6a3259ce19478`
and shinychat `88f7625846b096b6e0b2f88358969b854602e022`.
The [ellmer release comparison](https://github.com/tidyverse/ellmer/compare/v0.5.0...b6a8bbd4ced3922cf9397b392db6a3259ce19478)
changes model data and exact matching, not the chat/content integration files;
the [shinychat release comparison](https://github.com/posit-dev/shinychat/compare/r/v0.5.0...88f7625846b096b6e0b2f88358969b854602e022)
is only a development version bump. Using development versions alone does not
provide the nested streaming feature.

Available public seams:

- ellmer's [`Chat$stream_async(stream = "content")`](https://github.com/tidyverse/ellmer/blob/v0.5.0/R/chat.R)
  yields public Content objects. Public tool request/result and request start/end
  callbacks are available. Deputy can own consumption and forwarding while
  preserving the typed payload; it need not reach into private Chat state.
- [`ContentToolResult`](https://github.com/tidyverse/ellmer/blob/v0.5.0/R/content.R)
  supports a model-visible value and additional metadata. A child generator must
  be consumed by an execution owner, and its final serializable outcome returned
  to the lead. Streaming delivery is a separate observation channel.
- shinychat's public [`tool_result_display()` and `contents_shinychat()`](https://github.com/posit-dev/shinychat/blob/r/v0.5.0/pkg-r/R/contents_shinychat.R)
  support compact labels/previews and detailed settled results, without changing
  the value sent to the model. The former preserves native tool cards; the latter
  allows custom content rendering. Neither promises live arbitrary nested chats.
- Public [`chat_ui()`, `chat_append()`, and `chat_append_message()`](https://github.com/posit-dev/shinychat/blob/r/v0.5.0/pkg-r/R/chat.R)
  can render separately addressed chat elements. The released
  [`page_chat()` and drawers](https://github.com/posit-dev/shinychat/blob/r/v0.5.0/pkg-r/NEWS.md)
  provide a natural host surface for a selected child conversation. A Deputy
  adapter using those APIs is feasible but still needs implementation and browser
  verification; source availability is not proof of that integration.

## Recommended Deputy story

These are our design recommendations, not claimed upstream agreements.

**One lead conversation; inspectable child conversations.** The user sees compact
child activity in the lead, with task, named specialist, lifecycle, and outcome.
Opening a child shows its own messages and tools in a drawer or adjacent panel,
with a breadcrumb or tree for deeper descendants. Avoid recursively embedding
complete chats in every tool card. The lead model receives only the agreed compact
outcome and selected evidence; revealing a child to the user does not insert its
transcript into the lead's model context.

**Deputy owns execution and lineage.** Retain separate identifiers for definition,
child conversation/instance, delegation attempt, run, parent delegation, and parent
tool call. A resumed child can have one conversation and several delegation/run
identifiers. A Shiny output ID is only a rendering target; a provider tool-call ID
is not a globally unique conversation ID. None of these identifiers authorizes
inspection, cancellation, or follow-up.

**Keep child Content intact inside a runtime envelope.** Extend the existing
AgentEvent/stream pipeline with ordered child events containing lineage,
per-stream sequence/cursor, event kind, and public ellmer Content or lifecycle
payload. One consumer owns the child generator and fans observations out to
subscribers; two independent consumers must not race over it. Define bounded
buffering, slow/disconnected observers, and unsubscribe behavior. Closing an
inspection panel must not cancel execution. Cancellation is a separate explicit
control governed by ownership and scope.

**Observation is not context selection or approval.** Runtime events, retained
transcripts, resolved input manifests, and working model context must stay
separately queryable. Apply host authorization and redaction before disclosure,
including hidden instructions, sensitive tool inputs/results, and provider thinking
content. Default to useful task/status/content views and expose additional detail
only when authorized. Tool-produced authoritative outputs remain distinguishable
from model commentary, following the mini-agent recipe.

**shinychat owns presentation, the host owns durable history.** Use public content
renderers and native tool cards rather than reproducing their markup or depending
on private branch/store helpers. Store serializable transcript/event references
and stable lineage, not a live generator or UI closures. Opening a historical
child is read-only replay and never silently reruns or resumes it. Durable live
recovery remains #42; owner-checked continuation remains #152.

## Backlog adjustments and ship boundaries

- **#150:** Land normalized lifecycle/live records now. Preserve delegation and
  parent identifiers needed for the observation API, without pretending status
  visibility alone delivers live child chats.
- **#149:** Include a separate inspectable input manifest and context/history
  distinction. Do not make UI disclosure implicitly copy context or widen tools.
- **#153:** Cover settled child transcript inspection and compact outcome cards
  with public ellmer/shinychat content APIs. Add explicit chat/delegation/run
  identity, owner checks, redaction, source-faithful tool output, and read-only
  replay acceptance criteria.
- **#157:** Ordered descendant event subscriptions/routing,
  owned stream consumption, snapshot plus cursor, bounded queues, error and
  cancellation terminal events, and independent observers. This is core Deputy
  runtime work, not a shinychat dependency. A single-Agent event feed exists,
  but descendant forwarding/subscription semantics still need implementation.
- **#158:** A lead chat with activity cards and a selected child
  transcript panel using public shinychat APIs, first replay then live events.
  Verify two concurrent children and duplicate specialist names,
  ordered tool requests/results, partial failure, cancellation, observer detach,
  cross-owner denial, reload replay, and no duplicate execution. Exercise deeper
  lineage with fixtures; a running grandchild demo waits for supported recursive
  lifecycle and transitive budgets in #42. Include a
  trusted mini-agent example where authoritative results are visually distinct.
- **Upstream-gated enhancement:** Streaming *inside native nested tool cards*
  should follow #378 when it gains a supported contract. The separate panel and
  core event feed need not wait. Avoid private wire-protocol/DOM extensions just
  to imitate an unfinished upstream feature.
- **#62/#66:** Keep the host-persistence/fork/headless adapter gate separate from
  inspection. A released shinychat history feature does not expose every private
  branch helper, and child inspection need not depend on automatic forks.

Acceptance should be tested on the declared minimum ellmer version and shinychat
R 0.5.0, with development-head compatibility optional. Offline stream fixtures
prove ordering/identity/control boundaries; browser tests prove what users see.
Neither substitutes for the other or implies better model task performance.
