# Permissions and Safety

Permissions control what an agent is allowed to do. They sit between the
LLM and tool execution, checking every tool call before it runs. deputy
ships with sensible presets and makes it easy to build custom policies.

## Permission Presets

``` r

library(deputy)

# Read-only: known Deputy read tools are allowed
permissions_readonly()

# Plan: annotated read-only tools plus ask_user
permissions_plan()

# Standard (default): accessible reads, workspace-scoped writes, R code,
# no bash/web
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
  install_packages = FALSE
)
```

Fields:

| Field | Type | Description |
|----|----|----|
| `file_read` | logical | Allow reading files |
| `file_write` | logical / path | Allow writing (optionally restricted to a directory) |
| `bash` | logical | Allow bash commands |
| `r_code` | logical | Allow R code execution |
| `web` | logical | Allow web access |
| `install_packages` | logical | Allow package installation |
| `can_use_tool` | function | Apply custom permission decisions |
| `tool_allowlist` | character | Deny tools not explicitly listed |
| `tool_denylist` | character | Always deny explicitly listed tools |
| `permission_prompt_tool_name` | character | Dedicated approval tool used in gating messages |

## Permission Modes

The `mode` field provides broad policy shortcuts:

| Mode | Behaviour |
|----|----|
| `"standard"` | Check each tool against the configured capabilities |
| `"readonly"` | Allow known Deputy read tools and explicit allowlist entries within configured capabilities |
| `"plan"` | Allow read-only annotated tools within configured capabilities and the human approval prompt tool |
| `"full"` | Allow every tool (dangerous!) |

``` r

perms <- Permissions$new(mode = "readonly")
```

[`permissions_plan()`](https://jameshwade.github.io/deputy/reference/permissions_plan.md)
creates a planning-oriented policy:

``` r

agent <- Agent$new(
  chat = ellmer::chat_anthropic(),
  tools = tools_all(),
  permissions = permissions_plan()
)
```

## Changing an Agent’s Mode

An agent’s configured permissions are an authority ceiling. Calling
`set_permission_mode()` may preserve or narrow that authority, but it
cannot widen it or replace it with an incomparable policy:

| Current mode | Allowed target modes                           |
|--------------|------------------------------------------------|
| `"readonly"` | `"readonly"`                                   |
| `"standard"` | `"standard"`, `"readonly"`                     |
| `"plan"`     | `"plan"`, `"readonly"`                         |
| `"full"`     | `"full"`, `"standard"`, `"plan"`, `"readonly"` |

Reapplying the current mode is an exact no-op. For an allowed narrowing,
Deputy intersects the target mode with the existing capabilities. Custom
restrictions, tool gates, callbacks, and directory-scoped write roots
therefore remain authoritative.

``` r

agent$set_permission_mode("readonly")
```

Create a newly configured `Agent` when broader or incomparable authority
is required.

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

Annotations describe behavior; they do not independently grant
authority. In `"readonly"` mode, Deputy recognizes its built-in read
tools and explicit allowlist entries, while still denying known writes,
destructive tools, and open-world tools when web access is disabled.
Unknown tools do not become authorized merely by declaring
`read_only_hint = TRUE`. In `"standard"` mode, annotations participate
in the configured capability checks.

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

## Run Limits

Permissions decide whether a tool may run. Configure resource limits
separately with
[`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
on the agent or an individual run:

``` r

agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_file(),
  permissions = permissions_standard(),
  usage_limits = UsageLimits(
    max_requests = 10,
    max_tool_calls = 20,
    max_cost_usd = 1
  )
)
```

When a limit is reached, the agent stops and the
`AgentResult$stop_reason` identifies the limit, such as
`"request_limit"`, `"tool_call_limit"`, or `"cost_limit"`.
