# Bounded history recovery pilot

Synthetic evidence-review trajectories; this pilot does not establish production performance.

Case: assay-review-resolved-methods-v1

Recorded 6 scored continuations and 46 governed requests. Cost: 0.08855886 USD.

| Helper / strategy | Trials | Mean score | Fully correct | Median seconds | Repeated effects |
| --- | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/summary | 3 | 0.900 | 0 | 9.16 | 0 |
| gpt-5.6-luna/history | 3 | 0.667 | 2 | 11.11 | 0 |

| Paired trial | History minus summary score | Shared preparation requests | Shared preparation USD |
| --- | ---: | ---: | ---: |
| gpt-5.6-luna/1 | 0.1 | 10 | 0.02671616 |
| gpt-5.6-luna/2 | 0.1 | 10 | 0.02651016 |
| gpt-5.6-luna/3 | -0.9 | 10 | 0.02675816 |

Expected 6 continuations; missing 0.

| Trial | Strategy | Score | Requests | Tokens | USD | Seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary | 0.900 | 2 | 2547 | 0.0010464 | 9.16 |
| gpt-5.6-luna/1 | history | 1.000 | 4 | 6000 | 0.00188248 | 11.11 |
| gpt-5.6-luna/2 | history | 1.000 | 4 | 6626 | 0.0020521 | 12.17 |
| gpt-5.6-luna/2 | summary | 0.900 | 2 | 2712 | 0.0012114 | 8.88 |
| gpt-5.6-luna/3 | summary | 0.900 | 2 | 3068 | 0.0014536 | 10.52 |
| gpt-5.6-luna/3 | history | 0.000 | 2 | 2992 | 0.0009284 | 6.11 |

| Trial | Strategy | Failed checks | History calls / bytes | Completed writes | Export attempts |
| --- | --- | --- | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary | grounded_sources | 0 / 0 | 1 | 0 |
| gpt-5.6-luna/1 | history | none | 7 / 3224 | 1 | 0 |
| gpt-5.6-luna/2 | history | none | 8 / 3986 | 1 | 0 |
| gpt-5.6-luna/2 | summary | grounded_sources | 0 / 0 | 1 | 0 |
| gpt-5.6-luna/3 | summary | grounded_sources | 0 / 0 | 1 | 0 |
| gpt-5.6-luna/3 | history | current_constraint, denominator, corrected_source, source_page, unresolved_work, d_classification, f_classification, completed_effect, authority, grounded_sources | 6 / 1970 | 1 | 0 |

Raw JSON records individual scores, run IDs, source references, attempts, usage, latency, and prompts.
Preparation cost is shared once per paired trial; continuation costs remain separate.
Inspect individual paired outcomes and missing/failed trials before drawing conclusions.
A small synthetic pilot cannot establish model equivalence or justify recursive analysis by itself.
