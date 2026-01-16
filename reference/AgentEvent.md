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

- `"tool_start"` - Tool execution starting. Contains: `tool_name`,
  `tool_input`

- `"tool_end"` - Tool execution completed. Contains: `tool_name`,
  `tool_result`, `tool_error`

- `"text"` - Text chunk from LLM. Contains: `text`, `is_complete`

- `"text_complete"` - Full text response. Contains: `text`

- `"turn"` - Turn completed. Contains: `turn`, `turn_number`

- `"warning"` - Warning condition occurred. Contains: `message`,
  `details`

- `"stop"` - Agent stopped. Contains: `reason`, `total_turns`, `cost`

## Examples

``` r
# Create a start event
AgentEvent("start", task = "Analyze data.csv")
#> <AgentEvent: start >
#>   timestamp: 2026-01-16 01:02:56 
#>   task: Analyze data.csv

# Create a text event
AgentEvent("text", text = "Hello", is_complete = FALSE
)
#> <AgentEvent: text >
#>   timestamp: 2026-01-16 01:02:56 
#>   text: Hello
#>   is_complete: FALSE
```
