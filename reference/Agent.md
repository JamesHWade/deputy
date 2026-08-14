# Agent R6 Class

The main class for creating AI agents that can use tools to accomplish
tasks. Agent wraps an ellmer Chat object and adds agentic capabilities
including multi-turn execution, permission enforcement, and streaming
output.

**Security Note:** Core agent fields are read-only from the public API
after construction. Internal lifecycle methods may update the underlying
state through private storage when required.

## Skill Methods

The following methods manage skills:

- `$load_skill(skill, allow_conflicts = FALSE)`:

  Load a [Skill](https://jameshwade.github.io/deputy/reference/Skill.md)
  into the agent. The `skill` parameter can be a Skill object or path to
  a skill directory. If `allow_conflicts` is FALSE (default), an error
  is thrown when skill tools conflict with existing tools. Set to TRUE
  to allow overwriting. Returns invisible self.

- `$skills()`:

  Get a named list of loaded
  [Skill](https://jameshwade.github.io/deputy/reference/Skill.md)
  objects.

## MCP Methods

The following methods manage MCP (Model Context Protocol) server tools:

- `$load_mcp(config = NULL, servers = NULL)`:

  Load tools from MCP servers. The `config` parameter specifies the path
  to the MCP config file (defaults to `~/.config/mcptools/config.json`).
  The `servers` parameter optionally filters to specific server names.
  Requires the mcptools package. Returns invisible self.

- `$mcp_tools()`:

  Get names of loaded MCP tools.

## File checkpoint methods

When `enable_file_checkpointing = TRUE`, Deputy captures exact preimages
for writes made through its native and Agent SDK-compatible file tools.

- `$checkpoint(name = NULL, metadata = list())`:

  Create a manual file checkpoint and return its checkpoint ID.

- `$list_checkpoints()`:

  List available file checkpoints.

- `$rewind_files(checkpoint_id)`:

  Restore files to a checkpoint and invalidate later file history.
  Conversation history is not changed.

## Active bindings

- `chat`:

  The wrapped ellmer Chat object. Read-only after construction.

- `permissions`:

  Permission policy for the agent. Read-only after construction.

- `usage_limits`:

  Default per-run
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md).
  Read-only after construction.

- `working_dir`:

  Working directory for file operations. Read-only after construction.

- `hooks`:

  Hook registry for lifecycle events. Read-only after construction.

## Methods

### Public methods

- [`Agent$new()`](#method-Agent-initialize)

- [`Agent$run()`](#method-Agent-run)

- [`Agent$run_sync()`](#method-Agent-run_sync)

- [`Agent$register_tool()`](#method-Agent-register_tool)

- [`Agent$register_tools()`](#method-Agent-register_tools)

- [`Agent$add_hook()`](#method-Agent-add_hook)

- [`Agent$turns()`](#method-Agent-turns)

- [`Agent$last_turn()`](#method-Agent-last_turn)

- [`Agent$session_id()`](#method-Agent-session_id)

- [`Agent$get_permission_mode()`](#method-Agent-get_permission_mode)

- [`Agent$set_permission_mode()`](#method-Agent-set_permission_mode)

- [`Agent$configure_sdk_compat()`](#method-Agent-configure_sdk_compat)

- [`Agent$cost()`](#method-Agent-cost)

- [`Agent$usage()`](#method-Agent-usage)

- [`Agent$interrupt()`](#method-Agent-interrupt)

- [`Agent$provider()`](#method-Agent-provider)

- [`Agent$save_session()`](#method-Agent-save_session)

- [`Agent$load_session()`](#method-Agent-load_session)

- [`Agent$checkpoint()`](#method-Agent-checkpoint)

- [`Agent$list_checkpoints()`](#method-Agent-list_checkpoints)

- [`Agent$rewind_files()`](#method-Agent-rewind_files)

- [`Agent$compact()`](#method-Agent-compact)

- [`Agent$print()`](#method-Agent-print)

- [`Agent$load_skill()`](#method-Agent-load_skill)

- [`Agent$skills()`](#method-Agent-skills)

- [`Agent$slash_commands()`](#method-Agent-slash_commands)

- [`Agent$settings()`](#method-Agent-settings)

- [`Agent$load_mcp()`](#method-Agent-load_mcp)

- [`Agent$mcp_tools()`](#method-Agent-mcp_tools)

- [`Agent$mcp_status()`](#method-Agent-mcp_status)

- [`Agent$run_shiny()`](#method-Agent-run_shiny)

- [`Agent$clone()`](#method-Agent-clone)

------------------------------------------------------------------------

### `Agent$new()`

Create a new Agent.

#### Usage

    Agent$new(
      chat,
      tools = list(),
      system_prompt = NULL,
      permissions = NULL,
      usage_limits = NULL,
      enable_file_checkpointing = FALSE,
      file_checkpoint_max_file_bytes = 50 * 1024^2,
      file_checkpoint_max_journal_bytes = 250 * 1024^2,
      working_dir = getwd(),
      setting_sources = NULL,
      settings = NULL
    )

#### Arguments

- `chat`:

  An ellmer Chat object created by
  [`ellmer::chat()`](https://ellmer.tidyverse.org/reference/chat-any.html)
  or provider-specific functions like
  [`ellmer::chat_openai()`](https://ellmer.tidyverse.org/reference/chat_openai.html).

- `tools`:

  A list of tools created with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).
  See
  [`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md)
  and
  [`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md)
  for built-in tool bundles.

- `system_prompt`:

  Optional system prompt. If provided, overrides the chat object's
  existing system prompt.

- `permissions`:

  A
  [Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
  object controlling what the agent can do. Defaults to
  [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md).

- `usage_limits`:

  Optional
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  applied independently to each run. NULL request or cost fields inherit
  the legacy `permissions$max_turns` and `permissions$max_cost_usd`
  values.

- `enable_file_checkpointing`:

  Whether to journal exact file preimages for Deputy's mutating file
  tools. A checkpoint is created automatically at the beginning of every
  run.

- `file_checkpoint_max_file_bytes`:

  Maximum bytes captured for one file preimage. Defaults to 50 MiB.

- `file_checkpoint_max_journal_bytes`:

  Maximum aggregate serialized bytes for checkpoint records, markers,
  metadata, and pending captures. Defaults to 250 MiB.

- `working_dir`:

  Working directory for file operations. Defaults to current directory.

- `setting_sources`:

  Optional character vector of Claude-style setting sources (e.g.,
  "project", "user") used to load memory, skills, and slash commands.

- `settings`:

  Optional pre-loaded settings list from
  [`claude_settings_load()`](https://jameshwade.github.io/deputy/reference/claude_settings_load.md).
  If provided, bypasses `setting_sources`.

#### Returns

A new `Agent` object

------------------------------------------------------------------------

### `Agent$run()`

Run an agentic task with streaming output.

Returns a generator that yields
[AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
objects as the agent works. The agent will continue until the task is
complete, a run limit is reached, or it is interrupted.

#### Usage

    Agent$run(
      task,
      max_turns = NULL,
      usage_limits = NULL,
      include_partial_messages = TRUE,
      output_format = NULL
    )

#### Arguments

- `task`:

  The task for the agent to perform

- `max_turns`:

  Legacy alias for the maximum number of model requests. Defaults to the
  value seeded from permissions.

- `usage_limits`:

  Optional
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  override for this run.

- `include_partial_messages`:

  If TRUE (default), yield partial text chunks as they stream. If FALSE,
  only yield `text_complete`.

- `output_format`:

  Optional output format spec (e.g. JSON schema) to guide and validate
  structured responses.

#### Returns

A generator yielding
[AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
objects

------------------------------------------------------------------------

### `Agent$run_sync()`

Run an agentic task and block until completion.

Convenience wrapper around `run()` that collects all events and returns
an
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).

#### Usage

    Agent$run_sync(
      task,
      max_turns = NULL,
      usage_limits = NULL,
      include_partial_messages = TRUE,
      output_format = NULL
    )

#### Arguments

- `task`:

  The task for the agent to perform

- `max_turns`:

  Legacy alias for the maximum number of model requests. Defaults to the
  value seeded from permissions.

- `usage_limits`:

  Optional
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  override for this run.

- `include_partial_messages`:

  If TRUE (default), keep partial text events. If FALSE, suppress
  partials.

- `output_format`:

  Optional output format spec (e.g. JSON schema) to guide and validate
  structured responses.

#### Returns

An
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
object

------------------------------------------------------------------------

### `Agent$register_tool()`

Register a tool with the agent.

#### Usage

    Agent$register_tool(tool)

#### Arguments

- `tool`:

  A tool created with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)

#### Returns

Invisible self for chaining

------------------------------------------------------------------------

### `Agent$register_tools()`

Register multiple tools with the agent.

#### Usage

    Agent$register_tools(tools)

#### Arguments

- `tools`:

  A list of tools created with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)

#### Returns

Invisible self for chaining

------------------------------------------------------------------------

### `Agent$add_hook()`

Add a hook to the agent.

Hooks are called at specific points during agent execution and can
modify behavior (e.g., deny tool calls, log events).

#### Usage

    Agent$add_hook(hook)

#### Arguments

- `hook`:

  A
  [HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
  object

#### Returns

Invisible self for chaining

#### Examples

    # Add a hook to block dangerous bash commands
    agent$add_hook(hook_block_dangerous_bash())

    # Add a custom PreToolUse hook
    agent$add_hook(HookMatcher$new(
      event = "PreToolUse",
      pattern = "^write_file$",
      callback = function(tool_name, tool_input, context) {
        cli::cli_alert_info("Writing to: {tool_input$path}")
        HookResultPreToolUse(permission = "allow")
      }
    ))

------------------------------------------------------------------------

### `Agent$turns()`

Get the conversation history.

#### Usage

    Agent$turns()

#### Returns

A list of Turn objects

------------------------------------------------------------------------

### `Agent$last_turn()`

Get the last turn in the conversation.

#### Usage

    Agent$last_turn(role = "assistant")

#### Arguments

- `role`:

  Role to filter by ("assistant", "user", or "system")

#### Returns

A Turn object or NULL

------------------------------------------------------------------------

### `Agent$session_id()`

Get the active Claude SDK compatibility session identifier.

#### Usage

    Agent$session_id()

#### Returns

Character session id, or NULL when compat mode is inactive

------------------------------------------------------------------------

### `Agent$get_permission_mode()`

Get the active permission mode.

#### Usage

    Agent$get_permission_mode()

#### Returns

Character permission mode

------------------------------------------------------------------------

### `Agent$set_permission_mode()`

Change the active permission mode for subsequent tool calls.

#### Usage

    Agent$set_permission_mode(mode)

#### Arguments

- `mode`:

  Permission mode, see
  [PermissionMode](https://jameshwade.github.io/deputy/reference/PermissionMode.md)

#### Returns

Invisible self

------------------------------------------------------------------------

### `Agent$configure_sdk_compat()`

Configure Claude SDK compatibility behavior for this agent.

#### Usage

    Agent$configure_sdk_compat(config = list())

#### Arguments

- `config`:

  Named list of compat settings

#### Returns

Invisible self for chaining

------------------------------------------------------------------------

### `Agent$cost()`

Get cost information for the conversation.

#### Usage

    Agent$cost()

#### Returns

A list with input, output, cached, and total token costs

------------------------------------------------------------------------

### `Agent$usage()`

Get normalized usage for the complete in-memory conversation.

Per-run usage is available on
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
and in the final `usage` event returned by `$run()`.

#### Usage

    Agent$usage()

#### Returns

An
[AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
object

------------------------------------------------------------------------

### `Agent$interrupt()`

Request cancellation of the active stream.

Cancellation is cooperative and takes effect at the next provider or
tool boundary supported by ellmer.

#### Usage

    Agent$interrupt(reason = "interrupted")

#### Arguments

- `reason`:

  Stable reason stored on the terminal event

#### Returns

Invisible logical indicating whether a run was active

------------------------------------------------------------------------

### `Agent$provider()`

Get provider information.

#### Usage

    Agent$provider()

#### Returns

A list with provider name and model

------------------------------------------------------------------------

### `Agent$save_session()`

Save the current session to an RDS file.

#### Usage

    Agent$save_session(path)

#### Arguments

- `path`:

  Path to save the session

#### Details

The session file contains:

- Conversation turns

- System prompt

- Tool definitions (serialized)

- Permissions configuration

- Working directory

- Metadata (timestamp, version, provider info)

#### Returns

Invisible path

------------------------------------------------------------------------

### `Agent$load_session()`

Load a session from an RDS file.

#### Usage

    Agent$load_session(path, restore_tools = FALSE)

#### Arguments

- `path`:

  Path to the session file

- `restore_tools`:

  If TRUE, explicitly trust and restore serialized tool definitions.
  Defaults to FALSE; constructor-registered tools are otherwise
  preserved as control-plane policy.

#### Details

Note: Hooks are NOT restored from sessions as they contain function
closures that may not serialize correctly. Constructor permissions and
`working_dir` always remain authoritative.

#### Returns

Invisible self

------------------------------------------------------------------------

### `Agent$checkpoint()`

Create a reversible file checkpoint.

#### Usage

    Agent$checkpoint(name = NULL, metadata = list())

#### Arguments

- `name`:

  Optional checkpoint label.

- `metadata`:

  Optional serializable metadata list.

#### Returns

The checkpoint ID.

------------------------------------------------------------------------

### `Agent$list_checkpoints()`

List reversible file checkpoints.

#### Usage

    Agent$list_checkpoints()

#### Returns

A data frame ordered from oldest to newest.

------------------------------------------------------------------------

### `Agent$rewind_files()`

Rewind files to a checkpoint without changing conversation history.

#### Usage

    Agent$rewind_files(checkpoint_id)

#### Arguments

- `checkpoint_id`:

  ID returned by `$checkpoint()` or present in a `file_checkpoint` run
  event.

#### Returns

A list describing the restored checkpoint and change count.

------------------------------------------------------------------------

### `Agent$compact()`

Compact the conversation history to reduce context size.

This method uses the LLM to generate a meaningful summary of older
conversation turns, then replaces them with the summary appended to the
system prompt. This preserves important context while reducing token
usage.

#### Usage

    Agent$compact(keep_last = 4, summary = NULL)

#### Arguments

- `keep_last`:

  Number of recent turns to keep uncompacted (default: 4)

- `summary`:

  Optional custom summary to use instead of auto-generating. If NULL,
  the LLM will generate a summary focusing on key decisions, findings,
  files discussed, and task progress.

#### Details

The compaction process:

1.  Fires the PreCompact hook (can cancel or provide custom summary)

2.  If no custom summary, uses LLM to summarize compacted turns

3.  Appends summary to system prompt under "Previous Conversation
    Summary"

4.  Keeps only the most recent `keep_last` turns

If LLM summarization fails (e.g., no API key), falls back to a simple
text-based summary with truncated turn contents.

#### Returns

Invisible self

------------------------------------------------------------------------

### `Agent$print()`

Print the agent configuration.

#### Usage

    Agent$print()

------------------------------------------------------------------------

### `Agent$load_skill()`

Load a [Skill](https://jameshwade.github.io/deputy/reference/Skill.md)
into the agent.

#### Usage

    Agent$load_skill(skill, allow_conflicts = FALSE)

#### Arguments

- `skill`:

  A [Skill](https://jameshwade.github.io/deputy/reference/Skill.md)
  object or path to a skill directory.

- `allow_conflicts`:

  If FALSE (default), error on tool name conflicts. Set TRUE to allow
  overwriting existing tools.

#### Returns

Invisible self for chaining.

------------------------------------------------------------------------

### `Agent$skills()`

Get loaded skills.

#### Usage

    Agent$skills()

#### Returns

Named list of loaded
[Skill](https://jameshwade.github.io/deputy/reference/Skill.md) objects.

------------------------------------------------------------------------

### `Agent$slash_commands()`

Get registered slash commands.

#### Usage

    Agent$slash_commands()

#### Returns

Named list of slash command definitions

------------------------------------------------------------------------

### `Agent$settings()`

Get applied Claude-style settings.

#### Usage

    Agent$settings()

#### Returns

Settings list returned by
[`claude_settings_load()`](https://jameshwade.github.io/deputy/reference/claude_settings_load.md)

------------------------------------------------------------------------

### `Agent$load_mcp()`

Load tools from MCP (Model Context Protocol) servers.

Requires the mcptools package. Issues a warning if not installed or if
tool fetching fails.

#### Usage

    Agent$load_mcp(config = NULL, servers = NULL)

#### Arguments

- `config`:

  Path to MCP configuration file. If NULL (default), uses the mcptools
  default location (`~/.config/mcptools/config.json`).

- `servers`:

  Optional character vector of server names to load from. If NULL, loads
  from all configured servers.

#### Returns

Invisible self for chaining

------------------------------------------------------------------------

### `Agent$mcp_tools()`

Get names of loaded MCP tools.

#### Usage

    Agent$mcp_tools()

#### Returns

Character vector of MCP tool names

------------------------------------------------------------------------

### `Agent$mcp_status()`

Get MCP runtime status records.

#### Usage

    Agent$mcp_status()

#### Returns

Data frame describing MCP load attempts and registered tools

------------------------------------------------------------------------

### `Agent$run_shiny()`

Run an agentic task for use in Shiny applications with shinychat.

Returns an async content stream suitable for passing to
[`shinychat::chat_append()`](https://posit-dev.github.io/shinychat/r/reference/chat_append.html).
Unlike `run()` and `run_sync()`, the multi-turn loop is driven by
ellmer's `stream_async()` rather than deputy's own generator. Deputy's
permissions, hooks, and observable
[UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
are still enforced via callbacks and terminal accounting. File tools
must use absolute paths within `working_dir`; rejected calls still count
toward tool usage.

#### Usage

    Agent$run_shiny(prompt, max_tool_calls = NULL)

#### Arguments

- `prompt`:

  The user message to send

- `max_tool_calls`:

  Maximum number of tool calls before stopping. Overrides
  `usage_limits$max_tool_calls`; otherwise falls back to that value,
  `permissions$max_turns`, or 25. This counts individual tool call
  requests, not LLM turns (one turn can have multiple parallel calls).

#### Returns

An async content stream suitable for
[`shinychat::chat_append()`](https://posit-dev.github.io/shinychat/r/reference/chat_append.html).

------------------------------------------------------------------------

### `Agent$clone()`

The objects of this class are cloneable with this method.

#### Usage

    Agent$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Examples

``` r
if (FALSE) { # \dontrun{
# Create an agent with file tools
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = tools_file()
)

# Run a task with streaming output
events <- agent$run("List files in the current directory")
repeat {
  event <- events()
  if (coro::is_exhausted(event)) break
  if (event$type == "text") cat(event$text)
}

# Or use the blocking convenience method
result <- agent$run_sync("List files")
print(result$response)
} # }

## ------------------------------------------------
## Method `Agent$add_hook()`
## ------------------------------------------------

if (FALSE) { # \dontrun{
# Add a hook to block dangerous bash commands
agent$add_hook(hook_block_dangerous_bash())

# Add a custom PreToolUse hook
agent$add_hook(HookMatcher$new(
  event = "PreToolUse",
  pattern = "^write_file$",
  callback = function(tool_name, tool_input, context) {
    cli::cli_alert_info("Writing to: {tool_input$path}")
    HookResultPreToolUse(permission = "allow")
  }
))
} # }
```
