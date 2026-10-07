# ADR-0032: Approved tool display and provenance evidence

Status: accepted for implementation in #238. Amends ADR-0020 and ADR-0022.

## Context

ADR-0020 omitted "arbitrary UI extras" from portable child records, and the
implementation cleared every `Content@extra`. A tool result's `extra` carries
three different things: shinychat's `display` (what the user was shown for the
call), producer provenance such as Commons' `commons_tag`, and provider or
application data that must never leave the runtime. Commons builds its trust
signal on the first two: a visible, deterministic card for each trusted
calculation, tagged `A` (registered measure) or `B` (SQL). Clearing `extra`
made every child Commons card disappear from inspection, observation, export
and replay, which posit-dev/commons#398 and posit-dev/shinychat#423 identify as
the obstacle to subagent workflows.

## Decision

- **A versioned projection, recorded beside the ellmer props.** Recording a
  `ContentToolResult` keeps `props$extra` empty and adds a sibling
  `deputy_display` field: `format = "deputy_tool_display"`, `version = 1`,
  `display`, `provenance` and `omitted`. `R/tool-display-evidence.R` owns the
  projection, its validation and the rebuilt `extra`.
- **Approved fields only.** `display` keeps the fields of shinychat's
  `tool_result_display()`: `title`, `icon`, `html` and `footer` as HTML text;
  `markdown`, `text`, `label` and `value_preview` as text; `show_request`,
  `open` and `full_screen` as flags; `open_style` as `"minimal"` or `"framed"`.
  `provenance` keeps `commons_tag` when it is one short token. A new field means
  a new version.
- **Bounded, with explicit omissions.** Each field has a byte limit (2 MiB for
  `html`, enough for a 2x inline plot; 1 KiB for one-line labels). A field over
  its limit, of the wrong type, or holding an object with no portable form
  (an htmlwidget, a function) is dropped and named in `omitted$fields` with the
  reason. Unknown `extra` keys and display fields are named, never copied.
  Tag objects are rendered with htmltools when they contain only tags, text and
  dependencies; dependencies are recorded by name and version, not file path.
- **Replay validates.** Saved history can come from storage the runtime does
  not control. Replay rebuilds `extra` only from a projection whose fields,
  types and sizes pass validation, and errors otherwise. A newer version is
  ignored rather than interpreted.
- **One projection for every path.** Inspection, observation, export,
  `delegation_history()` and context forks all record turns through
  `inspection_record_turn()`, so they share the projection. Observation events
  that carry content are bounded as before: a display larger than one event is
  omitted from the event and recovered from a snapshot. `tool_end` events keep
  reporting the model-facing value; the display lives in the transcript.
- **The browser boundary makes HTML inert.** shinychat renders a display's
  `title`, `icon`, `footer` and `html` as raw HTML. The optional Shiny adapter
  rebuilds those fields from an allowlist (`R/subagent-display.R`) before
  shinychat sees them: structure, classes, inline styles, inline SVG and
  `data:` images stay; scripts, event handlers, forms, embedded documents,
  sibling-reaching selectors, nested CSS rules and every URL the browser would
  fetch (remote images, and quoted URLs in `image-set()` and the other image
  functions, included) go. Ids get a prefix unique to each display, and a
  `<style>` element survives only when every rule is scoped to such an id, as
  gt's tables are; `@media` is kept at the top level only and a sheet over
  256 KiB is dropped, so the scan is linear. Each rebuilt field sits in its
  own box with `contain: paint` and `isolation: isolate`, so positioned,
  transformed or offset content can't paint over the host page. `markdown`
  and text fields are left to shinychat's inert renderers. Core records keep
  the tool's own HTML; the adapter is the only renderer.
- **Rendering never runs code.** Tag objects are rendered only when they are
  plain, resolved tags: a render hook would run arbitrary R code while a
  record is made, so a tag carrying one is omitted as `unsupported_object`.

## Consequences

- Child Commons cards, gt tables and inline plots are visible in the child
  panel and in replayed history, looking as they did when the tool ran.
- Records grow by the size of the displays they keep. Disclosure `max_bytes`
  still bounds a whole view; a host showing many large plots may need a larger
  bound or narrower selections.
- Provider-private data, executable closures, HTML dependency paths and
  unknown fields remain excluded. A display that needs a dependency the page
  doesn't load renders without it, and the record says which was omitted.
- Tag provenance is a label recorded by the producer, not proof of trust.
  Trusted results remain the job of `TrustedResults` (ADR-0030).
- Durable widget artifacts with their dependency bundles remain #144.
