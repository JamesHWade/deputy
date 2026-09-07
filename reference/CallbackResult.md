# Callback result value families

Abstract S7 bases for hook and permission results. Construct a concrete
result with
[`HookResultPreToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPreToolUse.md),
[`HookResultPostToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPostToolUse.md),
[`HookResultPreCompact()`](https://jameshwade.github.io/deputy/reference/HookResultPreCompact.md),
[`PermissionResultAllow()`](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md),
or
[`PermissionResultDeny()`](https://jameshwade.github.io/deputy/reference/PermissionResultDeny.md).
Test family membership with
[`S7::S7_inherits()`](https://rconsortium.github.io/S7/reference/S7_inherits.html).

Result properties are read-only after construction. Read with `@`,
[`S7::prop()`](https://rconsortium.github.io/S7/reference/prop.html), or
`$`; missing `$` fields return NULL. Use
[`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
for a plain list of properties and construct a new result to change a
decision. S3 class tags and whole-result list indexing are not
supported. Objects stored in `updated_tool_output` retain their own
reference semantics; freezing a result does not freeze an environment
inside it.

## Usage

``` r
HookResult()

PermissionResult()
```
