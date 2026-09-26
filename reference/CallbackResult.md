# Hook and permission results

`HookResult` and `PermissionResult` are the parent classes of the values
that hook and permission callbacks return. You don't create them
directly; use
[`HookResultPreToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPreToolUse.md),
[`HookResultPostToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPostToolUse.md),
[`HookResultPreCompact()`](https://jameshwade.github.io/deputy/reference/HookResultPreCompact.md),
[`PermissionResultAllow()`](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md),
[`PermissionResultDeny()`](https://jameshwade.github.io/deputy/reference/PermissionResultDeny.md)
or
[`PermissionResultPending()`](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md).
To test which kind a value is, use
`S7::S7_inherits(x, PermissionResult)`.

Results are read-only. Read fields with `$` (a missing field gives
`NULL`), `@` or
[`S7::prop()`](https://rconsortium.github.io/S7/reference/prop.html), or
get them all as a list with
[`S7::props()`](https://rconsortium.github.io/S7/reference/props.html).
To change a decision, create a new result.

## Usage

``` r
HookResult()

PermissionResult()
```
