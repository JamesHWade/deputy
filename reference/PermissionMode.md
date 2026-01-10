# Permission modes for agent tool access

Permission modes control the overall behavior of tool permission
checking:

- `"default"` - Check each tool against the permission policy

- `"acceptEdits"` - Auto-accept file write tools

- `"readonly"` - Deny all write/execute tools

- `"bypassPermissions"` - Allow all tools (dangerous, use with caution)

## Usage

``` r
PermissionMode
```

## Format

An object of class `character` of length 4.

## Tool Annotations

Permissions use tool annotations (from
[`ellmer::tool_annotations()`](https://ellmer.tidyverse.org/reference/tool_annotations.html))
to determine tool behavior. Available annotations:

**read_only_hint** (logical, default: FALSE)

Indicates the tool only reads data and doesn't modify state. Tools with
`read_only_hint = TRUE` are allowed in `"readonly"` mode. Examples:
`tool_read_file`, `tool_list_files`, `tool_search`

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
