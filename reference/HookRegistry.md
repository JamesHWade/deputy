# Hook registry

Holds an agent's hooks, finds the ones that match an event, and runs
them. Each agent has its own registry in `agent$hooks`; add hooks with
`agent$add_hook()`.

## Methods

### Public methods

- [`HookRegistry$new()`](#method-HookRegistry-initialize)

- [`HookRegistry$add()`](#method-HookRegistry-add)

- [`HookRegistry$get_hooks()`](#method-HookRegistry-get_hooks)

- [`HookRegistry$fire()`](#method-HookRegistry-fire)

- [`HookRegistry$reserve_fire_id()`](#method-HookRegistry-reserve_fire_id)

- [`HookRegistry$last_errors()`](#method-HookRegistry-last_errors)

- [`HookRegistry$errors_from()`](#method-HookRegistry-errors_from)

- [`HookRegistry$clear_errors()`](#method-HookRegistry-clear_errors)

- [`HookRegistry$count()`](#method-HookRegistry-count)

- [`HookRegistry$print()`](#method-HookRegistry-print)

- [`HookRegistry$clone()`](#method-HookRegistry-clone)

------------------------------------------------------------------------

### `HookRegistry$new()`

Create an empty registry.

#### Usage

    HookRegistry$new()

------------------------------------------------------------------------

### `HookRegistry$add()`

Add a hook to the registry.

#### Usage

    HookRegistry$add(hook)

#### Arguments

- `hook`:

  A
  [HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md).

#### Returns

The registry, invisibly.

------------------------------------------------------------------------

### `HookRegistry$get_hooks()`

Get the hooks that match an event.

#### Usage

    HookRegistry$get_hooks(event, tool_name = NULL)

#### Arguments

- `event`:

  A
  [HookEvent](https://jameshwade.github.io/deputy/reference/HookEvent.md).

- `tool_name`:

  Optional tool name to match against hook patterns.

#### Returns

A list of
[HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
objects.

------------------------------------------------------------------------

### `HookRegistry$fire()`

Run the matching hooks in the order they were added and return the first
non-`NULL` result. Later hooks don't run. When a callback returns a
promise, later hooks wait for it, and the promise `fire()` returns
resolves to that result.

A failing callback is recorded in `last_errors()`. For PreToolUse the
failure denies the tool call; for other events it is reported and the
next hook runs.

#### Usage

    HookRegistry$fire(event, tool_name = NULL, ...)

#### Arguments

- `event`:

  A
  [HookEvent](https://jameshwade.github.io/deputy/reference/HookEvent.md).

- `tool_name`:

  Optional tool name, matched against hook patterns and passed to the
  callback.

- `...`:

  Other arguments for the callback.

#### Returns

The first non-`NULL` result, or `NULL`. A promise of it when a callback
returned a promise.

------------------------------------------------------------------------

### `HookRegistry$reserve_fire_id()`

Reserve the ID of the next `fire()` call, so that its errors can be
found afterwards with `errors_from()`. Call it immediately before
`fire()`.

#### Usage

    HookRegistry$reserve_fire_id()

#### Returns

The ID, an integer.

------------------------------------------------------------------------

### `HookRegistry$last_errors()`

Get the errors hook callbacks have raised since the registry was created
or last cleared. Use it to check logging hooks, whose failures don't
stop the run.

#### Usage

    HookRegistry$last_errors()

#### Returns

A list of records with `event`, `tool_name`, `error`, `timestamp` and
`fire_id`, the ID of the `fire()` call that raised the error.

------------------------------------------------------------------------

### `HookRegistry$errors_from()`

Get the errors raised by one `fire()` call, including those of promises
that settled later.

#### Usage

    HookRegistry$errors_from(fire_id)

#### Arguments

- `fire_id`:

  An ID from `reserve_fire_id()`.

#### Returns

A list of records, as `last_errors()` returns.

------------------------------------------------------------------------

### `HookRegistry$clear_errors()`

Clear the recorded errors.

#### Usage

    HookRegistry$clear_errors()

------------------------------------------------------------------------

### `HookRegistry$count()`

Get the number of registered hooks.

#### Usage

    HookRegistry$count()

#### Returns

An integer.

------------------------------------------------------------------------

### `HookRegistry$print()`

Print the registry.

#### Usage

    HookRegistry$print()

------------------------------------------------------------------------

### `HookRegistry$clone()`

The objects of this class are cloneable with this method.

#### Usage

    HookRegistry$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
