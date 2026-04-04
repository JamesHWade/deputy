# Agent SDK Compatibility

deputy keeps a provider-agnostic R runtime at its core and layers an
opt-in Agent SDK-compatible facade on top. This vignette shows what is
covered by the compatibility layer, how the Anthropic-style entrypoints
map to deputy, and where the current boundary remains intentionally
narrower than Anthropic’s full ecosystem surface.

## Compatibility Matrix

| Surface                                                                                                                                                                                          | Status           | deputy mapping                                                                                                                                                                                                    |
|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`agent_sdk_query()`](https://jameshwade.github.io/deputy/reference/claude_sdk_query.md) / [`claude_sdk_query()`](https://jameshwade.github.io/deputy/reference/claude_sdk_query.md) / `query()` | Covered          | [`agent_sdk_query()`](https://jameshwade.github.io/deputy/reference/claude_sdk_query.md), [`claude_sdk_query()`](https://jameshwade.github.io/deputy/reference/claude_sdk_query.md), and `AgentSDKClient$query()` |
| Session ids, resume, fork                                                                                                                                                                        | Covered          | Persisted snapshots plus `resume()` / CLI flags                                                                                                                                                                   |
| Permission modes                                                                                                                                                                                 | Covered          | `default`, `acceptEdits`, `readonly`, `plan`, `bypassPermissions`                                                                                                                                                 |
| Hook events                                                                                                                                                                                      | Covered          | Existing hook system plus `Notification`                                                                                                                                                                          |
| Claude settings                                                                                                                                                                                  | Covered          | `CLAUDE.md`, `.claude/skills`, `.claude/commands`, `.claude/agents`, tool policy keys                                                                                                                             |
| Anthropic-style built-in tool names                                                                                                                                                              | Covered          | `Read`, `Write`, `Edit`, `MultiEdit`, `Glob`, `Grep`, `LS`, `TodoRead`, `TodoWrite`, `WebFetch`, `WebSearch`, `Agent`, `Task`                                                                                     |
| Native deputy runtime                                                                                                                                                                            | Canonical        | `Agent`, `LeadAgent`, `Permissions`, `HookMatcher`                                                                                                                                                                |
| Plugin discovery / marketplace execution                                                                                                                                                         | Not in this wave | Track separately from the core compat facade                                                                                                                                                                      |
| MCP resource subscriptions                                                                                                                                                                       | Not in this wave | deputy exposes MCP tools, not Anthropic-specific resource flows                                                                                                                                                   |

## Entry Points

Use
[`agent_sdk_options()`](https://jameshwade.github.io/deputy/reference/claude_sdk_options.md)
to express Anthropic-shaped options and translate them into deputy
internals. The Claude-named aliases remain fully supported.

``` r
library(deputy)

options <- agent_sdk_options(
  chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  setting_sources = c("user", "project", "local"),
  permission_mode = "plan",
  allowed_tools = c("Read", "Grep", "LS"),
  max_turns = 15
)

result <- agent_sdk_query("Summarize the package structure", options = options)
result$session_id
```

For a stateful client:

``` r
client <- AgentSDKClient$new(options)
client$query("Inspect the R/ directory")
```

## Sessions, Resume, and Fork

The compatibility layer persists snapshots to:

``` r
tools::R_user_dir("deputy", "cache")
```

Snapshots are enabled by default for the compatibility APIs. Each
completed turn writes a new snapshot, and the latest snapshot path is
attached to `AgentResult$snapshot_path`.

``` r
result <- client$query("Create a high-level summary")

# Restore the latest snapshot for a session id
client$resume(result$session_id)

# Restore the newest snapshot at or before a point in time
client$resume(result$session_id, at = "2026-03-07 10:30:00")

# Clone the restored state into a new session id
client$resume(result$session_id, fork = TRUE)
```

The CLI exposes the same behavior:

``` bash
deputy --permission-mode plan --persist-session
deputy --resume-session-id abc123
deputy --resume-session-id abc123 --resume-session-at "2026-03-07 10:30:00"
deputy --resume-session-id abc123 --fork-session
```

## Permissions and Hooks

Anthropic’s planning behavior maps to deputy’s `plan` mode:

``` r
permissions_plan()
```

`plan` allows only tools annotated with `read_only_hint = TRUE` plus the
approval tool named by `permission_prompt_tool_name` (default:
`"AskUserQuestion"`). Write, execution, and unannotated tools are denied
by default.

Informational runtime events now use the existing hook system via
`Notification`:

``` r
hook <- HookMatcher$new(
  event = "Notification",
  callback = function(message, context) {
    cli::cli_alert_info("[{context$code}] {message}")
    NULL
  }
)
```

deputy emits `Notification` for cases such as session restore or fork
notices, permission-denied guidance, compaction fallbacks, and cost
warnings.

## Settings, Agents, and Tool Aliases

[`claude_settings_load()`](https://jameshwade.github.io/deputy/reference/claude_settings_load.md)
and
[`claude_settings_apply()`](https://jameshwade.github.io/deputy/reference/claude_settings_apply.md)
now understand:

- `CLAUDE.md` memory blocks
- `.claude/skills`
- `.claude/commands`
- `.claude/agents`
- Tool policy keys such as `allowedTools`, `disallowedTools`, and
  `permissionPromptToolName`

`setting_sources` precedence is fixed as `user`, then `project`, then
`local`. The `local` source only loads `.claude/settings.local.json`, so
it can override settings keys without pulling in extra memory, commands,
skills, or agents.

Custom agents from `.claude/agents` are converted to `AgentDefinition`
objects and registered automatically when you use `LeadAgent` or
`AgentSDKClient`. Unsupported frontmatter fields are warned on and
ignored so compatibility stays resilient when files include metadata
deputy does not map.

Anthropic-style tool names resolve through the compatibility layer
rather than changing deputy’s native tool names:

``` r
compat_tools <- agent_sdk_options(
  custom_tools = list(),
  allowed_tools = c("Read", "Edit", "TodoWrite", "Agent")
)
```

This keeps `read_file`, `edit_file`, `todo_write`, and the rest of
deputy’s snake_case tool surface intact for native R users.

## Design Boundary

deputy aims for behavioral compatibility, not a literal language-port of
the Node or Python SDKs. The runtime model is intentionally R-native:

- R6 objects instead of Python or TypeScript classes
- `coro` generators for streaming
- Base lists and data frames for snapshots and session indexes
- Existing deputy hooks and permissions reused by the compat facade

That boundary keeps the Anthropic surface available without making the
rest of the package Anthropic-specific. Plugins and marketplace
execution remain deferred until the settings and agent surface is more
mature.
