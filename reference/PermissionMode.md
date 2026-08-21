# Permission modes for agent tool access

Permission modes control the overall behavior of tool permission
checking:

- `"standard"` - Check each tool against the configured capabilities

- `"plan"` - Allow annotated read-only tools within configured
  capabilities plus human approval prompts

- `"readonly"` - Deny all write/execute tools

- `"full"` - Allow all tools (dangerous, use with caution)

## Usage

``` r
PermissionMode
```

## Tool Annotations

Permissions use tool annotations (from
[`ellmer::tool_annotations()`](https://ellmer.tidyverse.org/reference/tool_annotations.html))
to determine tool behavior. Available annotations:

**read_only_hint** (logical, default: FALSE)

Indicates the tool only reads data and doesn't modify state. Annotations
are descriptive metadata, not an authority grant: `"readonly"` mode
allows known Deputy read tools or explicit allowlist entries, subject to
destructive and open-world capability checks. Examples:
`tool_read_file`, `tool_list_files`, `tool_search`.

**destructive_hint** (logical, default: TRUE)

Indicates the tool may cause destructive/irreversible changes. Tools
with `destructive_hint = TRUE` require explicit permission. Examples:
`tool_write_file`, `tool_delete_file`, `tool_run_bash`

**open_world_hint** (logical, default: FALSE)

Indicates the tool may interact with external systems. Used for network
calls, package installation, etc. Examples: `tool_web_search`,
`tool_install_package`

**idempotent_hint** (logical, default: FALSE)

Indicates repeated calls produce the same result. Safe to retry on
failure.

## Creating Tools with Annotations

    # Read-only tool
    tool_search <- ellmer::tool(
      fun = function(pattern) grep(pattern, files),
      name = "search",
      description = "Search for pattern",
      arguments = list(pattern = ellmer::type_string("Search pattern")),
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        destructive_hint = FALSE
      )
    )

    # Destructive tool
    tool_delete <- ellmer::tool(
      fun = function(path) unlink(path),
      name = "delete",
      description = "Delete a file",
      arguments = list(path = ellmer::type_string("File path")),
      annotations = ellmer::tool_annotations(
        read_only_hint = FALSE,
        destructive_hint = TRUE
      )
    )

## See also

[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md),
[`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md),
[`permissions_plan()`](https://jameshwade.github.io/deputy/reference/permissions_plan.md),
[`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md),
and
[`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md).
