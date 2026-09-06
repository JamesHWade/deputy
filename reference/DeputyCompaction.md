# Record a conversation compaction outcome

[Agent](https://jameshwade.github.io/deputy/reference/Agent.md)`$compact()`
and `$last_compaction()` return this read-only S7 value. `$` and
[`S7::prop()`](https://rconsortium.github.io/S7/reference/prop.html)
read its properties.
[`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
returns a plain list for explicit reporting; nested usage must also be
projected for JSON. Original provider conditions in `attempts` retain
their identity and any reference semantics. Reporting code should select
safe evidence fields rather than serialize arbitrary conditions or
provider objects.

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

  Outcome: `"none"`, `"cancelled"`, `"custom"`, `"hook"`, `"llm"`, or
  `"text"`.

- automatic:

  Whether the run triggered compaction automatically.

- turns_compacted:

  Number of turns removed from the active context.

- turns_kept:

  Number of retained turns.

- estimated_tokens:

  Estimated context size before compaction, or `NULL` when unavailable.

- usage:

  An
  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  value for summary generation, including failed attempts. Unknown
  provider costs remain unknown.

- summary:

  Installed summary text, or `NULL` when no replacement occurred.

- attempts:

  List of summary attempt records containing `fallback_index`,
  `provider`, `model`, `usage`, and the original `condition` (or
  `NULL`).

- run_id:

  Governed run identifier, or `NULL` for manual compaction.

## Value

A read-only `DeputyCompaction` S7 object.

## Additional properties

- `@compacted_at`:

  Construction time as a `POSIXct` value. Read-only.

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
