# HookRegistry R6 Class

Manages a collection of hooks for an agent. Handles registration,
matching, and execution of hooks.

## Methods

### Public methods

- [`HookRegistry$new()`](#method-HookRegistry-new)

- [`HookRegistry$add()`](#method-HookRegistry-add)

- [`HookRegistry$get_hooks()`](#method-HookRegistry-get_hooks)

- [`HookRegistry$fire()`](#method-HookRegistry-fire)

- [`HookRegistry$last_errors()`](#method-HookRegistry-last_errors)

- [`HookRegistry$clear_errors()`](#method-HookRegistry-clear_errors)

- [`HookRegistry$count()`](#method-HookRegistry-count)

- [`HookRegistry$print()`](#method-HookRegistry-print)

- [`HookRegistry$clone()`](#method-HookRegistry-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new HookRegistry.

#### Usage

    HookRegistry$new()

------------------------------------------------------------------------

### Method `add()`

Add a hook to the registry.

#### Usage

    HookRegistry$add(hook)

#### Arguments

- `hook`:

  A
  [HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
  object

#### Returns

Invisible self for chaining

------------------------------------------------------------------------

### Method `get_hooks()`

Get all hooks for a specific event.

#### Usage

    HookRegistry$get_hooks(event, tool_name = NULL)

#### Arguments

- `event`:

  The event type

- `tool_name`:

  Optional tool name for filtering

#### Returns

List of matching HookMatcher objects

------------------------------------------------------------------------

### Method `fire()`

Fire hooks for an event and return the first non-NULL result.

Hook errors are handled as follows:

- **PreToolUse**: Errors result in denial (fail-safe security behavior)

- **Other events**: Errors are logged prominently and stored in the
  `last_errors` field, but execution continues to prevent cascade
  failures

#### Usage

    HookRegistry$fire(event, tool_name = NULL, ...)

#### Arguments

- `event`:

  The event type

- `tool_name`:

  Optional tool name for filtering (also passed to callback)

- `...`:

  Arguments to pass to the callback

#### Returns

The first non-NULL hook result, or NULL

------------------------------------------------------------------------

### Method `last_errors()`

Get errors from recent hook executions.

Useful for programmatic checking of hook health, especially for
audit/logging hooks where failures are logged but not fatal.

#### Usage

    HookRegistry$last_errors()

#### Returns

List of error records, each containing event, tool_name, error,
timestamp

------------------------------------------------------------------------

### Method `clear_errors()`

Clear the error history.

#### Usage

    HookRegistry$clear_errors()

------------------------------------------------------------------------

### Method `count()`

Get the number of registered hooks.

#### Usage

    HookRegistry$count()

#### Returns

Integer count

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print the registry.

#### Usage

    HookRegistry$print()

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    HookRegistry$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
