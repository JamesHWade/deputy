# Bounded history recovery pilot

Synthetic evidence-review trajectories; this pilot does not establish production performance.

Case: assay-review-changed-constraint-v1

Recorded 9 arms: 9 attempted and 0 undispatched. Governed requests: 61. Cost: 0.09901798 USD.

An attempted continuation with a missing structured answer receives zero under the fixed scoring rule. Undispatched arms are retained but excluded from scores, latency summaries and paired comparisons. Completion is reported separately from answer checks.

| Helper / strategy / protocol | Recorded arms | Attempted | Undispatched | Answers | Mean attempted score | Fully correct | Median completed seconds | Median incomplete seconds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/summary/baseline | 3 | 3 | 0 | 3 | 0.767 | 0 | 9.44 | not observed |
| gpt-5.6-luna/history/baseline | 3 | 3 | 0 | 2 | 0.633 | 1 | 14.60 | 8.03 |
| gpt-5.6-luna/history/budget-aware | 3 | 3 | 0 | 3 | 0.933 | 1 | 19.43 | not observed |

| Shared trial | History protocol | History minus summary score | History minus baseline history score | Shared preparation requests | Shared preparation USD |
| --- | --- | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/1 | baseline | 0.1 | 0 | 10 | 0.02684896 |
| gpt-5.6-luna/1 | budget-aware | 0.1 | 0 | 10 | 0.02684896 |
| gpt-5.6-luna/2 | baseline | -0.7 | 0 | 10 | 0.02662836 |
| gpt-5.6-luna/2 | budget-aware | 0.2 | 0.9 | 10 | 0.02662836 |
| gpt-5.6-luna/3 | budget-aware | 0.2 | 0 | 10 | 0.02669456 |
| gpt-5.6-luna/3 | baseline | 0.2 | 0 | 10 | 0.02669456 |

Expected 9 continuations; attempted 9; missing 0 (0 undispatched, 0 not recorded).
Shared preparation is counted once per trial, even when displayed beside multiple comparisons.

| Trial | Strategy / protocol | Dispatched | Answer | Score | Requests | Governed tool requests | Tokens | USD | Seconds | Stop reason |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| gpt-5.6-luna/1 | summary/baseline | TRUE | present | 0.800 | 2 | 0 | 2863 | 0.0013026 | 9.44 | complete |
| gpt-5.6-luna/1 | history/baseline | TRUE | present | 0.900 | 4 | 8 | 6911 | 0.00227312 | 15.34 | complete |
| gpt-5.6-luna/1 | history/budget-aware | TRUE | present | 0.900 | 5 | 6 | 10282 | 0.00338322 | 19.98 | complete |
| gpt-5.6-luna/2 | history/baseline | TRUE | missing | 0.000 | 2 | 10 | 2561 | 0.0007822 | 8.03 | tool_call_limit |
| gpt-5.6-luna/2 | history/budget-aware | TRUE | present | 0.900 | 5 | 6 | 10417 | 0.00347726 | 19.43 | complete |
| gpt-5.6-luna/2 | summary/baseline | TRUE | present | 0.700 | 2 | 0 | 2575 | 0.00115 | 11.77 | complete |
| gpt-5.6-luna/3 | history/budget-aware | TRUE | present | 1.000 | 5 | 5 | 9594 | 0.00323612 | 17.94 | complete |
| gpt-5.6-luna/3 | summary/baseline | TRUE | present | 0.800 | 2 | 0 | 2605 | 0.001092 | 6.26 | complete |
| gpt-5.6-luna/3 | history/baseline | TRUE | present | 1.000 | 4 | 8 | 6322 | 0.00214958 | 13.87 | complete |

| Trial | Strategy / protocol | Failed checks | History requested | Adapter calls | Not dispatched | Adapter refusals | Searches with source payload | Reads with source payload | History bytes | Completed writes | Export attempts | Repeated exports |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary/baseline | source_page, grounded_sources | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| gpt-5.6-luna/1 | history/baseline | grounded_sources | 8 | 8 | 0 | 2 | 6 | 0 | 3881 | 1 | 0 | 0 |
| gpt-5.6-luna/1 | history/budget-aware | grounded_sources | 6 | 6 | 0 | 0 | 6 | 0 | 3098 | 1 | 0 | 0 |
| gpt-5.6-luna/2 | history/baseline | current_constraint, denominator, corrected_source, source_page, unresolved_work, d_classification, f_classification, completed_effect, authority, grounded_sources | 10 | 6 | 4 | 0 | 4 | 0 | 1541 | 1 | 0 | 0 |
| gpt-5.6-luna/2 | history/budget-aware | grounded_sources | 6 | 6 | 0 | 0 | 6 | 0 | 3166 | 1 | 0 | 0 |
| gpt-5.6-luna/2 | summary/baseline | source_page, completed_effect, grounded_sources | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| gpt-5.6-luna/3 | history/budget-aware | none | 5 | 5 | 0 | 0 | 5 | 0 | 3523 | 1 | 0 | 0 |
| gpt-5.6-luna/3 | summary/baseline | source_page, grounded_sources | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| gpt-5.6-luna/3 | history/baseline | none | 8 | 8 | 0 | 2 | 6 | 0 | 2846 | 1 | 0 | 0 |

| Trial | Strategy / protocol | Phase | Dispatched | Stop reason | Requests | Tokens | USD |
| --- | --- | --- | --- | --- | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary/baseline | answer | TRUE | complete | 2 | 2863 | 0.0013026 |
| gpt-5.6-luna/1 | history/baseline | answer | TRUE | complete | 4 | 6911 | 0.00227312 |
| gpt-5.6-luna/1 | history/budget-aware | retrieve | TRUE | complete | 3 | 3940 | 0.00151082 |
| gpt-5.6-luna/1 | history/budget-aware | answer | TRUE | complete | 2 | 6342 | 0.0018724 |
| gpt-5.6-luna/2 | history/baseline | answer | TRUE | tool_call_limit | 2 | 2561 | 0.0007822 |
| gpt-5.6-luna/2 | history/budget-aware | retrieve | TRUE | complete | 3 | 4004 | 0.00165866 |
| gpt-5.6-luna/2 | history/budget-aware | answer | TRUE | complete | 2 | 6413 | 0.0018186 |
| gpt-5.6-luna/2 | summary/baseline | answer | TRUE | complete | 2 | 2575 | 0.00115 |
| gpt-5.6-luna/3 | history/budget-aware | retrieve | TRUE | complete | 3 | 3084 | 0.00138712 |
| gpt-5.6-luna/3 | history/budget-aware | answer | TRUE | complete | 2 | 6510 | 0.001849 |
| gpt-5.6-luna/3 | summary/baseline | answer | TRUE | complete | 2 | 2605 | 0.001092 |
| gpt-5.6-luna/3 | history/baseline | answer | TRUE | complete | 4 | 6322 | 0.00214958 |

Raw JSON records individual scores, run IDs, source references, attempts, usage, phase outcomes, latency, and prompts.
History requested counts continuation request occurrences, including calls stopped before adapter dispatch by runtime, permission or schema checks. Adapter refusals count budget, invalid, cancelled and unavailable responses; legacy unrecorded fields remain unknown.
Successful payload counts require nonempty source text or excerpts and exclude stale, missing and rejected responses. Legacy audits without source-byte counts remain unknown. Unknown phase usage remains NA; undispatched phases use zero.
Preparation cost is shared once per trial; continuation costs include every phase and remain separate.
Inspect individual matched outcomes and missing/failed trials before drawing conclusions.
A small synthetic pilot cannot establish model equivalence or justify recursive analysis by itself.
