# Bounded history recovery pilot

Synthetic evidence-review trajectories; this pilot does not establish production performance.

Case: assay-review-changed-constraint-v1

Recorded 6 scored continuations and 44 governed requests. Cost: 0.08900706 USD.

| Helper / strategy | Trials | Mean score | Fully correct | Median seconds | Repeated effects |
| --- | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/summary | 3 | 0.733 | 0 | 10.71 | 0 |
| gpt-5.6-luna/history | 3 | 0.300 | 0 | 7.19 | 0 |

| Paired trial | History minus summary score | Shared preparation requests | Shared preparation USD |
| --- | ---: | ---: | ---: |
| gpt-5.6-luna/1 | -0.7 | 10 | 0.02681616 |
| gpt-5.6-luna/2 | 0.1 | 10 | 0.02714156 |
| gpt-5.6-luna/3 | -0.7 | 10 | 0.02681156 |

Expected 6 continuations; missing 0.

| Trial | Strategy | Score | Requests | Tokens | USD | Seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary | 0.700 | 2 | 2801 | 0.0012972 | 9.59 |
| gpt-5.6-luna/1 | history | 0.000 | 2 | 3151 | 0.0008682 | 7.19 |
| gpt-5.6-luna/2 | history | 0.900 | 4 | 6878 | 0.00225778 | 14.17 |
| gpt-5.6-luna/2 | summary | 0.800 | 2 | 3078 | 0.0013426 | 10.71 |
| gpt-5.6-luna/3 | summary | 0.700 | 2 | 3243 | 0.0016476 | 18.10 |
| gpt-5.6-luna/3 | history | 0.000 | 2 | 2707 | 0.0008244 | 4.95 |

| Trial | Strategy | Failed checks | History calls / bytes | Completed writes | Export attempts |
| --- | --- | --- | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary | source_page, completed_effect, grounded_sources | 0 / 0 | 1 | 0 |
| gpt-5.6-luna/1 | history | current_constraint, denominator, corrected_source, source_page, unresolved_work, d_classification, f_classification, completed_effect, authority, grounded_sources | 5 / 3578 | 1 | 0 |
| gpt-5.6-luna/2 | history | completed_effect | 8 / 3204 | 1 | 0 |
| gpt-5.6-luna/2 | summary | completed_effect, grounded_sources | 0 / 0 | 1 | 0 |
| gpt-5.6-luna/3 | summary | source_page, completed_effect, grounded_sources | 0 / 0 | 1 | 0 |
| gpt-5.6-luna/3 | history | current_constraint, denominator, corrected_source, source_page, unresolved_work, d_classification, f_classification, completed_effect, authority, grounded_sources | 8 / 2401 | 1 | 0 |

Raw JSON records individual scores, run IDs, source references, attempts, usage, latency, and prompts.
Preparation cost is shared once per paired trial; continuation costs remain separate.
Inspect individual paired outcomes and missing/failed trials before drawing conclusions.
A small synthetic pilot cannot establish model equivalence or justify recursive analysis by itself.
