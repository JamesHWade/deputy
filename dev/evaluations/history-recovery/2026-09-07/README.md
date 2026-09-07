# Live bounded-history pilot: 7 September 2026

Bounded retrieval improved grounding when it produced an answer, but three of
nine retrieval continuations stopped at the tool-call limit. Under the tested
limits, its overall mean score was lower than summary-only context. These results
support investigating completion under a bounded retrieval budget before
production integration or recursive analysis.

The pilot used 136 governed requests at an estimated cost of **$0.27056888**,
within a user-approved $5 allowance. Cost is the runtime estimate, not an invoice.
All nine paired preparations succeeded; 15 of 18 continuations produced answers.
No failed runs were replaced or retried to improve the reported scores.

## Paired results

Each answer has ten fixed checks. A continuation without a successful structured
answer receives zero under the pre-existing scoring rule. The table includes
these failures; a zero does not establish that the model asserted ten wrong facts.
Latency includes failed continuations, so early stops can lower its median.

| Scenario | Strategy | Answers | Mean score | All checks correct | Median seconds |
| --- | --- | ---: | ---: | ---: | ---: |
| original | summary | 3/3 | 0.833 | 0/3 | 8.63 |
| original | history | 3/3 | 0.967 | 2/3 | 11.66 |
| changed-constraint | summary | 3/3 | 0.733 | 0/3 | 10.71 |
| changed-constraint | history | 1/3 | 0.300 | 0/3 | 7.19 |
| resolved-methods | summary | 3/3 | 0.900 | 0/3 | 9.16 |
| resolved-methods | history | 2/3 | 0.667 | 2/3 | 11.11 |

Across all nine pairs, summary-only scored 0.822 and history scored 0.644.
History won six pairs and lost the three in which it did not produce an answer.
Four history answers passed every check; no summary-only answer did.

The six completed history answers all passed grounding. None of the nine
summary-only answers supplied the complete required set of valid source IDs.
Summary-only nevertheless preserved the current eligibility rule, corrected
denominator and document ID, unresolved work, D/F classifications and read-only
authority in all nine answers. Its other failures were the source page in two
answers and the exact export ID in five. Two completed history answers also
confused the export ID with its source-record ID. Exact export identification
improved in one pair; across all attempts, both strategies identified it in
4/9 answers. The observed benefit is therefore mainly source grounding.

## Completion and authority

| Scenario / trial | Stop reason | Governed tool requests | History call attempts |
| --- | --- | ---: | ---: |
| changed-constraint / 1 | tool_call_limit | 10 | 5 |
| changed-constraint / 3 | tool_call_limit | 9 | 8 |
| resolved-methods / 3 | tool_call_limit | 9 | 6 |

The per-run limit was eight tool requests. Provider batches requested more than
that limit; these counts include refused requests and do not imply that every
request executed. History access separately allowed six calls and returned no
source bytes for nine over-budget attempts across the pilot. Some calls also
returned no match. Raw audits distinguish those cases from successful reads.

Each preparation executed one real host-authorized CSV write in its own temporary
directory. Both continuations inherited the same verified receipt. All nine
receipts match the expected 37-byte artifact and its SHA-256. There were no
attempted or repeated exports during continuation. This establishes the observed
effect behavior; it does not exercise a fresh adversarial attempt to write.

## Protocol and limits

The producer was commit `c1dad52f76af6ac8df21f238a4ccd24bd9f145b6`, using Deputy
0.0.0.9000, released ellmer 0.5.0 and R 4.6.1. Both preparation/helper and task
models were configured as `gpt-5.6-luna`, with low reasoning effort and at most
1,024 output tokens per response. There was no Terra arm or independent helper
model comparison.

This frozen run predates PR #132's additional validation of the scoped receipt
row before export. All three recorded fixtures contain exactly one receipt row,
in the authorized scope at checkpoint 2; that hardening does not change the
recorded cases. The original inputs and results have not been replaced.

Each of three scenarios had three paired trials. Both strategies received the
same prepared turns and system prompt, verified by the saved summary ID.
Execution order alternated by trial. Every preparation produced three automatic
compactions. History access was limited to the host-bound owner, conversation,
Agent and branch, 4,096 bytes per response and 16,384 bytes in total.

The runner reserved 30% of the authorized allowance: each scenario received the
remaining part of a $3.50 aggregate estimated-cost threshold, with at most 250
governed requests across scenarios. The estimate can cross a threshold in flight;
this run remained well below both threshold and allowance.

These are three variants of one synthetic evidence-review case, with roughly
400 KB of repetitive catalogue padding. Three pairs per variant cannot establish
production quality, model equivalence or reliable tail behavior. The next
comparison should make remaining retrieval capacity explicit and reserve an
answer path, retain the same bounded-authority contract, and use more diverse
trajectories. Preserve this baseline when testing that change. Completion is
tracked in [#135](https://github.com/JamesHWade/deputy/issues/135), with broader
evaluation in [#112](https://github.com/JamesHWade/deputy/issues/112). No recursive runtime or
production history integration is justified by this pilot alone.

## Evidence

- [All trial rows](trials.csv) include scores, answer presence, stop reasons,
  usage, latency, retrieval attempts and effect counters.
- Original: [generated report](original.md), [raw JSON archive](original.json.gz).
- Changed constraint: [generated report](changed-constraint.md),
  [raw JSON archive](changed-constraint.json.gz).
- Resolved methods: [generated report](resolved-methods.md),
  [raw JSON archive](resolved-methods.json.gz).
- [Manifest](manifest.json) records configuration, versions and SHA-256 digests
  for the compressed and original JSON bytes.
- [Historical invocation](invocation.R.txt) and [execution log](execution.txt)
  retain the exact driver and its aggregate usage output. The invocation uses
  the temporary source/output paths from this run; it is an audit record.

The archives preserve the original JSON bytes, including inputs, prompts,
answers, source revisions, run/attempt events and compaction evidence. The runner's
JSON writer rounded floating point values to four decimal places; the unmodified
Markdown reports retain the cost estimates formatted before serialization.
Small differences between sums of JSON costs and the displayed total are rounding,
not omitted calls. Scores, checks and integer counters were independently verified,
as were all nine matching preparation pairs and artifact receipts.

For example, inspect an archive without making a model request:

```r
evidence <- jsonlite::fromJSON(
  gzfile("dev/evaluations/history-recovery/2026-09-07/original.json.gz"),
  simplifyVector = FALSE
)
```

The [example README](../../../../inst/examples/history-recovery/README.md)
documents a new live invocation. A rerun requires its own explicit spending
allowance and must preserve these original observations.
