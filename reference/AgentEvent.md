# Create an agent event

Agent events are yielded by the `run()` generator to provide streaming
updates on agent progress.

## Usage

``` r
AgentEvent(type, ...)
```

## Arguments

- type:

  Event type (see Event Types section)

- ...:

  Additional event data

## Value

An `AgentEvent` object

## Event Types

- `"start"` - Task started. Contains: `task`

- `"tool_start"` - Tool execution starting. Contains: `tool_call_id`,
  `tool_name`, and `tool_input`

- `"tool_end"` - Tool execution completed. Contains: `tool_call_id`,
  `tool_name`, `tool_result`, and `tool_error`

- `"text"` - Text chunk from LLM. Contains: `text`, `is_complete`

- `"text_complete"` - Full text response. Contains: `text`

- `"turn"` - Turn completed. Contains: `turn`, `turn_number`

- `"warning"` - Warning condition occurred. Contains: `message`,
  `details`

- `"content"` - Non-text provider content. Contains: `content`,
  `content_type`

- `"request_start"`, `"request_end"`, `"request_error"` - Governed model
  dispatch evidence with provider, model, request number, and original
  HTTP/transport conditions on errors. These are not individual HTTP
  retry attempts. Unclassified application errors are retained as
  `"run_error"`.

- `"run_error"` - Terminal initialization, streaming, or
  structured-output failure, with its phase and original condition.
  Application callbacks and validation do not turn a successful response
  into a `"request_error"`.

- `"fallback"` - Explicit Chat selection, prior condition, and usage.

- `"structured_attempt"` - Structured value, available turn, validation
  outcome, feedback, and condition. May contain sensitive application
  data.

- `"permission"`, `"hook"`, `"compaction"` - Governance decisions and
  lifecycle.

- `"file_checkpoint"` - Automatic run-boundary checkpoint. Contains:
  `checkpoint_id`, `name`

- `"usage"` - Run usage snapshot. Contains: `usage`, `limits`

- `"stop"` - Agent stopped. Contains: `reason`, `total_turns`, `cost`,
  `usage`, and `run_id`

Run-boundary and tool lifecycle events also carry `agent_id`, `run_id`,
immutable `run_context`, and delegated-run correlation fields when
applicable.

## Examples

``` r
# Create a start event
AgentEvent("start", task = "Analyze data.csv")
#> <AgentEvent: start >
#>   timestamp: 2026-09-05 09:59:34 
#>   task: Analyze data.csv

# Create a text event
AgentEvent("text", text = "Hello", is_complete = FALSE
)
#> <AgentEvent: text >
#>   timestamp: 2026-09-05 09:59:34 
#>   text: Hello
#>   is_complete: FALSE
```
