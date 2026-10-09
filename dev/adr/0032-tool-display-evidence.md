# ADR-0032: Approved tool display and provenance evidence

Status: accepted for implementation in #238. Amends ADR-0020 and ADR-0022.
Version 2 of the record adds Commons' query provenance (see the last section).

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
  A tag tree that would render to more than the field's limit is dropped as
  oversized without being rendered, since rendering copies and escapes all of
  it. The size is bounded before rendering from everything rendering writes
  out: text, tag and attribute names, and attribute values of any atomic type,
  counted by their widest element without converting them, so a compact
  sequence such as `1:1e8` is never expanded. Text and attribute values count
  as escaped (`&` as `&amp;`, `"` in an attribute as `&quot;`), and each tag
  its markup, indentation and line breaks, so the bound holds for the rendered
  text. The walk visits at most 4,096 nodes, attributes included, and stops at
  the first it refuses, so a longer tag list isn't walked to its end.
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
  functions, included) go. So do the declarative hooks that libraries on the
  host page act on: every `data-*` attribute (Bootstrap's `data-bs-toggle`
  and `data-bs-target` would open or close host elements) and shinychat's
  `suggestion` class (a click would send the element's text as the user's
  message). Ids get a prefix unique to each display, and a
  `<style>` element survives only when every rule is scoped to such an id, as
  gt's tables are; `@media` is kept at the top level only. A sheet over
  256 KiB or 1,000 rules, or an inline style over 256 KiB, is dropped unread,
  and declarations, like a rule's selectors, are checked together, so
  rebuilding stays linear and bounded. Each rebuilt field sits in its
  own box with `contain: paint` and `isolation: isolate`, so positioned,
  transformed or offset content can't paint over the host page, and with a
  bounded height (the body scrolls within 80vh, header fields are clipped to
  4em), so an element of enormous height can't stretch the conversation
  around the card. shinychat
  renders `markdown` as HTML, remote images included, so the adapter renders
  it with commonmark and rebuilds the result through the same allowlist,
  showing it as `html` (and drops it beside HTML of the card's own). Text
  fields are left to shinychat's plain-text renderer. Core records keep
  the tool's own HTML; the adapter is the only renderer.
- **Recording never runs code.** Tag objects are rendered only when they are
  plain, resolved tags: a render hook would run arbitrary R code while a
  record is made, so a tag carrying one is omitted as `unsupported_object`.
  Nor does reading a value dispatch a method: tags, tag lists, dependencies
  and `html` strings must have exactly the class htmltools gives them and
  are read after `unclass()`, and a string or flag with any other class is
  refused before `length()` or `is.na()` could call its methods. The
  attributes rendering reads from a node are checked too: attached
  dependencies must be plain `html_dependency` records (a function standing
  in for one would be called), the singleton flag a plain flag, and `noWS`
  one of htmltools' own options, since `%in%` would convert any other value
  in full. Tags and dependencies must be lists as well; an environment or
  function carrying their class is omitted. Only the `extra` element named
  exactly `display` is read as the display, so a key such as
  `display_private` is named as unknown and never projected. The display
  itself must be a plain list, or a list with exactly shinychat's
  `shinychat_tool_result_display` class; anything else, such as an
  environment carrying that class, is recorded as `invalid`.

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

## Version 2: query provenance

posit-dev/commons#404 records, on each `call_metrics` and `call_calculation`
result, the SQL that ran (`extra$sql`) and the values bound into its
placeholders (`extra$bindings`), so a document built from the result can say
where each number came from. Version 1 named both as unknown and dropped them,
so a child's query was lost from inspection, export and saved history even
though its result and tag were kept.

- **Two more provenance fields.** `sql` is kept when it is one plain string of
  at most 64 KiB. `bindings` is kept when it is an unnamed, attribute-free list
  of at most 64 values, each one plain non-missing string (at most 4 KiB),
  number or flag, which is what Commons binds. Attributes are checked before
  anything else is read, so a classed value (a `Date`, say) is refused without
  running its methods. A value that fails is dropped and named in
  `omitted$provenance`, as a malformed tag already was.
- **The version follows the fields.** A record holding either field is version
  2; a record without them is still written as version 1. A reader that knows
  only version 1 ignores a version 2 record, as it ignores any newer version, so
  only the records that carry a query lose their card in an older reader.
- **Validation is per version.** A version 1 record that carries `sql` or
  `bindings` is invalid; a version 2 record's fields are checked by the same
  rules as projection.
- **Not shown in the shared conversation.** Activity cards (ADR-0033) carry the
  display and tag only. The query lives in the subagent records: inspection,
  observation, export, `delegation_history()` and saved conversation records.
- **Disclosure applies as before.** The SQL names tables and columns, and the
  bindings can hold values a user typed. Both reach only an authorized
  requester, and a `DelegationDisclosure` redactor can remove them.
