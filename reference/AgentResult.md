# Create a completed agent result

A read-only S7 snapshot of a governed run. It contains original ellmer
turns, Deputy events, usage, and correlation metadata. Read properties
with `S7::prop(result, "response")` or `$`; use
[`result_n_turns()`](https://jameshwade.github.io/deputy/reference/result_n_turns.md),
[`result_tool_calls()`](https://jameshwade.github.io/deputy/reference/result_tool_calls.md),
[`result_tool_results()`](https://jameshwade.github.io/deputy/reference/result_tool_results.md),
[`result_text_chunks()`](https://jameshwade.github.io/deputy/reference/result_text_chunks.md),
and
[`result_is_success()`](https://jameshwade.github.io/deputy/reference/result_is_success.md)
for inspection.

All properties are read-only, including previously writable R6 fields.
Ordinary nested lists use R value semantics. Embedded provider objects,
conditions, environments, and closures retain their own reference
semantics; the result does not deep-copy or sanitize their contents. Run
context is separately normalized to canonical JSON-compatible values.

## Usage

``` r
AgentResult(
  response = NULL,
  turns = list(),
  cost = list(input = 0, output = 0, cached = 0, total = 0, complete = TRUE, missing =
    0L),
  events = list(),
  duration = NULL,
  stop_reason = "complete",
  structured_output = NULL,
  session_id = NULL,
  run_id = NULL,
  usage = AgentUsage(),
  agent_id = NULL,
  agent_name = NULL,
  parent_agent_id = NULL,
  parent_run_id = NULL,
  delegation_id = NULL,
  run_context = list()
)
```

## Arguments

- response:

  Final text response, or `NULL`.

- turns:

  List of original conversation turns.

- cost:

  Cost information, including provider coverage metadata, or `NULL`. An
  incomplete total is `NA_real_`.

- events:

  List of
  [AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
  objects.

- duration:

  Finite, nonnegative duration in seconds, or `NULL`.

- stop_reason:

  One nonempty stop-reason string.

- structured_output:

  Parsed structured output, if any.

- session_id, run_id, agent_id, agent_name, parent_agent_id,
  parent_run_id, delegation_id:

  Optional nonempty correlation and identity strings.

- usage:

  Run-scoped
  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md),
  or `NULL`.

- run_context:

  Canonical product context for the run.

## Value

An `AgentResult` S7 object.

## Examples

``` r
result <- AgentResult(response = "Done", events = list(
  AgentEvent("text", text = "Done")
))
result_is_success(result)
#> [1] TRUE
result_text_chunks(result)
#> [1] "Done"
```
