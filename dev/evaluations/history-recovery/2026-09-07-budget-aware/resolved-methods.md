# Bounded history recovery pilot

Synthetic evidence-review trajectories; this pilot does not establish production performance.

Case: assay-review-resolved-methods-v1

Recorded 9 arms: 9 attempted and 0 undispatched. Governed requests: 62. Cost: 0.09823596 USD.

An attempted continuation with a missing structured answer receives zero under the fixed scoring rule. Undispatched arms are retained but excluded from scores, latency summaries and paired comparisons. Completion is reported separately from answer checks.

| Helper / strategy / protocol | Recorded arms | Attempted | Undispatched | Answers | Mean attempted score | Fully correct | Median completed seconds | Median incomplete seconds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/summary/baseline | 3 | 3 | 0 | 3 | 0.867 | 0 | 9.38 | not observed |
| gpt-5.6-luna/history/baseline | 3 | 3 | 0 | 3 | 1.000 | 3 | 11.74 | not observed |
| gpt-5.6-luna/history/budget-aware | 3 | 3 | 0 | 3 | 1.000 | 3 | 19.03 | not observed |

| Shared trial | History protocol | History minus summary score | History minus baseline history score | Shared preparation requests | Shared preparation USD |
| --- | --- | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/1 | baseline | 0.2 | 0 | 10 | 0.02667556 |
| gpt-5.6-luna/1 | budget-aware | 0.2 | 0 | 10 | 0.02667556 |
| gpt-5.6-luna/2 | baseline | 0.1 | 0 | 10 | 0.02657456 |
| gpt-5.6-luna/2 | budget-aware | 0.1 | 0 | 10 | 0.02657456 |
| gpt-5.6-luna/3 | budget-aware | 0.1 | 0 | 10 | 0.02638336 |
| gpt-5.6-luna/3 | baseline | 0.1 | 0 | 10 | 0.02638336 |

Expected 9 continuations; attempted 9; missing 0 (0 undispatched, 0 not recorded).
Shared preparation is counted once per trial, even when displayed beside multiple comparisons.

| Trial | Strategy / protocol | Dispatched | Answer | Score | Requests | Governed tool requests | Tokens | USD | Seconds | Stop reason |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| gpt-5.6-luna/1 | summary/baseline | TRUE | present | 0.800 | 2 | 0 | 2677 | 0.0011354 | 10.24 | complete |
| gpt-5.6-luna/1 | history/baseline | TRUE | present | 1.000 | 3 | 6 | 6183 | 0.0020116 | 11.44 | complete |
| gpt-5.6-luna/1 | history/budget-aware | TRUE | present | 1.000 | 6 | 6 | 9132 | 0.00313324 | 21.92 | complete |
| gpt-5.6-luna/2 | history/baseline | TRUE | present | 1.000 | 3 | 5 | 5859 | 0.0018078 | 12.98 | complete |
| gpt-5.6-luna/2 | history/budget-aware | TRUE | present | 1.000 | 5 | 6 | 8660 | 0.00297056 | 19.03 | complete |
| gpt-5.6-luna/2 | summary/baseline | TRUE | present | 0.900 | 2 | 0 | 2832 | 0.0012364 | 8.35 | complete |
| gpt-5.6-luna/3 | history/budget-aware | TRUE | present | 1.000 | 5 | 4 | 8957 | 0.00285878 | 16.41 | complete |
| gpt-5.6-luna/3 | summary/baseline | TRUE | present | 0.900 | 2 | 0 | 2775 | 0.001388 | 9.38 | complete |
| gpt-5.6-luna/3 | history/baseline | TRUE | present | 1.000 | 4 | 8 | 6833 | 0.0020607 | 11.74 | complete |

| Trial | Strategy / protocol | Failed checks | History requested | Adapter calls | Not dispatched | Adapter refusals | Searches with source payload | Reads with source payload | History bytes | Completed writes | Export attempts | Repeated exports |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary/baseline | source_page, grounded_sources | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| gpt-5.6-luna/1 | history/baseline | none | 6 | 6 | 0 | 0 | 1 | 5 | 2901 | 1 | 0 | 0 |
| gpt-5.6-luna/1 | history/budget-aware | none | 6 | 6 | 0 | 0 | 3 | 3 | 2965 | 1 | 0 | 0 |
| gpt-5.6-luna/2 | history/baseline | none | 5 | 5 | 0 | 0 | 5 | 0 | 3064 | 1 | 0 | 0 |
| gpt-5.6-luna/2 | history/budget-aware | none | 6 | 6 | 0 | 0 | 0 | 4 | 2206 | 1 | 0 | 0 |
| gpt-5.6-luna/2 | summary/baseline | source_page | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| gpt-5.6-luna/3 | history/budget-aware | none | 4 | 4 | 0 | 0 | 4 | 0 | 2473 | 1 | 0 | 0 |
| gpt-5.6-luna/3 | summary/baseline | grounded_sources | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 |
| gpt-5.6-luna/3 | history/baseline | none | 8 | 8 | 0 | 2 | 6 | 0 | 4611 | 1 | 0 | 0 |

| Trial | Strategy / protocol | Phase | Dispatched | Stop reason | Requests | Tokens | USD |
| --- | --- | --- | --- | --- | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary/baseline | answer | TRUE | complete | 2 | 2677 | 0.0011354 |
| gpt-5.6-luna/1 | history/baseline | answer | TRUE | complete | 3 | 6183 | 0.0020116 |
| gpt-5.6-luna/1 | history/budget-aware | retrieve | TRUE | complete | 4 | 2984 | 0.00135764 |
| gpt-5.6-luna/1 | history/budget-aware | answer | TRUE | complete | 2 | 6148 | 0.0017756 |
| gpt-5.6-luna/2 | history/baseline | answer | TRUE | complete | 3 | 5859 | 0.0018078 |
| gpt-5.6-luna/2 | history/budget-aware | retrieve | TRUE | complete | 3 | 3019 | 0.00143936 |
| gpt-5.6-luna/2 | history/budget-aware | answer | TRUE | complete | 2 | 5641 | 0.0015312 |
| gpt-5.6-luna/2 | summary/baseline | answer | TRUE | complete | 2 | 2832 | 0.0012364 |
| gpt-5.6-luna/3 | history/budget-aware | retrieve | TRUE | complete | 3 | 3583 | 0.00135598 |
| gpt-5.6-luna/3 | history/budget-aware | answer | TRUE | complete | 2 | 5374 | 0.0015028 |
| gpt-5.6-luna/3 | summary/baseline | answer | TRUE | complete | 2 | 2775 | 0.001388 |
| gpt-5.6-luna/3 | history/baseline | answer | TRUE | complete | 4 | 6833 | 0.0020607 |

Raw JSON records individual scores, run IDs, source references, attempts, usage, phase outcomes, latency, and prompts.
History requested counts continuation request occurrences, including calls stopped before adapter dispatch by runtime, permission or schema checks. Adapter refusals count budget, invalid, cancelled and unavailable responses; legacy unrecorded fields remain unknown.
Successful payload counts require nonempty source text or excerpts and exclude stale, missing and rejected responses. Legacy audits without source-byte counts remain unknown. Unknown phase usage remains NA; undispatched phases use zero.
Preparation cost is shared once per trial; continuation costs include every phase and remain separate.
Inspect individual matched outcomes and missing/failed trials before drawing conclusions.
A small synthetic pilot cannot establish model equivalence or justify recursive analysis by itself.
