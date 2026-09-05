# Compaction evaluation

The governed compaction lifecycle (#111) is independent of the strategy used to
prepare the next context window. This change retains summary-based compaction.
It does not implement history storage, retrieval, or an RLM runtime.

## Fixed case and deterministic checks

`tests/testthat/fixtures/compaction/evidence-review.json` supplies an evidence
review trajectory and probes for four kinds of information:

| Probe | Expected continuation |
| --- | --- |
| Early constraint | Reject a study with children under an adult-only rule |
| Superseded evidence | Use denominator 84 from assay-C-r3, page 17 |
| Unresolved work | Preserve uncertainty about D and F |
| Completed effect | Recognize export-0042; require fresh authority for another write |

The history is deliberately small so local tests can force transitions at a low
token threshold. It is a seed case for longer evaluations, not evidence of
long-context model quality. Required facts and forbidden claims are semantic
targets; mentioning a superseded value to explain its correction is acceptable.
The fixture's statements about approval are conversation content, not executable
permission grants. Tests provide permissions through the host's Agent policy.

`test-compaction-run.R` uses the real released ellmer producer against a local
HTTP server with deterministic responses. It verifies summary isolation,
explicit recovery destinations, shared request/token/cost accounting, lifecycle
correlation, cancellation, and preservation of tool results and completed effects.
The between-round cases execute a counted export tool and require exactly one
effect. Wire fixtures establish runtime behavior, not model recall accuracy.
Stopped boundaries are also saved, loaded into a fresh Agent, and resumed;
the provider receives each settled tool result once, with run-scoped usage.

Released ellmer 0.5.0's `get_tokens()` preview table assumes paired user and
completed assistant turns. A retained, undispatched tool-result turn violates
that assumption ([upstream issue](https://github.com/tidyverse/ellmer/issues/1131)).
Deputy reads public assistant token/cost properties if that
table fails. For context estimation, it supplies the last completed pair and
subsequent content to ellmer's public estimator on a clone. This leaves the
canonical history and provider encoding intact, including after resume. Remove
these narrow accommodations when the released producer supports this history.

Run these tests without credentials or external model requests:

```r
devtools::test(filter = "compaction-run|context-policy|chat-fallback")
```

## Next comparison

The runnable producer is now in
[`inst/examples/history-recovery/`](../inst/examples/history-recovery/README.md).
It supplies three synthetic checkpoints through real tool rounds, requires
repeated automatic compaction, and compares identical prepared contexts with
and without scoped retrieval. `test-history-recovery-example.R` exercises its
paired runner and failure paths with released ellmer wire fixtures. The new
tool-evidence regression also verifies that the summary request contains tool
results without their private display metadata.

Deterministic scores establish the experiment's wiring, not model quality.
#112 remains open for authorized live repeated trials and an evidence-based
decision. The initial catalogue is repetitive synthetic padding; supplement it
with diverse or consented trajectories, actual completed effects and changed
constraints before making a production claim. The live runner requires explicit
opt-in, preserves recoverable partial results, and documents observed-cost
limitations. No recursive implementation is justified by the fixture tests.

The optional `changed-constraint` scenario now supplies a later host amendment
and retains it by source ID and revision. Its deterministic producer checks
paired contexts, retrieval of the amendment, and rejection of the superseded
eligibility answer. Actual completed effects and more diverse trajectories
remain follow-up work; the export receipt in both scenarios is synthetic.

Evaluate these strategies on the same host-owned trajectories and probes:

1. Current cumulative summary plus recent context.
2. The same summary plus bounded reads/search of original history by stable ID.
3. Bounded recursive analysis over selected history, only after the second
   strategy has a working producer and a measured need for recursive calls.

Retain the seed's early facts and corrections while adding real intervening
tool rounds from consented or synthetic runs. Force several context transitions,
including one after a side effect and one before a changed user constraint.
Also test missing history, stale references, cancellation, and exhausted budgets.
Scope every history lookup to the authorized conversation and Agent.

Record the case ID, strategy, model/version, prompt, run ID, compaction attempts,
source item references, answer, requests, reported tokens, known/unknown cost,
latency, and tool-effect counts. Judge factual claims against the original source
items and execution authority against host state. Repeat model trials; compare
accuracy and latency distributions, not one successful answer. Luna is a
candidate helper model to measure, not an assumed quality-equivalent substitute.

Do not add a second conversation database to run this comparison. Use an
explicit caller-owned history fixture first. Continue implementation against
host-supplied history under ADR-0003; the optional shinychat adapter tracked in
#66 can follow when its public R contract is released. Removed
turns remain unrecoverable through the current Deputy session snapshot unless
the host retained them independently. Schema changes can target the current
pre-CRAN format directly.

## Design evidence

Codex 0.153.1 includes a token-budget context transition that skips summarization
but retains compaction lifecycle hooks. Separately configured history and notes
tools support recovery across windows. These are useful examples of separating
active context from recoverable history; they do not establish an RLM backend.
See [context transitions](https://github.com/openai/codex/blob/rust-v0.153.1/codex-rs/core/src/compact_token_budget.rs)
and [history tools](https://github.com/openai/codex/blob/rust-v0.153.1/codex-rs/ext/history-notes/src/tools.rs).

The [RLM paper](https://arxiv.org/html/2512.24601v3) describes programmatic access
to externalized inputs and recursive model calls. That is a separate strategy
to evaluate. [OpenAI API compaction](https://developers.openai.com/api/docs/guides/compaction)
instead exposes opaque continuation items; provider encoding belongs in ellmer.
