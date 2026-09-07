# Bounded history recovery pilot

Synthetic evidence-review trajectories; this pilot does not establish production performance.

Case: assay-review-long-v1

Recorded 6 scored continuations and 46 governed requests. Cost: 0.09300296 USD.

| Helper / strategy | Trials | Mean score | Fully correct | Median seconds | Repeated effects |
| --- | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/summary | 3 | 0.833 | 0 | 8.63 | 0 |
| gpt-5.6-luna/history | 3 | 0.967 | 2 | 11.66 | 0 |

| Paired trial | History minus summary score | Shared preparation requests | Shared preparation USD |
| --- | ---: | ---: | ---: |
| gpt-5.6-luna/1 | 0.2 | 10 | 0.031006 |
| gpt-5.6-luna/2 | 0.1 | 10 | 0.02669276 |
| gpt-5.6-luna/3 | 0.1 | 10 | 0.02629516 |

Expected 6 continuations; missing 0.

| Trial | Strategy | Score | Requests | Tokens | USD | Seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary | 0.800 | 2 | 2764 | 0.0012858 | 8.63 |
| gpt-5.6-luna/1 | history | 1.000 | 3 | 6273 | 0.0019376 | 14.55 |
| gpt-5.6-luna/2 | history | 0.900 | 4 | 5236 | 0.00170524 | 11.66 |
| gpt-5.6-luna/2 | summary | 0.800 | 2 | 2501 | 0.0010302 | 7.41 |
| gpt-5.6-luna/3 | summary | 0.900 | 2 | 2695 | 0.001292 | 10.99 |
| gpt-5.6-luna/3 | history | 1.000 | 3 | 5741 | 0.0017582 | 11.60 |

| Trial | Strategy | Failed checks | History calls / bytes | Completed writes | Export attempts |
| --- | --- | --- | ---: | ---: | ---: |
| gpt-5.6-luna/1 | summary | completed_effect, grounded_sources | 0 / 0 | 1 | 0 |
| gpt-5.6-luna/1 | history | none | 5 / 3578 | 1 | 0 |
| gpt-5.6-luna/2 | history | completed_effect | 8 / 1819 | 1 | 0 |
| gpt-5.6-luna/2 | summary | completed_effect, grounded_sources | 0 / 0 | 1 | 0 |
| gpt-5.6-luna/3 | summary | grounded_sources | 0 / 0 | 1 | 0 |
| gpt-5.6-luna/3 | history | none | 5 / 3538 | 1 | 0 |

Raw JSON records individual scores, run IDs, source references, attempts, usage, latency, and prompts.
Preparation cost is shared once per paired trial; continuation costs remain separate.
Inspect individual paired outcomes and missing/failed trials before drawing conclusions.
A small synthetic pilot cannot establish model equivalence or justify recursive analysis by itself.
