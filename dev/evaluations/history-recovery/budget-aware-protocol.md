# Budget-aware history completion: follow-up protocol

This comparison tests whether exposing remaining retrieval capacity and reserving
an answer phase improves completion within the existing continuation limits.
It is a targeted follow-up to the [7 September baseline](2026-09-07/README.md)
and [#135](https://github.com/JamesHWade/deputy/issues/135). Declare and commit
this protocol before starting a new paid run; record the evaluated source commit
in the resulting evidence manifest.

## Matched comparison

Run three trials for each existing scenario: `original`, `changed-constraint`,
and `resolved-methods`. Every trial prepares one context through three automatic
compactions and one verified host export. Reuse those exact prepared turns,
system prompt, source revisions and effect receipt in three fresh continuations:

1. Summary-only, using the original question and no history access.
2. Baseline history, using the original question, tool descriptions and response
   payloads from the recorded producer.
3. Budget-aware history, with remaining capacity in descriptions and responses,
   followed by a separate answer phase with all tools removed.

Rotate the first arm across the three trials so each arm appears in every
execution position once. This gives nine matched preparations and 27 planned
continuations. Use `protocols = c("baseline", "budget-aware")` with
`history_evaluate()`. The frozen baseline remains unchanged; the new baseline
history arm provides the contemporaneous comparison.

Fix both helper and task model to `gpt-5.6-luna`, low reasoning effort, at most
1,024 output tokens per response, with the released ellmer dependency set.
Preparation retains its 6,000-token context threshold. Verify model availability
and record the dependency versions before dispatch. Do not retry failed trials,
replace missing answers, tune prompts after viewing results, or change the
scoring checks during this comparison.

## Capacity and authority

Every continuation retains an eight-model-request ceiling. Baseline history
retains its eight-tool-request limit. Budget-aware history allocates at most six
model requests to retrieval and at most two to producing the final structured
answer through ellmer. The two phases share the experiment's request and cost
accounting; all phase usage contributes to the continuation total.

The retrieval phase retains the same eight-tool-request limit. The answer phase
registers no tools and allows zero tool calls. It can follow a completed
retrieval phase or a request/tool-limit stop; other failed retrieval outcomes
remain incomplete. A cancellation, exhausted aggregate budget, unavailable cost,
or failure to produce a valid structured answer can still leave the continuation
incomplete. Preserve that outcome and its phase evidence.

Both retrieval arms share the unchanged host-bound owner, conversation, Agent,
and branch scope; six history attempts, 4,096 bytes per response, and 16,384
bytes total. Budget-aware response framing counts against those same byte
ceilings. Responses state calls remaining after the attempt and bytes remaining
before the response; raw usage records the exact remaining bytes afterward.
An oversized provider batch cannot obtain source payload beyond the adapter
allowance. Refused requests remain visible in the audit and run counters.

All arms retain read-only host authority and the same completed-export receipt.
The baseline registers the denied export spy throughout its continuation; the
budget-aware arm removes it along with history tools for the final answer phase.
Count any requested or executed repeat export. Removing tools grants no new
permission.

## Outcomes declared in advance

The primary outcome is the number of structured answers from budget-aware history
versus baseline history across all nine matched trials. Report completion and
missing answers separately from the ten fixed answer checks. Missing answers
receive zero in all-attempt mean scores, as in the original comparison; this is
not a claim that the model asserted ten incorrect facts.

Also report individual matched scores and differences, summary-only scores,
source grounding, exact export identification, attempted retrieval calls,
searches and reads with source payload, refused calls, returned bytes, requested
and repeated exports, each phase's stop reason and dispatch status, requests,
tokens and estimated cost. Show latency for completed answers separately from
incomplete continuations. Charge preparation once per matched trial and include
all retrieval and answer-phase usage in each continuation's totals.

Keep raw inputs, prompts, answers, source revisions, run IDs, phase outcomes,
compaction evidence and receipts. Save JSON with full numeric precision, generated
reports, all trial rows, the exact invocation, execution output and SHA-256 hashes.
If aggregate limits interrupt the experiment, retain partial evidence and list
planned continuations that were never reached separately from attempted failures.

## Spending and interpretation

A new paid invocation requires an explicit user spending allowance. The proposed
run uses an allowance of at most $5, stops new dispatch at an aggregate observed
estimate of $3.50, and permits at most 300 governed requests across all scenarios.
The larger aggregate request allowance accommodates the additional comparison
arm; no per-continuation budget is increased. The cost threshold reserves 30%
headroom for in-flight accounting and is not a hard billing cap. No paid run is
authorized by committing this protocol alone.

Nine trials across three variants of one synthetic case are sufficient for a
small controlled follow-up, not a production-quality conclusion or statistical
reliability claim. Broader tasks, different source structures, larger catalogues,
and longer revision histories remain necessary under
[#112](https://github.com/JamesHWade/deputy/issues/112) before any integration
recommendation. This experiment does not add a production history store or a
recursive execution framework.
