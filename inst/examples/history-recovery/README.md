# History recovery experiment

Does an agent whose conversation has been compacted answer better if it can
also search and read the full earlier history? This experiment prepares one
compacted context, then continues it twice: once with the summary and recent
turns only, and once with two read-only history tools added. It is an example
built on Deputy and ellmer, not part of Deputy's API.

## The fixture

`fixture.R` defines a synthetic evidence review of reports A to F, loaded in
three checkpoints. The history contains early eligibility rules, a corrected
denominator, unresolved methods, a completed export and quoted malicious
instructions. Ninety synthetic catalogue records add about 400 KB of
repetitive distractor text. None of it is real clinical data.

`DEPUTY_HISTORY_SCENARIO` picks one of three scenarios. `original` is the
default. In `changed-constraint`, a user instruction at checkpoint 3 replaces
the adults-only rule with an all-ages rule for randomized studies: B becomes
eligible, while D and F still wait for allocation details. The instruction is
also stored as a source record. The final question doesn't repeat the change,
and the old rule stays in the history, so the scenario tests whether the model
applies the newer rule. In `resolved-methods`, later allocation details under
the original rule make D eligible and exclude F, leaving no reports pending.

Each trial runs one real CSV export (`export-0042`, fixed by
`history_export_contract()`) before checkpoint 2. The file's SHA-256, size
and contents are recorded, both continuations receive that record, and the
file is deleted. Both continuations also have an export tool that the agent's
permissions forbid, even if the history asks for another export.

## How a trial runs

`evaluation.R` loads each checkpoint through a real ellmer tool call in a
read-only Deputy agent, with large-result offloading turned off so the model
sees the source text. Preparation must load checkpoints 1, 2 and 3 in order and
compact at least twice; otherwise the trial is discarded. Both continuations
then start from the same turns and system prompt, in alternating order. The
helper model prepares and summarizes; the task model answers.

The history arm adds two tools from `history.R`. `history_search(query)`
matches literal words, all of which must appear, and returns up to three item
IDs with revisions and short excerpts. `history_read(item_id, revision,
offset)` returns one UTF-8 chunk of an item; it rejects an outdated
`revision`, and `next_offset` continues the read.

The tools only see records for the owner, conversation, agent and branch the
app sets; the model can't change that, and missing and unauthorized IDs look
the same. Each record's revision is checked against the SHA-256 of its text.
By default the tools allow six calls, 4,096 bytes per response and 16,384
bytes in total, counting JSON framing. Refused calls return no source text and
don't use up the byte allowance.

## Budget-aware protocol

The optional `budget-aware` protocol tells the model how many history calls
and bytes it has left, in the tool descriptions and in every response. Of each
continuation's eight model requests, up to six go to retrieval; then the tools
are removed and the model has up to two requests for its structured answer.
The answer phase also runs if retrieval stops at a request or tool-call limit.
Cancellation, an exhausted overall budget or another failure ends the
continuation as incomplete. Every phase counts toward the same budget.

`history_evaluate(protocols = c("baseline", "budget-aware"))` compares both
retrieval protocols and summary-only against the same prepared context, and
three trials rotate the order so each arm takes every position once. Called
directly, `history_evaluate()` defaults to the two-arm `baseline` comparison.
The [follow-up protocol](../../../dev/evaluations/history-recovery/budget-aware-protocol.md)
sets out that comparison and its outcomes before any paid run.

## Offline tests

From a source checkout, with ellmer 0.5.0 or later:

```r
devtools::test(filter = "history-recovery-example|compaction-evidence")
```

The tests run real ellmer calls against a local HTTP server with canned
answers, and use a character-count token estimate to force compaction. They
cover preparation, scoring, retrieval, scope isolation, stale and missing
references, size limits, denied exports, cancellation, exhausted or
unknown-cost budgets and the budget-aware answer phase, and run all three
scenarios through compaction and both continuations. The canned answers test
the wiring, not how well a model recalls.

## Live runs

Live runs make paid OpenAI requests. Install Deputy, set up OpenAI credentials
as you normally would for ellmer, choose a spending limit, and run:

```sh
DEPUTY_HISTORY_LIVE=yes \
DEPUTY_HISTORY_MAX_COST_USD=2 \
DEPUTY_HISTORY_OUTPUT=/tmp/history-recovery-luna-pilot \
Rscript -e 'source(system.file("examples/history-recovery/run.R", package = "deputy"))'
```

`DEPUTY_HISTORY_MAX_COST_USD` is a limit on observed estimated cost, not a
billing cap: a response already in flight can go over it, and provider retries
may not report their usage. Leave headroom, and set a limit with your provider
if you need a hard ceiling. The run stops if a cost is unknown. It also stops
after 100 requests in total, limits each run, and asks for at most 1,024
output tokens per response.

Other settings:

- `DEPUTY_HISTORY_TRIALS`: number of trials, default `3`.
- `DEPUTY_HISTORY_HELPERS`: comma-separated helper models, default
  `gpt-5.6-luna`. To compare helpers, keep the task model fixed and list
  several, such as `gpt-5.6-luna,gpt-5.6-terra`.
- `DEPUTY_HISTORY_TASK_MODEL`: the answering model, default `gpt-5.6-luna`.
- `DEPUTY_HISTORY_SCENARIO`: `original` (default), `changed-constraint` or
  `resolved-methods`. Use a separate output directory for each.
- `DEPUTY_HISTORY_PROTOCOLS`: `baseline,budget-aware` (default, three
  continuations per preparation), `baseline` (the original two-arm comparison)
  or `budget-aware` (summary-only against the budget-aware protocol).

Each invocation has its own spending limit, so add them up when you run
several. The 100-request cap can stop a larger experiment early; call
`history_evaluate()` directly to set a different one.

## Output and scoring

Each run writes `results.json` and `report.md` to a new output directory. The
JSON (schema version 3, full numeric precision) holds the fixture, input
contexts, prompts, answers, source references, run IDs, compaction attempts,
events, usage, latency and effect counts, including each protocol phase's
outcome. Errors are reduced to their classes, so request objects carrying
credentials are not saved. If you adapt the experiment to real data, treat
these files as private. A failure the runner can recover from still saves
partial results; killing or interrupting the process before it saves does
not.

Ten structured checks score each answer, including the current eligibility
rule and the individual D and F classifications; no model acts as judge.
"Fully correct" means all ten pass, which doesn't cover every claim in the
free text. Preparation cost is counted once per pair and each continuation's
cost separately. The report lists individual paired outcomes, failed checks,
missing continuations, completion counts, retrieval attempts and those that
returned source text, verified writes and export attempts, with latency for
completed and incomplete runs shown separately.

The optional `cancelled` callback is checked before each run and each history
call. It doesn't interrupt a request that is already running.

## Results so far

The [7 September 2026 pilot](../../../dev/evaluations/history-recovery/2026-09-07/README.md)
ran nine paired trials across the three scenarios. Retrieval improved source
grounding when it finished, but three history continuations stopped at the
tool-call limit. The report keeps those failures, the costs, the matched
contexts and the export records.

The [budget-aware follow-up](../../../dev/evaluations/history-recovery/2026-09-07-budget-aware/README.md)
got structured answers in 9/9 budget-aware and 8/9 baseline-history trials,
with 7/9 fully correct in both. The one recovered answer accounts for the
higher mean score, and the budget-aware arm used more requests, cost and time.
The archive holds all 27 continuations, the exact invocation and independent
checks.

Both are small synthetic samples. They don't show production quality, that
Luna and Terra are interchangeable, or that recursive analysis is needed.
