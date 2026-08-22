# HookMatcher rejects callbacks that cannot accept an event

    Code
      HookMatcher$new(event = "PreToolUse", callback = function(tool_name) NULL)
    Condition
      Error in `validate_hook_callback()`:
      ! Invalid callback for "PreToolUse" hook.
      i Expected signature: function(tool_name, tool_input, context) or a callback accepting `...`.

---

    Code
      HookMatcher$new(event = "SessionStart", callback = function(context, required)
        NULL)
    Condition
      Error in `validate_hook_callback()`:
      ! Invalid callback for "SessionStart" hook.
      i Expected signature: function(context) or a callback accepting `...`.

# HookMatcher rejects invalid regex patterns at construction

    Code
      HookMatcher$new(event = "PreToolUse", pattern = "[", callback = function(...)
        NULL)
    Condition
      Error in `validate_hook_pattern()`:
      ! Invalid hook pattern: "["

---

    Code
      HookMatcher$new(event = "PreToolUse", pattern = c("read", "write"), callback = function(
        ...) NULL)
    Condition
      Error in `validate_hook_pattern()`:
      ! `pattern` must be NULL or one non-missing string
