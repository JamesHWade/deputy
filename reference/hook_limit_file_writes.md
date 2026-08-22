# Create a hook that limits file writes to a directory

Convenience function to create a PreToolUse hook that applies Deputy's
canonical file-write permission policy to `write_file`, `edit_file`, and
`multi_edit`. Prefer configuring
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
as the Agent's authority policy; this helper is useful as an additional
hook-level restriction.

## Usage

``` r
hook_limit_file_writes(allowed_dir)
```

## Arguments

- allowed_dir:

  Existing directory where writes are allowed. The path is canonicalized
  when the hook is created.

## Value

A
[HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
object

## See also

[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)

## Examples

``` r
if (FALSE) { # \dontrun{
dir.create("output", showWarnings = FALSE)
agent$add_hook(hook_limit_file_writes("output"))
} # }
```
