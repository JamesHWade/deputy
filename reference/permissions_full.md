# Create a full access permission policy

Creates a `"full"` policy, which allows every tool call: writes anywhere
your R session can write, R and shell code, web access and package
installation. Capability flags and tool annotations are not checked,
though PreToolUse hooks still run and can deny a call. Use it only with
a model and task you trust, ideally inside a container or other OS
sandbox.

## Usage

``` r
permissions_full()
```

## Value

A
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
object.

## Examples

``` r
perms <- permissions_full()
```
