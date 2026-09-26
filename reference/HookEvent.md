# Hook events

`HookEvent` lists the events you can attach a hook to with
[`HookMatcher()`](https://jameshwade.github.io/deputy/reference/HookMatcher.md).

When several hooks match an event, they run in the order they were
added. The first callback that returns a non-`NULL` value decides the
outcome, and the remaining hooks for that event don't run. If a
PreToolUse callback errors or times out, the tool call is denied. Errors
in other callbacks are reported and the run continues.

## Usage

``` r
HookEvent
```

## Events

Each entry shows the event with its callback's arguments, then when it
fires.

- `PreToolUse(tool_name, tool_input, context)`: before a tool runs, once
  the permission policy has allowed it.

- `PostToolUse(tool_name, tool_result, tool_error, context)`: after a
  tool call finishes, whether or not it failed.

- `PostToolUseFailure(tool_name, tool_result, tool_error, context)`:
  after `PostToolUse`, when the tool failed.

- `PermissionRequest(tool_name, tool_input, permission_result, context)`:
  when the permission policy denies a call.

- `SessionStart(context)`: at the start of each run.

- `UserPromptSubmit(prompt, context)`: at the start of each run, after
  `SessionStart`.

- `Stop(reason, context)`: at the end of each run.

- `SessionEnd(reason, context)`: at the end of each run, after `Stop`.

- `SubagentStart(agent_name, task, context)`: when a subagent starts a
  delegated task.

- `SubagentStop(agent_name, task, result, context)`: when a subagent
  finishes.

- `PreCompact(turns_to_compact, turns_to_keep, context)`: before older
  turns are summarised.

- `PostCompact(result, context)`: after compaction.

- `Notification(message, context)`: when the agent reports something,
  such as a denied call.

- `ConfigChange(key, old_value, new_value, context)`: when
  `set_permission_mode()` changes the mode.

`tool_input` is the named list of tool arguments. After a successful
call `tool_error` is `NULL`; after a failure `tool_result` is `NULL` and
`tool_error` holds the error message. `reason` is the stop reason, such
as `"complete"`, `"request_limit"`, `"cost_limit"`, `"tool_loop"`,
`"hook_requested_stop"` or `"provider_error"`. `result` is the
subagent's result for `SubagentStop` and the
[DeputyCompaction](https://jameshwade.github.io/deputy/reference/DeputyCompaction.md)
for `PostCompact`. For `ConfigChange`, `key` is `"permission_mode"`.

Four events use the callback's return value:

- `PreToolUse`: return
  [`HookResultPreToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPreToolUse.md)
  to allow or deny the call, or to stop the run.

- `PostToolUse`: return
  [`HookResultPostToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPostToolUse.md)
  to stop the run or to change what the `tool_end` event shows.

- `PermissionRequest`: return
  [`PermissionResultAllow()`](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md)
  to allow the call anyway, or
  [`PermissionResultDeny()`](https://jameshwade.github.io/deputy/reference/PermissionResultDeny.md)
  to change the reason.

- `PreCompact`: return
  [`HookResultPreCompact()`](https://jameshwade.github.io/deputy/reference/HookResultPreCompact.md)
  to cancel compaction or to supply your own summary.

Other events ignore the return value. Returning `NULL` means "no
decision".

## Context

`context` is a named list. Every event includes:

- `working_dir`: the agent's working directory.

- `agent_id`, `agent_name`, `session_id`: the agent's identifiers.

- `run_id`: the current run, when one is active.

- `run_context`: the run's `run_context` list.

- `parent_agent_id`, `parent_run_id`, `delegation_id`: set in subagent
  runs.

Some events add fields:

- `tool_call_id`, `permission_mode`, `usage`, `usage_limits` (tool
  events): the call's ID, the permission mode, the run's
  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  so far and its
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md).

- `tool_annotations`, `tool_arguments`, `tool_metadata` (PreToolUse,
  PermissionRequest): the tool's annotations, declared arguments and
  [`tool_metadata()`](https://jameshwade.github.io/deputy/reference/tool_metadata.md),
  when available.

- `usage`, `cost` (Stop, SessionEnd): the run's
  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  and the conversation's cost, as returned by `agent$cost()`.

- `total_turns`, `compact_count` (PreCompact, PostCompact): the number
  of turns in the conversation and the number being summarised.

- `automatic` (PostCompact): `TRUE` when compaction ran automatically
  during a run rather than through `compact()`.

- `child_agent_id`, `child_run_id`, `status` (SubagentStart,
  SubagentStop): the subagent's identifiers and status.

- `level`, `code` (Notification): a severity such as `"info"` or
  `"warning"`, and a notification code when there is one.

- `permissions`, `provider`, `tools_count` (SessionStart): the agent's
  [Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md),
  a list with the provider `name` and `model`, and the number of
  registered tools.

## See also

[`vignette("hooks")`](https://jameshwade.github.io/deputy/articles/hooks.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Log each tool call. Returning NULL leaves the decision to other hooks.
agent$add_hook(HookMatcher(
  event = "PreToolUse",
  callback = function(tool_name, tool_input, context) {
    message("Tool: ", tool_name, " in ", context$working_dir)
    NULL
  }
))

# Stop the run when a tool fails
agent$add_hook(HookMatcher(
  event = "PostToolUse",
  callback = function(tool_name, tool_result, tool_error, context) {
    if (!is.null(tool_error)) {
      return(HookResultPostToolUse(continue = FALSE))
    }
    NULL
  }
))
} # }
```
