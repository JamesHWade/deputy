# Create a hook

`HookMatcher()` pairs a callback with a [hook
event](https://jameshwade.github.io/deputy/reference/HookEvent.md) and,
optionally, a tool-name pattern. Add it to an agent with
`agent$add_hook()`. The object is read-only; read its fields with `@` or
[`S7::prop()`](https://rconsortium.github.io/S7/reference/prop.html).

## Usage

``` r
HookMatcher(event, callback, pattern = NULL, timeout = 0, promise_timeout = 60)
```

## Arguments

- event:

  One of
  [HookEvent](https://jameshwade.github.io/deputy/reference/HookEvent.md).

- callback:

  A function taking the arguments listed for `event` in
  [HookEvent](https://jameshwade.github.io/deputy/reference/HookEvent.md),
  or `...`. `HookMatcher()` errors if the arguments don't fit.

- pattern:

  Optional regular expression matched against the tool name. A hook with
  a pattern only fires for events that have a tool name.

- timeout:

  Time limit for the callback, in seconds. The default, 0, runs the
  callback in your R session with no limit. A positive value runs it in
  a fresh R process with
  [`callr::r()`](https://callr.r-lib.org/reference/r.html). That process
  can't see your global variables or attached packages (call functions
  as `pkg::fn()`), and its printed output and other side effects stay
  there. Such a callback can't return a promise.

- promise_timeout:

  Time limit, in seconds, for a promise the callback returns. The
  default is 60. A promise that has not settled by then counts as no
  answer and is recorded as a hook error. For PreToolUse that denies the
  call.

## Value

A `HookMatcher` object.

## See also

[`hook_matches()`](https://jameshwade.github.io/deputy/reference/hook_matches.md)

## Examples

``` r
hook <- HookMatcher(
  "PreToolUse",
  callback = function(tool_name, tool_input, context) {
    HookResultPreToolUse(permission = "deny", reason = "Read only")
  },
  pattern = "^write_"
)
hook_matches(hook, "write_file")
#> [1] TRUE
S7::prop(hook, "event")
#> [1] "PreToolUse"
```
