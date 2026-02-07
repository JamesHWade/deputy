# Agent R6 Class

The main class for creating AI agents that can use tools to accomplish
tasks. Agent wraps an ellmer Chat object and adds agentic capabilities
including multi-turn execution, permission enforcement, and streaming
output.

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

## Public fields

- `chat`:

  The wrapped ellmer Chat object

- `permissions`:

  Permission policy for the agent

- `working_dir`:

  Working directory for file operations

- `hooks`:

  Hook registry for lifecycle events

## Methods

### Public methods

- [`Agent$new()`](#method-Agent-new)

- [`Agent$run()`](#method-Agent-run)

- [`Agent$run_sync()`](#method-Agent-run_sync)

- [`Agent$register_tool()`](#method-Agent-register_tool)

- [`Agent$register_tools()`](#method-Agent-register_tools)

- [`Agent$add_hook()`](#method-Agent-add_hook)

- [`Agent$turns()`](#method-Agent-turns)

- [`Agent$last_turn()`](#method-Agent-last_turn)

- [`Agent$cost()`](#method-Agent-cost)

- [`Agent$provider()`](#method-Agent-provider)

- [`Agent$save_session()`](#method-Agent-save_session)

- [`Agent$load_session()`](#method-Agent-load_session)

- [`Agent$compact()`](#method-Agent-compact)

- [`Agent$print()`](#method-Agent-print)

- [`Agent$load_skill()`](#method-Agent-load_skill)

- [`Agent$skills()`](#method-Agent-skills)

- [`Agent$slash_commands()`](#method-Agent-slash_commands)

- [`Agent$settings()`](#method-Agent-settings)

- [`Agent$load_mcp()`](#method-Agent-load_mcp)

- [`Agent$mcp_tools()`](#method-Agent-mcp_tools)

- [`Agent$run_shiny()`](#method-Agent-run_shiny)

- [`Agent$clone()`](#method-Agent-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new Agent.

#### Usage

    Agent$new(
      chat,
      tools = list(),
      system_prompt = NULL,
      permissions = NULL,
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

### Method `run()`

Run an agentic task with streaming output.

Returns a generator that yields
[AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
objects as the agent works. The agent will continue until the task is
complete, max_turns is reached, or the cost limit is exceeded.

#### Usage

    Agent$run(
      task,
      max_turns = NULL,
      include_partial_messages = TRUE,
      output_format = NULL
    )

#### Arguments

- `task`:

  The task for the agent to perform

- `max_turns`:

  Maximum number of turns (default: from permissions)

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

### Method `run_sync()`

Run an agentic task and block until completion.

Convenience wrapper around `run()` that collects all events and returns
an
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).

#### Usage

    Agent$run_sync(
      task,
      max_turns = NULL,
      include_partial_messages = TRUE,
      output_format = NULL
    )

#### Arguments

- `task`:

  The task for the agent to perform

- `max_turns`:

  Maximum number of turns (default: from permissions)

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

### Method `register_tool()`

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

### Method `register_tools()`

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

### Method `add_hook()`

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

    \dontrun{
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
    }

------------------------------------------------------------------------

### Method `turns()`

Get the conversation history.

#### Usage

    Agent$turns()

#### Returns

A list of Turn objects

------------------------------------------------------------------------

### Method `last_turn()`

Get the last turn in the conversation.

#### Usage

    Agent$last_turn(role = "assistant")

#### Arguments

- `role`:

  Role to filter by ("assistant", "user", or "system")

#### Returns

A Turn object or NULL

------------------------------------------------------------------------

### Method `cost()`

Get cost information for the conversation.

#### Usage

    Agent$cost()

#### Returns

A list with input, output, cached, and total token costs

------------------------------------------------------------------------

### Method `provider()`

Get provider information.

#### Usage

    Agent$provider()

#### Returns

A list with provider name and model

------------------------------------------------------------------------

### Method `save_session()`

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

### Method `load_session()`

Load a session from an RDS file.

#### Usage

    Agent$load_session(path, restore_tools = TRUE)

#### Arguments

- `path`:

  Path to the session file

- `restore_tools`:

  If TRUE (default), restore tools from session

#### Details

Note: Hooks are NOT restored from sessions as they contain function
closures that may not serialize correctly.

#### Returns

Invisible self

------------------------------------------------------------------------

### Method `compact()`

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

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print the agent configuration.

#### Usage

    Agent$print()

------------------------------------------------------------------------

### Method `load_skill()`

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

### Method `skills()`

Get loaded skills.

#### Usage

    Agent$skills()

#### Returns

Named list of loaded
[Skill](https://jameshwade.github.io/deputy/reference/Skill.md) objects.

------------------------------------------------------------------------

### Method `slash_commands()`

Get registered slash commands.

#### Usage

    Agent$slash_commands()

#### Returns

Named list of slash command definitions

------------------------------------------------------------------------

### Method `settings()`

Get applied Claude-style settings.

#### Usage

    Agent$settings()

#### Returns

Settings list returned by
[`claude_settings_load()`](https://jameshwade.github.io/deputy/reference/claude_settings_load.md)

------------------------------------------------------------------------

### Method `load_mcp()`

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

### Method `mcp_tools()`

Get names of loaded MCP tools.

#### Usage

    Agent$mcp_tools()

#### Returns

Character vector of MCP tool names

------------------------------------------------------------------------

### Method `run_shiny()`

Run an agentic task for use in Shiny applications with shinychat.

Returns an async content stream suitable for passing to
[`shinychat::chat_append()`](https://posit-dev.github.io/shinychat/r/reference/chat_append.html).
Unlike `run()` and `run_sync()`, the multi-turn loop is driven by
ellmer's `stream_async()` rather than deputy's own generator. Deputy's
permissions, hooks, and tool call limits are still enforced via the
`on_tool_request` callback.

#### Usage

    Agent$run_shiny(prompt, max_tool_calls = NULL)

#### Arguments

- `prompt`:

  The user message to send

- `max_tool_calls`:

  Maximum number of tool calls before stopping. Defaults to
  `permissions$max_turns` or 25. Note this counts individual tool call
  requests, not LLM turns (one turn can have multiple parallel tool
  calls).

#### Returns

A promise that resolves when the stream is complete, suitable for
[`shinychat::chat_append()`](https://posit-dev.github.io/shinychat/r/reference/chat_append.html).

------------------------------------------------------------------------

### Method `clone()`

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
for (event in agent$run("List files in the current directory")) {
  if (event$type == "text") cat(event$text)
}

# Or use the blocking convenience method
result <- agent$run_sync("List files")
print(result$response)
} # }

## ------------------------------------------------
## Method `Agent$add_hook`
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
