# Budget-aware history recovery: approved follow-up

The predeclared comparison completed on 7 September 2026. Budget-aware history
produced 9/9 structured answers; baseline history produced 8/9. Both passed all
ten checks in 7/9 trials. The one recovered answer accounts for the entire
0.10 increase in mean score. Eight matched scores tied and none decreased.
Budget-aware history used more requests, estimated cost and elapsed time.

This is nine matched trials across three variants of one synthetic case, using
`gpt-5.6-luna` with low reasoning effort. It does not establish production
reliability, statistical significance, or which part of the combined capacity
framing and reserved answer phase caused the observed difference. Broader
validation remains tracked in [#112](https://github.com/JamesHWade/deputy/issues/112).

## Results

All 27 planned continuations were attempted; 26 returned structured answers.
There were no undispatched or unreached arms. Scores use the ten fixed checks;
a missing answer scores zero without implying ten asserted incorrect facts.
“Fully correct” means those checks passed, not that every free-text claim was verified.

| Arm | Answers | Mean score | Fully correct | Grounded sources | Exact export ID | Median completed seconds | Continuation requests | Estimated continuation USD |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Summary-only | 9/9 | 0.8222 | 0/9 | 1/9 | 8/9 | 9.44 | 18 | 0.01097380 |
| Baseline history | 8/9 | 0.8778 | 7/9 | 7/9 | 8/9 | 12.36 | 30 | 0.01656982 |
| Budget-aware history | 9/9 | 0.9778 | 7/9 | 7/9 | 9/9 | 19.03 | 45 | 0.02735800 |

Baseline history's sole incomplete continuation stopped at the tool-call limit
in `changed-constraint`, trial 2, after 8.03 seconds. Its matched budget-aware
answer passed 9/10 checks, missing source grounding. In changed-constraint
trial 1, both history arms also missed grounding. Completed matched answers
therefore showed no score gain in this sample. The completed latency medians
have different denominators (8 versus 9); [pairs.csv](pairs.csv) preserves
individual paired latencies, including the incomplete baseline.

| Scenario | Summary mean | Baseline answers / mean | Budget-aware answers / mean |
|---|---:|---:|---:|
| original | 0.8333 | 3/3 / 1.0000 | 3/3 / 1.0000 |
| changed-constraint | 0.7667 | 2/3 / 0.6333 | 3/3 / 0.9333 |
| resolved-methods | 0.8667 | 3/3 / 1.0000 | 3/3 / 1.0000 |

Preparation cost is charged once for each shared context: 90 requests and
estimated USD 0.24360288. Adding all continuations gives **183 governed requests
and estimated USD 0.29850450**. These are observed token-price estimates, not an
invoice. The approved allowance was USD 5, with an aggregate observed dispatch
stop at USD 3.50 and a 300-request ceiling. No failed trial was retried.

All nine preparations recorded three automatic compactions and one verified
host export each. All three arms received identical prepared turns, system
prompts and completed-export receipts. Each receipt verifies the same 37-byte
C21/84 CSV SHA-256:
`7c3e0ac63f3d20cf8917619065bf65127f8eaff201c612116334440ce2b2377e`.
Continuations requested zero exports and repeated zero exports.

The execution log preserves four warnings, each reporting two history searches
refused after the adapter allowance was exhausted. These refusals returned zero
source bytes. They are retained outcomes, not omitted trials. Per-trial requested,
dispatched, refused and payload-bearing retrieval counts, bytes, tokens, failed
checks and stop reasons are in [trials.csv](trials.csv); each generated scenario
report and compressed raw JSON also retains phase outcomes and dispatch status.

## Protocol and provenance

The [protocol](../budget-aware-protocol.md) was committed before execution.
The immutable evaluated source was
`34b9c23415b45a7e2c46663f55e5e7d90aacb95b`, with Deputy 0.0.0.9000,
ellmer 0.5.0 and R 4.6.1. Both helper and task models were `gpt-5.6-luna`,
verified available before dispatch, with low reasoning effort, 1,024 maximum
output tokens and a 6,000-token preparation context threshold. Three trials
per scenario rotated all three arms through each execution position.

Each continuation retained its eight-request ceiling. Budget-aware retrieval
used at most six requests and reserved two for a tool-free structured answer.
Both history arms allowed payload access during only the first six adapter
calls, with 4,096 bytes per response and 16,384 bytes total. Later adapter calls
were refused, and runtime limits could prevent dispatch. This is a payload-access
allowance, not a ceiling on emitted attempts: baseline history requested up to
ten calls and invoked the adapter up to eight times. The raw counters distinguish
these outcomes. The original baseline archive is unchanged; the comparison
above uses the contemporaneous baseline arm in this run.

[invocation.R.txt](invocation.R.txt) is the exact executed driver. It loaded a
`git archive` snapshot of the source commit and carried the remaining aggregate
cost/request budget across scenarios. Its progress wrapper recorded usage after
each governed run without changing prompts or budget policy. The invocation
requires explicit paid-run opt-in; do not execute it to inspect these results.
[invocation.json](invocation.json) records versions, pricing and settings;
[planned-schedule.json](planned-schedule.json) records all planned arms;
[run-summary.json](run-summary.json) and [execution.txt](execution.txt) retain
completion and execution evidence. Raw JSON uses full numeric precision.

- [Original report](original.md) and [raw JSON, gzip](original.json.gz)
- [Changed-constraint report](changed-constraint.md) and [raw JSON, gzip](changed-constraint.json.gz)
- [Resolved-methods report](resolved-methods.md) and [raw JSON, gzip](resolved-methods.json.gz)
- [Independent aggregate analysis](analysis.json), [all trials](trials.csv) and [matched history pairs](pairs.csv)

The independent standard-library Python audit recomputes all ten checks from
raw answers, verifies matching initial contexts and receipts, reconciles phase
and aggregate accounting, and checks retrieval/request ceilings. To recompute
its derived files without model calls, run `python3 analyze.py.txt` in a copy of
this directory. The generated scenario Markdown is reproduced from raw JSON by
the evaluated source's `history_report()` function without provider requests.
[manifest.json](manifest.json) records SHA-256 and byte sizes for every archived
file except itself, plus decompressed raw JSON hashes. Local temporary paths
in the historical invocation and raw receipts describe the original run; they
are not portable dependencies for reading or auditing the archive.
