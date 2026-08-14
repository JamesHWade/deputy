# HookMatcher R6 Class

Defines when a hook callback should be triggered. Hooks can be filtered
by event type and optionally by tool name pattern.

**Security Note:** Hook matcher configuration is read-only from the
public API after construction so callbacks and matching rules cannot be
swapped out accidentally at runtime.

## Active bindings

- `event`:

  The hook event type (see
  [HookEvent](https://jameshwade.github.io/deputy/reference/HookEvent.md)).
  Read-only after construction.

- `pattern`:

  Optional regex pattern for tool name filtering. Read-only after
  construction.

- `callback`:

  The function to call when the hook fires. Read-only after
  construction.

- `timeout`:

  Maximum execution time for the callback in seconds. Read-only after
  construction.

## Methods

### Public methods

- [`HookMatcher$new()`](#method-HookMatcher-initialize)

- [`HookMatcher$matches()`](#method-HookMatcher-matches)

- [`HookMatcher$print()`](#method-HookMatcher-print)

- [`HookMatcher$clone()`](#method-HookMatcher-clone)

------------------------------------------------------------------------

### `HookMatcher$new()`

Create a new HookMatcher.

#### Usage

    HookMatcher$new(event, callback, pattern = NULL, timeout = 30)

#### Arguments

- `event`:

  The event type (must be one of
  [HookEvent](https://jameshwade.github.io/deputy/reference/HookEvent.md))

- `callback`:

  Function to call. Signature depends on event type:

  - PreToolUse: `function(tool_name, tool_input, context)`

  - PostToolUse: `function(tool_name, tool_result, tool_error, context)`

  - PostToolUseFailure:
    `function(tool_name, tool_result, tool_error, context)`

  - Stop: `function(reason, context)`

  - SubagentStart: `function(agent_name, task, context)`

  - SubagentStop: `function(agent_name, task, result, context)`

  - UserPromptSubmit: `function(prompt, context)`

  - Notification: `function(message, context)`

  - PermissionRequest:
    `function(tool_name, tool_input, permission_result, context)`

  - ConfigChange: `function(key, old_value, new_value, context)`

  - PreCompact: `function(turns_to_compact, turns_to_keep, context)`

  - SessionStart: `function(context)`

  - SessionEnd: `function(reason, context)`

- `pattern`:

  Optional regex pattern to filter by tool name. Only applies to
  PreToolUse and PostToolUse events.

- `timeout`:

  Maximum callback execution time in seconds

#### Returns

A new `HookMatcher` object

#### Examples

    # Block dangerous bash commands
    HookMatcher$new(
      event = "PreToolUse",
      pattern = "^(run_bash|bash)$",
      callback = function(tool_name, tool_input, context) {
        if (grepl("rm -rf", tool_input$command)) {
          HookResultPreToolUse(permission = "deny", reason = "Dangerous!")
        } else {
          HookResultPreToolUse(permission = "allow")
        }
      }
    )

------------------------------------------------------------------------

### `HookMatcher$matches()`

Check if this hook matches a given tool name.

#### Usage

    HookMatcher$matches(tool_name = NULL)

#### Arguments

- `tool_name`:

  The tool name to check (can be NULL)

#### Returns

Logical indicating if the hook matches

------------------------------------------------------------------------

### `HookMatcher$print()`

Print the hook matcher.

#### Usage

    HookMatcher$print()

------------------------------------------------------------------------

### `HookMatcher$clone()`

The objects of this class are cloneable with this method.

#### Usage

    HookMatcher$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Examples

``` r

## ------------------------------------------------
## Method `HookMatcher$new()`
## ------------------------------------------------

if (FALSE) { # \dontrun{
# Block dangerous bash commands
HookMatcher$new(
  event = "PreToolUse",
  pattern = "^(run_bash|bash)$",
  callback = function(tool_name, tool_input, context) {
    if (grepl("rm -rf", tool_input$command)) {
      HookResultPreToolUse(permission = "deny", reason = "Dangerous!")
    } else {
      HookResultPreToolUse(permission = "allow")
    }
  }
)
} # }
```
