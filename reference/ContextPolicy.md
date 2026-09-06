# Configure automatic context management

Defines when an
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) compacts
its conversation and when large tool results are replaced with durable
references. The default policy compacts before a request would exceed
32,000 estimated tokens and offloads tool results larger than 64 KiB.

## Usage

``` r
ContextPolicy(
  max_tokens = 32000L,
  compact_to = 0.5,
  fallback = c("error", "text"),
  max_tool_result_bytes = 64 * 1024,
  offload_dir = NULL,
  summary_fallback_chats = list()
)
```

## Arguments

- max_tokens:

  Estimated complete-context token threshold that triggers compaction.
  Use `NULL` to disable automatic compaction.

- compact_to:

  Fraction of `max_tokens` that the retained recent context should
  occupy after compaction.

- fallback:

  What to do when LLM summary generation fails. `"error"` fails closed;
  `"text"` uses a deterministic truncated-text summary. Summary
  generation uses an isolated clone of the active Chat and does not
  select from the Agent's task `fallback_chats`.

- max_tool_result_bytes:

  Serialized size above which a tool result is stored outside the model
  context. Use `NULL` to disable result offloading. Compaction applies
  this limit to the public evidence in explicit
  [`ellmer::ContentToolResult`](https://ellmer.tidyverse.org/reference/Content.html)
  payloads too, retaining a preview and recoverable reference. Large
  tool-request arguments use the same bound and retain a recoverable
  argument record. Content objects and error conditions use their public
  text. A conservative rendered-size bound also covers compact sequences
  and shared strings before JSON expansion. Generated summaries retain
  up to eight direct recovery references; larger sets use one durable,
  chunk-readable catalog. Catalogs preserve earlier entries across
  compactions and session restores, including existing references when
  new result offloading is disabled. Superseded internal catalogs are
  reclaimed after replacement, except those referenced by retained turns
  or the installed prompt of a live Agent sharing that session directory
  in the current R process, including independent Agents and clones.
  Earlier saved sessions keep their own catalog snapshots. Original
  result artifacts are retained. New evidence artifacts from aborted
  compactions are removed unless another compaction or tool caller has
  claimed them.

- offload_dir:

  Directory for durable result envelopes. Relative paths are anchored to
  the current working directory when the policy is created. `NULL` uses
  the Deputy user cache, partitioned by Agent session.

- summary_fallback_chats:

  Ordered, explicitly configured ellmer Chats authorized to receive
  summary prompts during automatic compaction. Each template must have
  no turns or tools. Transient transport failures may advance to the
  next template after ellmer's retries. These destinations are separate
  from the Agent's task `fallback_chats`; choosing a summary destination
  does not change the task Chat. Manual `$compact()` uses only its
  active Chat and `fallback` policy. Templates are cloned at
  construction.

## Value

A `ContextPolicy` object.

## Details

Automatic compaction is an asynchronous run phase. `SessionStart` and
`UserPromptSubmit` precede `PreCompact`; `PostCompact` follows an
accepted replacement. `Stop` and `SessionEnd` include summary failures
and usage. Between tool rounds, context is checked at ellmer's next
request boundary after all tool results settle. Summary dispatches,
including failures, share the run's request/token/cost budget. Unknown
costs remain unknown.

Summary Chats have no tools, history, system prompt, or inherited
callbacks. Cancellation or unrecoverable failure leaves the active
context unchanged. An accepted summary remains installed when the budget
prevents task dispatch. `$last_compaction()` includes `run_id` and
summary `attempts` with destination, usage, and original condition.
Summaries are internal context, not task output. This policy does not
archive removed turns or restore runtime permissions from a summary.
