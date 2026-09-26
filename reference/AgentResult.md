# Create an agent run result

An `AgentResult` describes one finished run.
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md)`$run_sync()`,
`$run_async()` and `$last_run()` return one; you rarely need to create
it yourself. It holds the final response, the conversation turns, every
[AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md),
usage and cost, and IDs that link the run to its agent and session.

Results are read-only. Read fields with `$`, for example
`result$response`, or use
[`result_n_turns()`](https://jameshwade.github.io/deputy/reference/result_n_turns.md),
[`result_tool_calls()`](https://jameshwade.github.io/deputy/reference/result_tool_calls.md),
[`result_tool_results()`](https://jameshwade.github.io/deputy/reference/result_tool_results.md),
[`result_text_chunks()`](https://jameshwade.github.io/deputy/reference/result_text_chunks.md)
and
[`result_is_success()`](https://jameshwade.github.io/deputy/reference/result_is_success.md).

`usage` covers this run only, but `cost` covers the whole conversation,
including earlier runs and turns that compaction removed from the model
context.

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

  List of ellmer turns in the model context when the run ended.

- cost:

  Cost summary (as from
  [Agent](https://jameshwade.github.io/deputy/reference/Agent.md)`$cost()`),
  or `NULL`. `total` is `NA` if some responses had no cost.

- events:

  List of
  [AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
  objects.

- duration:

  Run time in seconds, or `NULL`.

- stop_reason:

  Why the run stopped: `"complete"` if the model finished, otherwise a
  reason such as `"request_limit"`, `"interrupted"` or `"error"`.

- structured_output:

  Extracted structured data, if any.

- session_id, run_id, agent_id, agent_name, parent_agent_id,
  parent_run_id, delegation_id:

  Optional ID strings linking the run to its session and agent and, for
  a subagent, to the parent run and delegation.

- usage:

  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  for this run only, or `NULL`.

- run_context:

  The run's `run_context`, a named list.

## Value

An `AgentResult` object.

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
