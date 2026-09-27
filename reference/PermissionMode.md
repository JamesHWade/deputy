# Permission modes

`PermissionMode` lists the modes a
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
policy can use. In every mode, `tool_denylist` and `tool_allowlist` are
checked first, and the approval prompt tool
(`permission_prompt_tool_name`) is then allowed without further checks.

- `"standard"`: checks built-in tools against the capability flags
  (`file_read`, `file_write`, `bash`, `r_code`, `web`,
  `install_packages`) and custom tools against their annotations.

- `"readonly"`: allows the built-in file-reading tools, the web tools
  when `web = TRUE`, the agent's own delegation tools and tools on
  `tool_allowlist`. It denies writes, code execution, destructive tools
  and, unless `web = TRUE`, open-world tools.

- `"plan"`: allows only tools annotated as read-only, plus the approval
  prompt tool and the agent's own delegation tools. Open-world tools
  also need `web = TRUE`.

- `"full"`: allows every call. Capability flags and annotations are not
  checked.

An agent's own delegation tools are a
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)'s
`delegate_to_agent` tool and the tools that call its retained agents,
from
[`delegation_tool()`](https://jameshwade.github.io/deputy/reference/delegation_tool.md)
and `$retain_agent_graph()`. Another tool doesn't qualify by using the
same name. Each tool call a subagent or retained agent makes is also
checked against the policy of the agent that delegated to it, so in
read-only or plan mode that agent's delegates are held to the same mode.
A
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)'s
subagents also can't use a less strict mode than their lead.

If the policy has a `can_use_tool` callback, it is called in every mode
for each call the rest of the policy allows. It can deny the call or
pause it for approval, but it can't allow a call the policy denies.

A denied call can still be allowed by a PermissionRequest hook (see
[HookEvent](https://jameshwade.github.io/deputy/reference/HookEvent.md)).

## Usage

``` r
PermissionMode
```

## Tool annotations

Custom tools are checked through their annotations, set with
[`ellmer::tool_annotations()`](https://ellmer.tidyverse.org/reference/tool_annotations.html).
A missing annotation takes a cautious default:

- `read_only_hint` (default `FALSE`): the tool only reads data. Plan
  mode allows only these tools.

- `destructive_hint` (default `TRUE`, or `FALSE` when
  `read_only_hint = TRUE`): the tool may make irreversible changes.
  Destructive tools are denied in plan and readonly modes, and in
  standard mode when both `file_write` and `bash` are off.

- `open_world_hint` (default `TRUE`): the tool may reach external
  systems. Open-world tools are denied unless `web = TRUE`, except in
  full mode.

- `idempotent_hint` (default `FALSE`): repeated calls have the same
  effect. Permission checks don't use it.

So in standard mode an unannotated custom tool needs `web = TRUE`, and
plan and readonly modes deny it. Built-in tools such as `write_file` and
`run_bash` are checked against their capability flag instead.

## Annotating tools

Set annotations when you create a tool:

    # Read-only tool
    tool_search <- ellmer::tool(
      fun = function(pattern) grep(pattern, files),
      name = "search",
      description = "Search for pattern",
      arguments = list(pattern = ellmer::type_string("Search pattern")),
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        destructive_hint = FALSE,
        open_world_hint = FALSE
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
        destructive_hint = TRUE,
        open_world_hint = FALSE
      )
    )

## See also

[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md),
[`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md),
[`permissions_plan()`](https://jameshwade.github.io/deputy/reference/permissions_plan.md),
[`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md),
and
[`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md).
