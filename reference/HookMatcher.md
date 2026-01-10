# HookMatcher R6 Class

Defines when a hook callback should be triggered. Hooks can be filtered
by event type and optionally by tool name pattern.

## Public fields

- `event`:

  The hook event type (see
  [HookEvent](https://jameshwade.github.io/deputy/reference/HookEvent.md))

- `pattern`:

  Optional regex pattern for tool name filtering

- `callback`:

  The function to call when the hook fires

- `timeout`:

  Maximum execution time for the callback in seconds

## Methods

### Public methods

- [`HookMatcher$new()`](#method-HookMatcher-new)

- [`HookMatcher$matches()`](#method-HookMatcher-matches)

- [`HookMatcher$print()`](#method-HookMatcher-print)

- [`HookMatcher$clone()`](#method-HookMatcher-clone)

------------------------------------------------------------------------

### Method `new()`

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

  - Stop: `function(reason, context)`

  - SubagentStop: `function(agent_name, task, result, context)`

  - UserPromptSubmit: `function(prompt, context)`

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

    \dontrun{
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
    }

------------------------------------------------------------------------

### Method `matches()`

Check if this hook matches a given tool name.

#### Usage

    HookMatcher$matches(tool_name = NULL)

#### Arguments

- `tool_name`:

  The tool name to check (can be NULL)

#### Returns

Logical indicating if the hook matches

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print the hook matcher.

#### Usage

    HookMatcher$print()

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    HookMatcher$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Examples

``` r
## ------------------------------------------------
## Method `HookMatcher$new`
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
