# Create a permission policy

A `Permissions` object decides which tool calls an agent may make. Pass
it to `Agent$new()`, or test a call with
[`permissions_check()`](https://jameshwade.github.io/deputy/reference/permissions_check.md).
[PermissionMode](https://jameshwade.github.io/deputy/reference/PermissionMode.md)
describes how each mode uses these settings.

The object is read-only; read its fields with `$`. To restrict an agent
further while it runs, call `agent$set_permission_mode()`. Permissions
can be narrowed but not widened.

A policy is not an OS sandbox: code run through `run_r_code` or
`run_bash` can do anything your R session can.

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

  Allow file reading. `TRUE` or `FALSE`. Reads aren't limited to a
  directory: with `TRUE`, the file tools can read any file the R process
  can, including credential files such as `~/.Renviron`. Use
  `can_use_tool` to refuse particular paths.

- file_write:

  `TRUE`, `FALSE`, or an existing absolute directory. A directory allows
  writes only inside it and is resolved when the policy is created. The
  path is checked when the model asks to write and again just before
  writing, so a symbolic link swapped in between is refused. The second
  check narrows the window for such a swap but can't remove it. Defaults
  to the current working directory.

- bash:

  Allow shell commands. `TRUE` or `FALSE`.

- r_code:

  Allow R code execution. `TRUE` or `FALSE`.

- web:

  Allow web access, including other tools that reach external systems.
  `TRUE` or `FALSE`.

- install_packages:

  Allow package installation. `TRUE` or `FALSE`.

- can_use_tool:

  Optional function `(tool_name, tool_input, context)` that returns
  [`PermissionResultAllow()`](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md),
  [`PermissionResultDeny()`](https://jameshwade.github.io/deputy/reference/PermissionResultDeny.md)
  or
  [`PermissionResultPending()`](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md).
  It is called, in every mode, for each call the rest of the policy
  allows, so it can deny a call or pause it for approval but can't allow
  a call the policy denies. Any other return value, including `NULL`,
  denies the call with a warning, and so does an error.

- tool_allowlist:

  Character vector of allowed tool names, or `NULL` (the default) to
  allow any name. An empty vector denies all tools.

- tool_denylist:

  Character vector of denied tool names, or `NULL`.

- permission_prompt_tool_name:

  Optional name of a tool the model can call to ask for approval, such
  as `"ask_user"`. It is allowed in every mode unless `tool_allowlist`
  or `tool_denylist` excludes it, and denials from those lists point the
  model to it. Built-in file, code, web, install and delegation tools
  can't be used.

## Value

A `Permissions` object.

## See also

[`vignette("permissions")`](https://jameshwade.github.io/deputy/articles/permissions.md)

## Examples

``` r
policy <- Permissions(file_write = FALSE)
permissions_check(policy, "write_file", list(path = "output.txt"))
#> <deputy::PermissionResultDeny>
#>  @ decision : chr "deny"
#>  @ reason   : chr "File writing is not allowed"
#>  @ interrupt: logi FALSE
policy$file_write
#> [1] FALSE
```
