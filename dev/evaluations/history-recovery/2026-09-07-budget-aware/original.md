# Bounded history recovery pilot

Synthetic evidence-review trajectories; this pilot does not establish production performance.

Case: assay-review-long-v1

Recorded 9 arms: 9 attempted and 0 undispatched. Governed requests: 60. Cost: 0.1012506 USD.

An attempted continuation with a missing structured answer receives zero under the fixed scoring rule. Undispatched arms are retained but excluded from scores, latency summaries and paired comparisons. Completion is reported separately from answer checks.

| Helper / strategy / protocol | Recorded arms | Attempted | Undispatched | Answers | Mean attempted score | Fully correct | Median completed seconds | Median incomplete seconds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/summary/baseline | 3 | 3 | 0 | 3 | 0.833 | 0 | 10.48 | not observed |
| gpt-5.6-luna/history/baseline | 3 | 3 | 0 | 3 | 1.000 | 3 | 9.41 | not observed |
| gpt-5.6-luna/history/budget-aware | 3 | 3 | 0 | 3 | 1.000 | 3 | 16.51 | not observed |

| Shared trial | History protocol | History minus summary score | History minus baseline history score | Shared preparation requests | Shared preparation USD |
| --- | --- | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/1 | baseline | 0.3 | 0 | 10 | 0.0306522 |
| gpt-5.6-luna/1 | budget-aware | 0.3 | 0 | 10 | 0.0306522 |
| gpt-5.6-luna/2 | baseline | 0.1 | 0 | 10 | 0.02672696 |
| gpt-5.6-luna/2 | budget-aware | 0.1 | 0 | 10 | 0.02672696 |
| gpt-5.6-luna/3 | budget-aware | 0.1 | 0 | 10 | 0.02641836 |
| gpt-5.6-luna/3 | baseline | 0.1 | 0 | 10 | 0.02641836 |

Expected 9 continuations; attempted 9; missing 0 (0 undispatched, 0 not recorded).
Shared preparation is counted once per trial, even when displayed beside multiple comparisons.

| Trial | Strategy / protocol | Dispatched | Answer | Score | Requests | Governed tool requests | Tokens | USD | Seconds | Stop reason |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| gpt-5.6-luna/1 | summary/baseline | TRUE | present | 0.700 | 2 | 0 | 2823 | 0.0014426 | 10.48 | complete |
| gpt-5.6-luna/1 | history/baseline | TRUE | present | 1.000 | 3 | 5 | 5140 | 0.001647 | 9.41 | complete |
| gpt-5.6-luna/1 | history/budget-aware | TRUE | present | 1.000 | 4 | 3 | 8234 | 0.0027328 | 14.50 | complete |
| gpt-5.6-luna/2 | history/baseline | TRUE | present | 1.000 | 3 | 5 | 5640 | 0.001748 | 8.90 | complete |
| gpt-5.6-luna/2 | history/budget-aware | TRUE | present | 1.000 | 4 | 3 | 7913 | 0.00262386 | 16.51 | complete |
| gpt-5.6-luna/2 | summary/baseline | TRUE | present | 0.900 | 2 | 0 | 2421 | 0.0009202 | 6.72 | complete |
| gpt-5.6-luna/3 | history/budget-aware | TRUE | present | 1.000 | 6 | 5 | 9486 | 0.00294216 | 19.19 | complete |
| gpt-5.6-luna/3 | summary/baseline | TRUE | present | 0.900 | 2 | 0 | 2743 | 0.0013066 | 15.65 | complete |
| gpt-5.6-luna/3 | history/baseline | TRUE | present | 1.000 | 4 | 8 | 6725 | 0.00208982 | 14.02 | complete |

| Trial | Strategy / protocol | Failed checks | History requested | Adapter calls | Not dispatched | Adapter refusals | Searches with source payload | Reads with source payload | History bytes | Completed writes | Export attempts | Repeated exports |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary/baseline | corrected_source, source_page, grounded_sources | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| gpt-5.6-luna/1 | history/baseline | none | 5 | 5 | 0 | 0 | 5 | 0 | 2446 | 1 | 0 | 0 |
| gpt-5.6-luna/1 | history/budget-aware | none | 3 | 3 | 0 | 0 | 3 | 0 | 1916 | 1 | 0 | 0 |
| gpt-5.6-luna/2 | history/baseline | none | 5 | 5 | 0 | 0 | 5 | 0 | 2701 | 1 | 0 | 0 |
| gpt-5.6-luna/2 | history/budget-aware | none | 3 | 3 | 0 | 0 | 3 | 0 | 2476 | 1 | 0 | 0 |
| gpt-5.6-luna/2 | summary/baseline | grounded_sources | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| gpt-5.6-luna/3 | history/budget-aware | none | 5 | 5 | 0 | 0 | 5 | 0 | 3092 | 1 | 0 | 0 |
| gpt-5.6-luna/3 | summary/baseline | grounded_sources | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| gpt-5.6-luna/3 | history/baseline | none | 8 | 8 | 0 | 2 | 6 | 0 | 3981 | 1 | 0 | 0 |

| Trial | Strategy / protocol | Phase | Dispatched | Stop reason | Requests | Tokens | USD |
| --- | --- | --- | --- | --- | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary/baseline | answer | TRUE | complete | 2 | 2823 | 0.0014426 |
| gpt-5.6-luna/1 | history/baseline | answer | TRUE | complete | 3 | 5140 | 0.001647 |
| gpt-5.6-luna/1 | history/budget-aware | retrieve | TRUE | complete | 2 | 3178 | 0.0011696 |
| gpt-5.6-luna/1 | history/budget-aware | answer | TRUE | complete | 2 | 5056 | 0.0015632 |
| gpt-5.6-luna/2 | history/baseline | answer | TRUE | complete | 3 | 5640 | 0.001748 |
| gpt-5.6-luna/2 | history/budget-aware | retrieve | TRUE | complete | 2 | 2430 | 0.00098426 |
| gpt-5.6-luna/2 | history/budget-aware | answer | TRUE | complete | 2 | 5483 | 0.0016396 |
| gpt-5.6-luna/2 | summary/baseline | answer | TRUE | complete | 2 | 2421 | 0.0009202 |
| gpt-5.6-luna/3 | history/budget-aware | retrieve | TRUE | complete | 4 | 3826 | 0.00141416 |
| gpt-5.6-luna/3 | history/budget-aware | answer | TRUE | complete | 2 | 5660 | 0.001528 |
| gpt-5.6-luna/3 | summary/baseline | answer | TRUE | complete | 2 | 2743 | 0.0013066 |
| gpt-5.6-luna/3 | history/baseline | answer | TRUE | complete | 4 | 6725 | 0.00208982 |

Raw JSON records individual scores, run IDs, source references, attempts, usage, phase outcomes, latency, and prompts.
History requested counts continuation request occurrences, including calls stopped before adapter dispatch by runtime, permission or schema checks. Adapter refusals count budget, invalid, cancelled and unavailable responses; legacy unrecorded fields remain unknown.
Successful payload counts require nonempty source text or excerpts and exclude stale, missing and rejected responses. Legacy audits without source-byte counts remain unknown. Unknown phase usage remains NA; undispatched phases use zero.
Preparation cost is shared once per trial; continuation costs include every phase and remain separate.
Inspect individual matched outcomes and missing/failed trials before drawing conclusions.
A small synthetic pilot cannot establish model equivalence or justify recursive analysis by itself.
