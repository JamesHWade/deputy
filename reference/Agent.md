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
for writes made through its native file tools.

- `$checkpoint(name = NULL, metadata = list())`:

  Create a manual file checkpoint and return its checkpoint ID.

- `$list_checkpoints()`:

  List available file checkpoints.

- `$rewind_files(checkpoint_id)`:

  Restore files to a checkpoint and invalidate later file history.
  Conversation history is not changed.

## Active bindings

- `agent_id`:

  Stable Agent instance identifier. Read-only.

- `agent_name`:

  Optional human-readable Agent name. Read-only.

- `run_context`:

  Default canonical product context. Read-only.

- `permissions`:

  Permission policy for the agent. Read-only after construction.

- `usage_limits`:

  Default per-run
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md).
  Read-only after construction.

- `context_policy`:

  Automatic context-management policy. Read-only.

- `working_dir`:

  Working directory for file operations. Read-only after construction.

- `hooks`:

  Hook registry for lifecycle events. Read-only after construction.

## Methods

### Public methods

- [`Agent$new()`](#method-Agent-initialize)

- [`Agent$run()`](#method-Agent-run)

- [`Agent$run_sync()`](#method-Agent-run_sync)

- [`Agent$chat()`](#method-Agent-chat)

- [`Agent$chat_async()`](#method-Agent-chat_async)

- [`Agent$chat_structured()`](#method-Agent-chat_structured)

- [`Agent$chat_structured_async()`](#method-Agent-chat_structured_async)

- [`Agent$stream()`](#method-Agent-stream)

- [`Agent$stream_async()`](#method-Agent-stream_async)

- [`Agent$last_run()`](#method-Agent-last_run)

- [`Agent$last_compaction()`](#method-Agent-last_compaction)

- [`Agent$resolve_tool_result()`](#method-Agent-resolve_tool_result)

- [`Agent$add_turn()`](#method-Agent-add_turn)

- [`Agent$get_turns()`](#method-Agent-get_turns)

- [`Agent$set_turns()`](#method-Agent-set_turns)

- [`Agent$get_system_prompt()`](#method-Agent-get_system_prompt)

- [`Agent$set_system_prompt()`](#method-Agent-set_system_prompt)

- [`Agent$get_tools()`](#method-Agent-get_tools)

- [`Agent$set_tools()`](#method-Agent-set_tools)

- [`Agent$get_tokens()`](#method-Agent-get_tokens)

- [`Agent$get_cost()`](#method-Agent-get_cost)

- [`Agent$token_count()`](#method-Agent-token_count)

- [`Agent$get_provider()`](#method-Agent-get_provider)

- [`Agent$get_model()`](#method-Agent-get_model)

- [`Agent$get_model_object()`](#method-Agent-get_model_object)

- [`Agent$set_model()`](#method-Agent-set_model)

- [`Agent$register_tool()`](#method-Agent-register_tool)

- [`Agent$register_tools()`](#method-Agent-register_tools)

- [`Agent$on_tool_request()`](#method-Agent-on_tool_request)

- [`Agent$on_tool_result()`](#method-Agent-on_tool_result)

- [`Agent$add_hook()`](#method-Agent-add_hook)

- [`Agent$turns()`](#method-Agent-turns)

- [`Agent$last_turn()`](#method-Agent-last_turn)

- [`Agent$session_id()`](#method-Agent-session_id)

- [`Agent$get_permission_mode()`](#method-Agent-get_permission_mode)

- [`Agent$set_permission_mode()`](#method-Agent-set_permission_mode)

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

- [`Agent$load_mcp()`](#method-Agent-load_mcp)

- [`Agent$mcp_tools()`](#method-Agent-mcp_tools)

- [`Agent$mcp_status()`](#method-Agent-mcp_status)

- [`Agent$run_async()`](#method-Agent-run_async)

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
      usage_limits = UsageLimits(max_requests = 25),
      context_policy = ContextPolicy(),
      enable_file_checkpointing = FALSE,
      file_checkpoint_max_file_bytes = 50 * 1024^2,
      file_checkpoint_max_journal_bytes = 250 * 1024^2,
      working_dir = getwd(),
      session_id = NULL,
      run_context = list(),
      agent_id = NULL,
      agent_name = NULL,
      fallback_chats = list()
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

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  applied independently to each run. Defaults to 25 model requests. Use
  [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for no limits.

- `context_policy`:

  A
  [ContextPolicy](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  controlling automatic compaction and durable offloading of large tool
  results.

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

- `session_id`:

  Optional stable session identifier used for correlation. A unique
  identifier is generated by default.

- `run_context`:

  Immutable canonical JSON-compatible product context inherited by each
  run. Credential-like fields and runtime objects are rejected.

- `agent_id`:

  Optional stable identifier for this Agent instance. A unique
  identifier is generated by default.

- `agent_name`:

  Optional human-readable Agent name.

- `fallback_chats`:

  Ordered configured ellmer Chats, explicitly allowed to receive this
  conversation after a transient failure before any response. Templates
  are cloned; their connection/model settings are preserved and their
  history, system prompt, and tools are replaced by the Agent's. The
  selected Chat remains active for subsequent runs. Applies to governed
  task and structured requests. Pre-run automatic compaction retains the
  separate
  [ContextPolicy](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  summary-failure policy.

#### Returns

A new `Agent` object

------------------------------------------------------------------------

### `Agent$run()`

Run an agentic task with semantic streaming events.

Returns a generator that yields
[AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
objects as the agent works. The agent will continue until the task is
complete, a run limit is reached, or it is interrupted.

#### Usage

    Agent$run(
      task,
      usage_limits = NULL,
      include_partial_messages = TRUE,
      run_context = list(),
      type = NULL,
      validate = NULL,
      max_corrections = 0L
    )

#### Arguments

- `task`:

  The task for the agent to perform

- `usage_limits`:

  Optional
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  override for this run.

- `include_partial_messages`:

  If TRUE (default), yield partial text chunks as they stream. If FALSE,
  only yield `text_complete`.

- `run_context`:

  Canonical JSON-compatible context to add to or narrow for this run.
  Protected constructor identity fields cannot change.

- `type`:

  Optional ellmer type. Complete the task with tools, then extract from
  the conversation within the same run budget.

- `validate`:

  Optional synchronous function receiving ellmer's value. Return TRUE,
  FALSE, or non-empty correction feedback. Errors and NA are terminal.

- `max_corrections`:

  Maximum additional structured requests after invalid output. Defaults
  to zero; all attempts share the run budget.

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
      usage_limits = NULL,
      include_partial_messages = TRUE,
      run_context = list(),
      type = NULL,
      validate = NULL,
      max_corrections = 0L
    )

#### Arguments

- `task`:

  The task for the agent to perform

- `usage_limits`:

  Optional
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  override for this run.

- `include_partial_messages`:

  If TRUE (default), keep partial text events. If FALSE, suppress
  partials.

- `run_context`:

  Canonical JSON-compatible context to add to or narrow for this run.
  Protected constructor identity fields cannot change.

- `type`:

  Optional ellmer type. Complete the task with tools, then extract from
  the conversation within the same run budget.

- `validate`:

  Optional synchronous function receiving ellmer's value. Return TRUE,
  FALSE, or non-empty correction feedback. Errors and NA are terminal.

- `max_corrections`:

  Maximum additional structured requests after invalid output. Defaults
  to zero; all attempts share the run budget.

#### Returns

An
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
object

------------------------------------------------------------------------

### `Agent$chat()`

Send messages synchronously using the ellmer Chat interface.

All requests pass through Deputy's run kernel. The return value matches
`ellmer::Chat$chat()`; inspect
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
metadata with `$last_run()`.

#### Usage

    Agent$chat(..., echo = NULL, run_context = list())

#### Arguments

- `...`:

  User content accepted by ellmer.

- `echo`:

  Accepted for ellmer compatibility.

- `run_context`:

  Canonical JSON-compatible context to add to or narrow for this run.

#### Returns

The final assistant text.

------------------------------------------------------------------------

### `Agent$chat_async()`

Send messages asynchronously using the ellmer Chat interface.

#### Usage

    Agent$chat_async(
      ...,
      tool_mode = c("concurrent", "sequential"),
      run_context = list()
    )

#### Arguments

- `...`:

  User content accepted by ellmer.

- `tool_mode`:

  Whether ellmer executes tool calls concurrently or sequentially.

- `run_context`:

  Canonical JSON-compatible context to add to or narrow for this run.

#### Returns

A promise resolving to the final assistant text.

------------------------------------------------------------------------

### `Agent$chat_structured()`

Send a structured request through the governed run kernel.

#### Usage

    Agent$chat_structured(
      ...,
      type,
      echo = "none",
      convert = TRUE,
      run_context = list(),
      validate = NULL,
      max_corrections = 0L
    )

#### Arguments

- `...`:

  User content accepted by ellmer.

- `type`:

  An ellmer structured-output type.

- `echo`:

  Echo mode forwarded to ellmer.

- `convert`:

  Whether ellmer converts the structured response.

- `run_context`:

  Canonical JSON-compatible context to add to or narrow for this run.

- `validate`:

  Optional synchronous function receiving ellmer's value. Return TRUE,
  FALSE, or non-empty correction feedback. Errors and NA are terminal.

- `max_corrections`:

  Maximum additional structured requests after invalid output. Defaults
  to zero; all attempts share the run budget.

#### Returns

Structured response data.

------------------------------------------------------------------------

### `Agent$chat_structured_async()`

Send an asynchronous structured request through Deputy.

#### Usage

    Agent$chat_structured_async(
      ...,
      type,
      echo = "none",
      convert = TRUE,
      run_context = list(),
      validate = NULL,
      max_corrections = 0L
    )

#### Arguments

- `...`:

  User content accepted by ellmer.

- `type`:

  An ellmer structured-output type.

- `echo`:

  Echo mode forwarded to ellmer.

- `convert`:

  Whether ellmer converts the structured response.

- `run_context`:

  Canonical JSON-compatible context to add to or narrow for this run.

- `validate`:

  Optional synchronous function receiving ellmer's value. Return TRUE,
  FALSE, or non-empty correction feedback. Errors and NA are terminal.

- `max_corrections`:

  Maximum additional structured requests after invalid output. Defaults
  to zero; all attempts share the run budget.

#### Returns

A promise resolving to structured response data.

------------------------------------------------------------------------

### `Agent$stream()`

Stream synchronously using the ellmer Chat interface.

#### Usage

    Agent$stream(
      ...,
      stream = c("text", "content"),
      controller = NULL,
      run_context = list(),
      type = NULL
    )

#### Arguments

- `...`:

  User content accepted by ellmer.

- `stream`:

  Yield text or semantic ellmer content.

- `controller`:

  Optional ellmer stream controller.

- `run_context`:

  Canonical JSON-compatible context to add to or narrow for this run.

- `type`:

  Optional ellmer type for native structured streaming. Providers
  requiring schema-tool fallback must use `chat_structured()`.

#### Returns

A synchronous generator.

------------------------------------------------------------------------

### `Agent$stream_async()`

Stream asynchronously using the ellmer Chat interface.

This is the primary interface for shinychat. It returns the same content
stream as ellmer while enforcing Deputy permissions, hooks, limits,
workspace resolution, context management, and run accounting.

#### Usage

    Agent$stream_async(
      ...,
      tool_mode = c("concurrent", "sequential"),
      stream = c("text", "content"),
      controller = NULL,
      run_context = list(),
      type = NULL
    )

#### Arguments

- `...`:

  User content accepted by ellmer, including shinychat's list of
  attachment-enabled `Content` objects.

- `tool_mode`:

  Whether ellmer executes tool calls concurrently or sequentially.

- `stream`:

  Yield text or semantic ellmer content.

- `controller`:

  Optional ellmer stream controller.

- `run_context`:

  Canonical JSON-compatible context to add to or narrow for this run.

- `type`:

  Optional ellmer type for native structured streaming. Providers
  requiring schema-tool fallback must use `chat_structured()`.

#### Returns

An asynchronous generator suitable for
[`shinychat::chat_append()`](https://posit-dev.github.io/shinychat/r/reference/chat_append.html).

------------------------------------------------------------------------

### `Agent$last_run()`

Return the most recently completed governed run.

#### Usage

    Agent$last_run()

#### Returns

An
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md),
or `NULL` before the first run completes.

------------------------------------------------------------------------

### `Agent$last_compaction()`

Return the most recent compaction outcome.

#### Usage

    Agent$last_compaction()

#### Returns

A `DeputyCompaction`, or `NULL` before compaction occurs.

------------------------------------------------------------------------

### `Agent$resolve_tool_result()`

Resolve a durable tool-result reference.

#### Usage

    Agent$resolve_tool_result(reference)

#### Arguments

- `reference`:

  A `deputy://tool-result/...` URI or reference text emitted into model
  context.

#### Returns

The complete original R value.

------------------------------------------------------------------------

### `Agent$add_turn()`

Add a user/assistant turn pair, as in ellmer Chat.

#### Usage

    Agent$add_turn(user, assistant, log_tokens = TRUE)

#### Arguments

- `user`:

  User turn or content.

- `assistant`:

  Assistant turn or content.

- `log_tokens`:

  Whether ellmer should log token metadata.

#### Returns

Invisible self.

------------------------------------------------------------------------

### `Agent$get_turns()`

Return conversation turns, as in ellmer Chat.

#### Usage

    Agent$get_turns(include_system_prompt = FALSE)

#### Arguments

- `include_system_prompt`:

  Include the system prompt as a turn.

#### Returns

A list of ellmer turns.

------------------------------------------------------------------------

### `Agent$set_turns()`

Replace conversation turns, as in ellmer Chat. During a run, already
accrued usage remains charged after history replacement.

#### Usage

    Agent$set_turns(value)

#### Arguments

- `value`:

  A list of ellmer turns.

#### Returns

Invisible self.

------------------------------------------------------------------------

### `Agent$get_system_prompt()`

Return the system prompt, as in ellmer Chat.

#### Usage

    Agent$get_system_prompt()

#### Returns

The system prompt or `NULL`.

------------------------------------------------------------------------

### `Agent$set_system_prompt()`

Replace the system prompt, as in ellmer Chat.

#### Usage

    Agent$set_system_prompt(value)

#### Arguments

- `value`:

  The new system prompt or `NULL`.

#### Returns

Invisible self.

------------------------------------------------------------------------

### `Agent$get_tools()`

Return registered tools, as in ellmer Chat.

#### Usage

    Agent$get_tools()

#### Returns

A named list of ellmer tool definitions.

------------------------------------------------------------------------

### `Agent$set_tools()`

Replace registered tools, preserving Deputy adaptation.

#### Usage

    Agent$set_tools(tools)

#### Arguments

- `tools`:

  A list of ellmer tool definitions.

#### Returns

Invisible self.

------------------------------------------------------------------------

### `Agent$get_tokens()`

Return provider token records, as in ellmer Chat.

#### Usage

    Agent$get_tokens(include_system_prompt = NULL)

#### Arguments

- `include_system_prompt`:

  Deprecated ellmer compatibility argument.

#### Returns

A token data frame.

------------------------------------------------------------------------

### `Agent$get_cost()`

Return provider cost records, as in ellmer Chat.

#### Usage

    Agent$get_cost(include = c("all", "last"))

#### Arguments

- `include`:

  Return all costs or only the latest request.

#### Returns

Provider cost information.

------------------------------------------------------------------------

### `Agent$token_count()`

Estimate tokens, as in ellmer Chat.

#### Usage

    Agent$token_count(..., include = c("new", "complete"), type = NULL)

#### Arguments

- `...`:

  User content accepted by ellmer.

- `include`:

  Count only new content or the complete context.

- `type`:

  Optional provider content type.

#### Returns

Estimated token count.

------------------------------------------------------------------------

### `Agent$get_provider()`

Return the ellmer provider.

#### Usage

    Agent$get_provider()

#### Returns

An ellmer provider object.

------------------------------------------------------------------------

### `Agent$get_model()`

Return the configured model name.

#### Usage

    Agent$get_model()

#### Returns

Model identifier.

------------------------------------------------------------------------

### `Agent$get_model_object()`

Return ellmer's configured model object.

#### Usage

    Agent$get_model_object()

#### Returns

An ellmer model object, including parameters and extra arguments.

------------------------------------------------------------------------

### `Agent$set_model()`

Replace the configured model.

#### Usage

    Agent$set_model(model)

#### Arguments

- `model`:

  Model identifier.

#### Returns

Invisible self.

------------------------------------------------------------------------

### `Agent$register_tool()`

Register a tool with the agent.

Function tools are wrapped with Deputy's runtime enforcement. Known
provider-native web tools are authorized once, before registration,
because their execution occurs inside the provider rather than R. Native
tools therefore require static permissions and cannot be registered with
a custom `can_use_tool` callback. Existing names require explicit
replacement. Every tool in a batch is validated and adapted before the
registry changes. List element names do not rename tools; each tool's
own name is authoritative.

#### Usage

    Agent$register_tool(tool, replace = FALSE)

#### Arguments

- `tool`:

  A tool created with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  or a supported provider-native web tool.

- `replace`:

  Replace tools already registered under the same name? Defaults to
  FALSE. Duplicate names within a batch always fail.

#### Returns

Invisible self for chaining

------------------------------------------------------------------------

### `Agent$register_tools()`

Register multiple tools with the agent.

#### Usage

    Agent$register_tools(tools, replace = FALSE)

#### Arguments

- `tools`:

  A list of function tools or supported provider-native web tools.

- `replace`:

  Replace tools already registered under the same name? Defaults to
  FALSE. Duplicate names within a batch always fail.

#### Returns

Invisible self for chaining

------------------------------------------------------------------------

### `Agent$on_tool_request()`

Register an additional ellmer tool-request observer.

#### Usage

    Agent$on_tool_request(callback)

#### Arguments

- `callback`:

  A function with one `request` argument.

#### Returns

A function that removes the observer.

------------------------------------------------------------------------

### `Agent$on_tool_result()`

Register an additional ellmer tool-result observer.

#### Usage

    Agent$on_tool_result(callback)

#### Arguments

- `callback`:

  A function with one `result` argument.

#### Returns

A function that removes the observer.

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

    Agent$last_turn(role = c("assistant", "user", "system"))

#### Arguments

- `role`:

  Role to filter by ("assistant", "user", or "system")

#### Returns

A Turn object or NULL

------------------------------------------------------------------------

### `Agent$session_id()`

Get this agent's session identifier.

#### Usage

    Agent$session_id()

#### Returns

Character session identifier

------------------------------------------------------------------------

### `Agent$get_permission_mode()`

Get the active permission mode.

#### Usage

    Agent$get_permission_mode()

#### Returns

Character permission mode

------------------------------------------------------------------------

### `Agent$set_permission_mode()`

Preserve or narrow the active permission mode for subsequent tool calls.
Reapplying the current mode is a no-op. Widening or incomparable mode
changes require a newly configured `Agent` so custom restrictions remain
an immutable authority ceiling. When narrowing removes web access,
registered provider-native web tools are removed before the new policy
becomes active because Deputy cannot interpose on provider-side calls.

#### Usage

    Agent$set_permission_mode(mode)

#### Arguments

- `mode`:

  Permission mode, see
  [PermissionMode](https://jameshwade.github.io/deputy/reference/PermissionMode.md)

#### Returns

Invisible self

------------------------------------------------------------------------

### `Agent$cost()`

Get cost information for the conversation.

#### Usage

    Agent$cost()

#### Returns

A list with input, output, and cached token counts; total estimated
cost; and `complete` and `missing` fields describing provider cost
coverage. An incomplete total is `NA_real_`.

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

- The cumulative compaction summary

- Portable copies of offloaded tool results

- Effective run context

- File checkpoint state, when enabled

- Metadata (timestamp, version, provider info)

#### Returns

Invisible path

------------------------------------------------------------------------

### `Agent$load_session()`

Load a session from an RDS file.

#### Usage

    Agent$load_session(path)

#### Arguments

- `path`:

  Path to the session file

#### Details

Tools, permissions, hooks, and the working directory are runtime policy
and are never restored from a session file. Saved run context is
validated before conversation state changes and merged with constructor
context; protected identity conflicts fail the load. Compaction
summaries and integrity-checked tool-result envelopes are restored as
conversational state under the receiving Agent's session identity.

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

    Agent$compact(
      keep_last = NULL,
      summary = NULL,
      fallback = self$context_policy$fallback,
      automatic = FALSE,
      estimated_tokens = NULL
    )

#### Arguments

- `keep_last`:

  Number of recent turns to retain. `NULL` chooses a complete
  conversational boundary using the context policy's token target.

- `summary`:

  Optional custom summary to use instead of auto-generating. If NULL,
  the LLM will generate a summary focusing on key decisions, findings,
  files discussed, and task progress.

- `fallback`:

  What to do when LLM summary generation fails.

- `automatic`:

  Whether the run kernel triggered this compaction.

- `estimated_tokens`:

  Optional pre-compaction token estimate.

#### Details

The compaction process:

1.  Fires the PreCompact hook (can cancel or provide custom summary)

2.  If no custom summary, uses LLM to summarize compacted turns

3.  Appends summary to system prompt under "Previous Conversation
    Summary"

4.  Keeps only the most recent `keep_last` turns

LLM summary-generation failures are errors by default. A deterministic
truncated-text summary is used only when `fallback = "text"` is
explicitly configured. The returned object records that degraded method.

#### Returns

A `DeputyCompaction` describing the method and usage.

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

### `Agent$load_mcp()`

Load tools from MCP (Model Context Protocol) servers.

Requires the mcptools package. Issues a warning if not installed or if
tool fetching fails.

#### Usage

    Agent$load_mcp(config = NULL, servers = NULL, replace = FALSE)

#### Arguments

- `config`:

  Path to MCP configuration file. If NULL (default), uses the mcptools
  default location (`~/.config/mcptools/config.json`).

- `servers`:

  Optional character vector of server names to load from. If NULL, loads
  from all configured servers.

- `replace`:

  Refresh the selected servers' complete tool sets, removing obsolete
  tools, and explicitly replace other matching names. On failure, tools
  whose connections were invalidated are removed; working tools remain.

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

### `Agent$run_async()`

Run an agentic task asynchronously and resolve to an
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).

Uses the same run kernel as `$stream_async()`, `$stream()`, `$chat()`,
and `$run_sync()`. It collects the final response and run metadata
rather than returning the content stream.

Use this when an Agent is a *worker* inside a larger async system, for
example a delegated sub-agent executed from the tool of a parent chat
that is itself streaming. Supply `type` to extract structured output
after the tool-using task within the same run budget.

#### Usage

    Agent$run_async(
      task,
      usage_limits = NULL,
      run_context = list(),
      type = NULL,
      validate = NULL,
      max_corrections = 0L
    )

#### Arguments

- `task`:

  The task for the agent to perform

- `usage_limits`:

  Optional
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  override for this run. Unset fields fall back to the Agent's limits.
  With `on_exceed = "error"`, hitting a limit rejects the promise with
  the structured limit error instead of resolving with a typed
  `stop_reason`.

- `run_context`:

  Canonical JSON-compatible context to add to or narrow for this run.
  Protected constructor identity fields cannot change.

- `type`:

  Optional ellmer type. Complete the task with tools, then extract from
  the conversation within the same run budget.

- `validate`:

  Optional synchronous function receiving ellmer's value. Return TRUE,
  FALSE, or non-empty correction feedback. Errors and NA are terminal.

- `max_corrections`:

  Maximum additional structured requests after invalid output. Defaults
  to zero; all attempts share the run budget.

#### Returns

A
[`promises::promise`](https://rstudio.github.io/promises/reference/promise.html)
resolving to an
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).
It is rejected if the provider stream fails or a limit configured with
`on_exceed = "error"` is reached.

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
  chat = ellmer::chat("openai/gpt-5.6-luna"),
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
