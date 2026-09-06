# Match a lifecycle hook

An S7 value defining when a callback runs. Configuration is read-only
after construction; callback closures retain their caller-owned
environments.

## Usage

``` r
HookMatcher(event, callback, pattern = NULL, timeout = 0)
```

## Arguments

- event:

  One of
  [HookEvent](https://jameshwade.github.io/deputy/reference/HookEvent.md).

- callback:

  Function accepting the arguments documented for the event in
  [HookEvent](https://jameshwade.github.io/deputy/reference/HookEvent.md),
  or `...`.

- pattern:

  Optional regular expression filtering tool names.

- timeout:

  Maximum callback time in seconds. Zero runs in the caller's process.
  Positive values use a clean
  [`callr::r()`](https://callr.r-lib.org/reference/r.html) subprocess,
  where caller-process state and side effects are not available.

## Value

A `HookMatcher` S7 object.

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
