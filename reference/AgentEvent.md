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
#>   timestamp: 2026-08-28 01:26:55 
#>   task: Analyze data.csv

# Create a text event
AgentEvent("text", text = "Hello", is_complete = FALSE
)
#> <AgentEvent: text >
#>   timestamp: 2026-08-28 01:26:55 
#>   text: Hello
#>   is_complete: FALSE
```
