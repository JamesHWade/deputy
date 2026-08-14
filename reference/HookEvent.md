# Hook events supported by deputy

Hook events are fired at specific points during agent execution. Each
event type has a specific callback signature and context structure.

## Usage

``` r
HookEvent
```

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

**PostToolUseFailure** - After a tool reports an error

Callback signature:
`function(tool_name, tool_result, tool_error, context)`

- Same arguments as PostToolUse, fired only when `tool_error` is not
  NULL

**Stop** - When the agent stops

Callback signature: `function(reason, context)`

- `reason`: Why the agent stopped (for example `"complete"`,
  `"request_limit"`, `"cost_limit"`, or `"provider_error"`)

- `context`: List containing `working_dir`, `usage`, `run_id`, and
  `cost`; native `run()` also includes `total_turns`

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

**SubagentStart** - When a delegated sub-agent starts (LeadAgent only)

Callback signature: `function(agent_name, task, context)`

- `agent_name`: Name of the sub-agent that started

- `task`: The delegated task

- `context`: List containing `working_dir`

**PermissionRequest** - When permission policy denies a tool call

Callback signature:
`function(tool_name, tool_input, permission_result, context)`

- Return:
  [`PermissionResultAllow()`](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md)
  to override the denial, or
  [`PermissionResultDeny()`](https://jameshwade.github.io/deputy/reference/PermissionResultDeny.md)
  to replace the denial reason

**ConfigChange** - When runtime configuration changes

Callback signature: `function(key, old_value, new_value, context)`

**UserPromptSubmit** - When a user prompt is submitted

Callback signature: `function(prompt, context)`

- `prompt`: The user's prompt text (character)

- `context`: List containing `working_dir`

- Return: NULL (informational only)

**Notification** - Informational runtime notice

Callback signature: `function(message, context)`

- `message`: The notification text (character)

- `context`: List containing `working_dir`, `level`, `code`, and any
  event-specific metadata

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

- `reason`: Why the agent stopped (for example `"complete"`,
  `"request_limit"`, `"cost_limit"`, or `"hook_requested_stop"`)

- `context`: List containing `working_dir`, `usage`, `run_id`, and
  `cost`; native `run()` also includes `total_turns`

- Return:
  [`HookResultSessionEnd()`](https://jameshwade.github.io/deputy/reference/HookResultSessionEnd.md)

## Context Structure

The context parameter is always a named list. Common fields:

- `working_dir`: The agent's current working directory

- `tool_annotations`: (PreToolUse only) Tool annotations from ellmer if
  available

- `usage`: Run-scoped
  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  for tool and terminal lifecycle hooks

- `usage_limits`: Active
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for tool lifecycle hooks

- `run_id`: Identifier for the active run

- `session_id`: Session identifier when compatibility persistence is
  configured

- `total_turns`: (native Stop, PreCompact, native SessionEnd)
  Conversation turns

- `cost`: (Stop, SessionEnd) List with `input`, `output`, `cached`, and
  `total`

- `compact_count`: (PreCompact only) Number of turns being compacted

- `level`: (Notification only) Informational severity such as `"info"`
  or `"warning"`

- `code`: (Notification only) Stable notification code when available

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
