# Create a permission policy

A read-only S7 value controlling tool access. Use
[`permissions_check()`](https://jameshwade.github.io/deputy/reference/permissions_check.md)
to evaluate a call. Read properties with `S7::prop(policy, "mode")` or
`$`. To narrow an active Agent, use its `set_permission_mode()` method;
replacing its policy or changing its properties is not supported.

Directory grants are canonicalized at construction. The callback retains
its caller-owned executable state. Read-only properties protect the
public configuration; they are not an execution sandbox. Serialized
policies are configuration records, not portable authority grants or a
way to widen an existing Agent's authority.

## Usage

``` r
Permissions(
  mode = "standard",
  file_read = TRUE,
  file_write = getwd(),
  bash = FALSE,
  r_code = FALSE,
  web = FALSE,
  install_packages = FALSE,
  can_use_tool = NULL,
  tool_allowlist = NULL,
  tool_denylist = NULL,
  permission_prompt_tool_name = NULL
)
```

## Arguments

- mode:

  One of `"standard"`, `"plan"`, `"readonly"`, or `"full"`.

- file_read:

  Allow file reading. One non-missing logical value.

- file_write:

  `TRUE`, `FALSE`, or an existing absolute directory path.

- bash:

  Allow shell commands. One non-missing logical value.

- r_code:

  Allow R code execution. One non-missing logical value; defaults to
  `FALSE`.

- web:

  Allow web requests. One non-missing logical value.

- install_packages:

  Allow package installation. One non-missing logical value.

- can_use_tool:

  A function accepting tool name, input, and context, returning a
  [PermissionResultAllow](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md),
  [PermissionResultDeny](https://jameshwade.github.io/deputy/reference/PermissionResultDeny.md),
  [PermissionResultPending](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md),
  or `NULL`.

- tool_allowlist:

  Character vector of allowed tool names, or `NULL`. An empty vector
  denies all tools; `NULL` disables this gate.

- tool_denylist:

  Character vector of denied tool names, or `NULL`.

- permission_prompt_tool_name:

  Optional dedicated approval-tool name to suggest in deny messages.
  Native capability-bearing tools cannot be used.

## Value

A read-only `Permissions` S7 object.

## Examples

``` r
policy <- Permissions(file_write = FALSE)
permissions_check(policy, "write_file", list(path = "output.txt"))
#> <deputy::PermissionResultDeny>
#>  @ decision : chr "deny"
#>  @ reason   : chr "File writing is not allowed"
#>  @ interrupt: logi FALSE
S7::prop(policy, "file_write")
#> [1] FALSE
```
