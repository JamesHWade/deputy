# Create a hook that limits file writes to a directory

Creates a PreToolUse hook that denies `write_file`, `edit_file` and
`multi_edit` calls outside `allowed_dir`, using the same path checks as
`Permissions(file_write = allowed_dir)`. Setting `file_write` in the
agent's
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
is the main way to limit writes; this hook adds a second check.

The hook returns a denial for a write outside `allowed_dir` and `NULL`
otherwise, so hooks added after it still see the writes it lets through.

## Usage

``` r
hook_limit_file_writes(allowed_dir)
```

## Arguments

- allowed_dir:

  An existing directory where writes are allowed. It is resolved to an
  absolute path when the hook is created.

## Value

A
[HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md).

## See also

[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)

## Examples

``` r
if (FALSE) { # \dontrun{
dir.create("output", showWarnings = FALSE)
agent$add_hook(hook_limit_file_writes("output"))
} # }
```
