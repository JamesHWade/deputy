# Permissions and Safety

Permissions control what an agent is allowed to do. They sit between the
LLM and tool execution, checking every tool call before it runs. deputy
ships with sensible presets and makes it easy to build custom policies.

## Permission Presets

``` r
library(deputy)

# Read-only: only read_file and list_files are allowed
permissions_readonly()

# Standard (default): file read/write in working dir, R code, no bash/web
permissions_standard()

# Full: everything allowed (use with caution!)
permissions_full()
```

Each preset returns a `Permissions` object. Pass it to `Agent$new()`:

``` r
agent <- Agent$new(
  chat = ellmer::chat_anthropic(),
  tools = tools_all(),
  permissions = permissions_readonly()
)
```

## Custom Permissions

For fine-grained control, create a `Permissions` object directly:

``` r
perms <- Permissions$new(
  file_read = TRUE,
  file_write = "/path/to/allowed/dir",
  bash = FALSE,
  r_code = TRUE,
  web = FALSE,
  install_packages = FALSE,
  max_turns = 10,
  max_cost_usd = 0.50
)
```

Fields:

| Field              | Type           | Description                                          |
|--------------------|----------------|------------------------------------------------------|
| `file_read`        | logical        | Allow reading files                                  |
| `file_write`       | logical / path | Allow writing (optionally restricted to a directory) |
| `bash`             | logical        | Allow bash commands                                  |
| `r_code`           | logical        | Allow R code execution                               |
| `web`              | logical        | Allow web access                                     |
| `install_packages` | logical        | Allow package installation                           |
| `max_turns`        | integer        | Maximum agentic turns (default 25)                   |
| `max_cost_usd`     | numeric / NULL | Maximum spend in USD                                 |

## Permission Modes

The `mode` field provides broad policy shortcuts:

| Mode                  | Behaviour                                             |
|-----------------------|-------------------------------------------------------|
| `"default"`           | Check each tool against the policy fields above       |
| `"readonly"`          | Only allow tools annotated as `read_only_hint = TRUE` |
| `"acceptEdits"`       | Auto-approve file writes without prompting            |
| `"bypassPermissions"` | Allow everything (dangerous!)                         |

``` r
perms <- Permissions$new(mode = "readonly")
```

## Tool Annotations

Tools carry annotations that describe their behaviour. The permission
system uses these annotations to make decisions:

``` r
# A read-only tool
tool_safe <- ellmer::tool(
  fun = function(x) x,
  name = "safe_tool",
  description = "A safe, read-only tool",
  arguments = list(x = ellmer::type_string("Input")),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE
  )
)
```

In `"readonly"` mode, only tools with `read_only_hint = TRUE` are
allowed. In `"default"` mode, tools with `destructive_hint = TRUE` may
be blocked depending on the policy.

## Custom Permission Callbacks

For complex logic, provide a `can_use_tool` callback:

``` r
perms <- Permissions$new(
  can_use_tool = function(tool_name, tool_input, context) {
    # Block writes to sensitive files
    if (tool_name == "write_file") {
      if (grepl("^\\.env|secrets|credentials", tool_input$path)) {
        return(PermissionResultDeny(
          reason = "Cannot write to sensitive files"
        ))
      }
    }
    PermissionResultAllow()
  }
)
```

The callback receives:

- `tool_name` – Name of the tool being called
- `tool_input` – Named list of arguments
- `context` – List with `working_dir` and `tool_annotations`

It must return
[`PermissionResultAllow()`](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md)
or `PermissionResultDeny(reason)`.

## Example: Read-Only Agent

A read-only agent can explore files but cannot change anything:

``` r
library(deputy)

chat <- ellmer::chat_anthropic(model = "claude-sonnet-4-20250514")
agent <- Agent$new(
  chat = chat,
  tools = tools_file(),
  permissions = permissions_readonly()
)

result <- agent$run_sync("What files are in the current directory?")
cat(result$response)
```

## Cost and Turn Limits

Permissions also enforce resource limits:

``` r
perms <- Permissions$new(
  max_turns = 10,      # Stop after 10 agentic turns
  max_cost_usd = 1.00  # Stop if cost exceeds $1.00
)
```

When a limit is reached, the agent stops and the
`AgentResult$stop_reason` indicates what happened (`"max_turns"` or
`"cost_limit"`).
