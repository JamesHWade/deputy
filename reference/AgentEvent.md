# Create an agent event

[Agent](https://jameshwade.github.io/deputy/reference/Agent.md)`$run()`
yields these events as the agent works, and an
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
keeps them in `events`. Each event has a `type`, a `timestamp` and a
named list of `data`. Check `event$type` to tell events apart, and read
data fields directly with `$`, for example `event$text`. A field that
isn't there returns `NULL`. Events are read-only.

## Usage

``` r
AgentEvent(type, ...)
```

## Arguments

- type:

  Event type (see the "Event types" section).

- ...:

  Named event data. Names must be unique and can't be `type`,
  `timestamp` or `data`.

## Value

An `AgentEvent` object.

## Event types

- `"start"`: the run started. `task`.

- `"request_start"`, `"request_end"`, `"request_error"`: a model request
  started, finished or failed, with the provider, model and request
  number. `"request_error"` carries the original `condition`. ellmer's
  HTTP retries are not separate requests.

- `"text"`: a streamed chunk of the reply. `text`, `is_complete`.

- `"text_complete"`: the full reply. `text`.

- `"content"`: other content from the provider. `content`,
  `content_type`.

- `"tool_start"`: a tool call is about to run. `tool_call_id`,
  `tool_name`, `tool_input`.

- `"tool_end"`: a tool call finished. `tool_call_id`, `tool_name`,
  `tool_result`, `tool_error`.

- `"turn"`: a turn finished. `turn`, `turn_number`.

- `"permission"`, `"hook"`: a permission decision or hook result.

- `"approval"`: a tool call is waiting for approval. `approval_id`,
  `path`, `tool_name`, `tool_input`, `reason`.

- `"trusted_result"`: a trusted tool returned a value (see
  [TrustedResults](https://jameshwade.github.io/deputy/reference/TrustedResults.md)).
  `result_id`, `result_type`, `tool_name`, `value`.

- `"compaction_start"`, `"compaction"`, `"compaction_error"`: automatic
  compaction started, finished or failed.

- `"fallback"`: a fallback Chat took over after a transient error.
  `fallback_index`, `condition`, `usage`.

- `"structured_attempt"`: one attempt at structured output, with the
  `value`, whether it was `valid` and any `feedback`. It may hold
  sensitive data.

- `"file_checkpoint"`: a file checkpoint was created at the start of the
  run. `checkpoint_id`, `name`.

- `"run_error"`: the run failed. `phase` and the original `condition`.

- `"usage"`: the run's usage. `usage`, `limits`.

- `"stop"`: the run ended. `reason`, `cost`, `usage`, and `limit`
  (details of the usage limit that stopped the run, or `NULL`).

Events also carry the `run_id`. All but `"text"`, `"text_complete"` and
`"content"` carry `agent_id`, `session_id` and `run_context` too, plus
parent and delegation IDs in subagent runs.

## Additional properties

- `@timestamp`:

  When the event was created, as a `POSIXct` value.

- `@data`:

  Named list of event data.

## Examples

``` r
# Create a start event
AgentEvent("start", task = "Analyze data.csv")
#> <AgentEvent: start >
#>   timestamp: 2026-09-26 23:28:42
#>   task: Analyze data.csv

# Create a text event
event <- AgentEvent("text", text = "Hello", is_complete = FALSE)
event$text
#> [1] "Hello"
```
