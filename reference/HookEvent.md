# Hook events supported by deputy

Hook events are fired at specific points during agent execution. Each
event type has a specific callback signature and context structure.

## Usage

``` r
HookEvent
```

## Format

An object of class `character` of length 8.

## Event Types

**PreToolUse** - Before a tool is executed (can deny)

Callback signature: `function(tool_name, tool_input, context)`

- `tool_name`: Name of the tool being called (character)

- `tool_input`: Named list of arguments passed to the tool

- `context`: List containing `working_dir` and `tool_annotations` (if
  available)

- Return:
  [`HookResultPreToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPreToolUse.md)
  to allow/deny

**PostToolUse** - After a tool completes

Callback signature:
`function(tool_name, tool_result, tool_error, context)`

- `tool_name`: Name of the tool that was called (character)

- `tool_result`: Result returned by the tool (or NULL on error)

- `tool_error`: Error message if tool failed (or NULL on success)

- `context`: List containing `working_dir` (current directory)

- Return:
  [`HookResultPostToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPostToolUse.md)
  to continue/stop

**Stop** - When the agent stops

Callback signature: `function(reason, context)`

- `reason`: Why the agent stopped ("complete", "max_turns", "error")

- `context`: List containing `working_dir`, `total_turns`, `cost`

- Return:
  [`HookResultStop()`](https://jameshwade.github.io/deputy/reference/HookResultStop.md)

**SubagentStop** - When a sub-agent completes (LeadAgent only)

Callback signature: `function(agent_name, task, result, context)`

- `agent_name`: Name of the sub-agent that completed (character)

- `task`: The task that was delegated (character)

- `result`: Result returned by the sub-agent

- `context`: List containing `working_dir`

- Return:
  [`HookResultSubagentStop()`](https://jameshwade.github.io/deputy/reference/HookResultSubagentStop.md)

**UserPromptSubmit** - When a user prompt is submitted

Callback signature: `function(prompt, context)`

- `prompt`: The user's prompt text (character)

- `context`: List containing `working_dir`

- Return: NULL (informational only)

**PreCompact** - Before conversation compaction

Callback signature: `function(turns_to_compact, turns_to_keep, context)`

- `turns_to_compact`: List of turns that will be compacted into a
  summary

- `turns_to_keep`: List of recent turns that will be preserved

- `context`: List containing `working_dir`, `total_turns`,
  `compact_count`

- Return:
  [`HookResultPreCompact()`](https://jameshwade.github.io/deputy/reference/HookResultPreCompact.md)
  to allow/cancel or provide custom summary

**SessionStart** - When an agent session begins

Callback signature: `function(context)`

- `context`: List containing `working_dir`, `permissions`, `provider`,
  `tools_count`

- Return:
  [`HookResultSessionStart()`](https://jameshwade.github.io/deputy/reference/HookResultSessionStart.md)

**SessionEnd** - When an agent session ends

Callback signature: `function(reason, context)`

- `reason`: Why the agent stopped ("complete", "max_turns",
  "cost_limit", "hook_requested_stop")

- `context`: List containing `working_dir`, `total_turns`, `cost`

- Return:
  [`HookResultSessionEnd()`](https://jameshwade.github.io/deputy/reference/HookResultSessionEnd.md)

## Context Structure

The context parameter is always a named list. Common fields:

- `working_dir`: The agent's current working directory

- `tool_annotations`: (PreToolUse only) Tool annotations from ellmer if
  available

- `total_turns`: (Stop, PreCompact, SessionEnd) Number of turns in the
  conversation

- `cost`: (Stop, SessionEnd) List with `total`, `input_tokens`,
  `output_tokens`

- `compact_count`: (PreCompact only) Number of turns being compacted

- `permissions`: (SessionStart only) The agent's permissions
  configuration

- `provider`: (SessionStart only) List with `name` and `model`

- `tools_count`: (SessionStart only) Number of registered tools

## Examples

``` r
if (FALSE) { # \dontrun{
# PreToolUse callback example
agent$add_hook(HookMatcher$new(
  event = "PreToolUse",
  callback = function(tool_name, tool_input, context) {
    message("Tool: ", tool_name, " in ", context$working_dir)
    HookResultPreToolUse(permission = "allow")
  }
))

# PostToolUse callback example
agent$add_hook(HookMatcher$new(
  event = "PostToolUse",
  callback = function(tool_name, tool_result, tool_error, context) {
    if (!is.null(tool_error)) {
      warning("Tool failed: ", tool_error)
    }
    HookResultPostToolUse()
  }
))
} # }
```
