# Create a compaction result

Describes one compaction.
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md)`$compact()`
and `$last_compaction()` return it; you rarely need to create one
yourself. It is read-only; read fields with `$`. `attempts` holds the
original error conditions, so pick out the fields you need rather than
saving or logging it whole.

## Usage

``` r
DeputyCompaction(
  method,
  automatic,
  turns_compacted,
  turns_kept,
  estimated_tokens = NULL,
  usage = AgentUsage(),
  summary = NULL,
  attempts = list(),
  run_id = NULL
)
```

## Arguments

- method:

  How the summary was made: `"llm"` (by the model), `"text"` (the plain
  fallback), `"custom"` (passed to `$compact()`) or `"hook"` (from a
  `PreCompact` hook). `"none"` means there was nothing to compact and
  `"cancelled"` means a hook cancelled it.

- automatic:

  Whether a run compacted automatically.

- turns_compacted:

  Number of turns removed from the model context.

- turns_kept:

  Number of turns kept.

- estimated_tokens:

  Estimated context size before compaction, or `NULL`.

- usage:

  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  of the summary requests, including failed ones.

- summary:

  The summary text, or `NULL` if nothing was replaced.

- attempts:

  List of summary attempts, each with `fallback_index`, `provider`,
  `model`, `usage` and the error `condition` (or `NULL`).

- run_id:

  ID of the run that compacted, or `NULL` for a manual compaction.

## Value

A `DeputyCompaction` object.

## Additional properties

- `@compacted_at`:

  When the result was created, as a `POSIXct` value.

## Examples

``` r
outcome <- DeputyCompaction("custom", FALSE, 4, 2, summary = "Earlier work")
outcome$turns_compacted
#> [1] 4
S7::props(outcome$usage)
#> $requests
#> [1] 0
#> 
#> $tool_calls
#> [1] 0
#> 
#> $input_tokens
#> [1] 0
#> 
#> $output_tokens
#> [1] 0
#> 
#> $cached_tokens
#> [1] 0
#> 
#> $total_tokens
#> [1] 0
#> 
#> $cost_usd
#> [1] 0
#> 
```
