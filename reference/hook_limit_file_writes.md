# Create a hook that limits file writes to a directory

Convenience function to create a PreToolUse hook that only allows file
writes within a specified directory.

## Usage

``` r
hook_limit_file_writes(allowed_dir)
```

## Arguments

- allowed_dir:

  Directory where writes are allowed

## Value

A
[HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
object

## Examples

``` r
if (FALSE) { # \dontrun{
agent$add_hook(hook_limit_file_writes("./output"))
} # }
```
