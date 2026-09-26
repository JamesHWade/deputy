# Test whether a hook matches a tool name

Test whether a hook matches a tool name

## Usage

``` r
hook_matches(hook, tool_name = NULL)
```

## Arguments

- hook:

  A
  [HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md).

- tool_name:

  One tool name, or `NULL`. A hook without a pattern matches every name,
  including `NULL`; a hook with a pattern never matches `NULL`.

## Value

`TRUE` or `FALSE`.
