# Bounded history recovery experiment

Compare cumulative summary plus recent context with **the same prepared context**
plus read-only search and reads of caller-owned source records. This is an
external example, not a new Deputy API, conversation database, or RLM runtime.

`fixture.R` supplies an entirely synthetic evidence review with three checkpoints,
early eligibility constraints, a superseded denominator, unresolved methods, a
historical export receipt, and quoted malicious instructions. Ninety synthetic
catalogue records add approximately 400 KB of deliberately repetitive distractor
text. This stresses repeated transitions; it is not representative clinical data
or evidence of performance on real conversations. The historical export is a
fixture receipt, not a write executed during preparation.

`evaluation.R` loads each checkpoint through an actual ellmer tool round under a
Deputy read-only allowlist. Large-result offloading is disabled for this experiment
so the source text reaches the model. Preparation must load all checkpoints and
produce at least two automatic compactions. A repeated or out-of-order checkpoint
invalidates preparation and is not scored. Both continuations start from identical
prepared turns and system prompt; their order alternates across trials. The helper
model performs preparation and summarization; the task model is held fixed.

The history continuation adds two tools from `history.R`:

- `history_search(query)`: literal word matching, at most three IDs with revisions
  and short excerpts. All query words must match; narrow the query for omitted hits.
- `history_read(item_id, revision, offset)`: a bounded UTF-8 chunk. An optional
  expected revision rejects stale references; `next_offset` continues a read.

The host binds owner, conversation, Agent and branch before searching. The model
cannot change that scope. Missing and unauthorized IDs return the same result.
Defaults allow six calls, 4,096 bytes per response and 16,384 bytes overall,
including JSON framing and provenance. Rejections contain no source payload and
do not consume the source-byte allowance. Both strategies register an export spy;
host permissions prohibit executing it even if source text asks for another write.

## Deterministic verification

From the source checkout, with released ellmer 0.5.0 installed:

```r
devtools::test(filter = "history-recovery-example|compaction-evidence")
```

Tests use real ellmer producers against a local HTTP server, with canned answers
and a character-count estimator that shrinks after compaction to force transitions. They cover paired preparation,
structured scoring, real retrieval, scope isolation, stale/missing references,
UTF-8 and payload limits, denied exports, cancellation and exhausted/unknown-cost
budgets. Canned answer scores test the wiring, **not model recall quality**.

## Live pilot

Install this Deputy branch first. Configure OpenAI credentials through ellmer's
normal mechanism. Run the following only after choosing a spending allowance:

```sh
DEPUTY_HISTORY_LIVE=yes \
DEPUTY_HISTORY_MAX_COST_USD=2 \
DEPUTY_HISTORY_OUTPUT=/tmp/history-recovery-luna-pilot \
Rscript -e 'source(system.file("examples/history-recovery/run.R", package = "deputy"))'
```

The limit is **observed estimated cost, not a hard billing cap**: an in-flight
response may cross it, and provider retries may not have reported usage. Leave
headroom within the authorized allowance and use provider-side controls if a
strict spending ceiling is required. Unknown cost stops subsequent dispatch.
The runner also caps the experiment at 100 governed requests, limits each run,
and requests at most 1,024 output tokens per response. Provider accounting and
retry behavior remain ellmer's responsibility.

Optional environment variables are `DEPUTY_HISTORY_TRIALS` (default `3`),
`DEPUTY_HISTORY_HELPERS` (comma-separated, default `gpt-5.6-luna`) and
`DEPUTY_HISTORY_TASK_MODEL` (default `gpt-5.6-luna`). For a helper comparison, keep
the task model fixed and include Luna and Terra in `DEPUTY_HISTORY_HELPERS`.
The aggregate request budget can stop a larger experiment early; use
`history_evaluate()` directly to choose a different request allowance.

Each new output directory receives `results.json` and `report.md`. The JSON
includes fixtures, input contexts, prompts, answers, source references, run IDs,
compaction attempts, events, usage, latency and completed-effect counters.
Conditions are reduced to their classes so credential-bearing request objects
are not persisted. Inputs are synthetic; a consented-data adaptation must treat
its outputs as private host data. Recoverable run failures preserve partial
evidence. A process kill or interactive interrupt before saving does not.

Eight explicit structured checks score the answer; no model judge is used.
Report individual paired outcomes, failed/missing trials and score/latency
distributions. Fully correct means all eight checks pass; it does not measure
every claim in the free-text answer. Preparation costs are shared once per pair;
continuation costs remain separate. Do not infer Luna/Terra equivalence, production
retrieval quality, or a need for recursive analysis from a small synthetic pilot.

The optional `cancelled` callback is cooperative: checked before runs and history
access. It does not interrupt an already-running provider request. Deputy's
runtime cancellation behavior is covered separately in its compaction tests.
