# LeadAgent R6 Class

A LeadAgent is an agent that can delegate tasks to specialized
sub-agents. It automatically has a `delegate_to_agent` tool that allows
it to spawn sub-agents based on registered AgentDefinitions.

## Super class

[`Agent`](https://jameshwade.github.io/deputy/reference/Agent.md) -\>
`LeadAgent`

## Active bindings

- `sub_agent_defs`:

  Read-only snapshot of registered AgentDefinitions.

## Methods

### Public methods

- [`LeadAgent$new()`](#method-LeadAgent-initialize)

- [`LeadAgent$register_sub_agent()`](#method-LeadAgent-register_sub_agent)

- [`LeadAgent$available_sub_agents()`](#method-LeadAgent-available_sub_agents)

- [`LeadAgent$list_subagents()`](#method-LeadAgent-list_subagents)

- [`LeadAgent$get_subagent_results()`](#method-LeadAgent-get_subagent_results)

- [`LeadAgent$get_subagent_messages()`](#method-LeadAgent-get_subagent_messages)

- [`LeadAgent$print()`](#method-LeadAgent-print)

- [`LeadAgent$clone()`](#method-LeadAgent-clone)

Inherited methods

- [`Agent$add_hook()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-add_hook)
- [`Agent$add_turn()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-add_turn)
- [`Agent$chat()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-chat)
- [`Agent$chat_async()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-chat_async)
- [`Agent$chat_structured()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-chat_structured)
- [`Agent$chat_structured_async()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-chat_structured_async)
- [`Agent$checkpoint()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-checkpoint)
- [`Agent$compact()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-compact)
- [`Agent$cost()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-cost)
- [`Agent$get_cost()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_cost)
- [`Agent$get_model()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_model)
- [`Agent$get_permission_mode()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_permission_mode)
- [`Agent$get_provider()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_provider)
- [`Agent$get_system_prompt()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_system_prompt)
- [`Agent$get_tokens()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_tokens)
- [`Agent$get_tools()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_tools)
- [`Agent$get_turns()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_turns)
- [`Agent$interrupt()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-interrupt)
- [`Agent$last_compaction()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-last_compaction)
- [`Agent$last_run()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-last_run)
- [`Agent$last_turn()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-last_turn)
- [`Agent$list_checkpoints()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-list_checkpoints)
- [`Agent$load_mcp()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-load_mcp)
- [`Agent$load_session()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-load_session)
- [`Agent$load_skill()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-load_skill)
- [`Agent$mcp_status()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-mcp_status)
- [`Agent$mcp_tools()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-mcp_tools)
- [`Agent$on_tool_request()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-on_tool_request)
- [`Agent$on_tool_result()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-on_tool_result)
- [`Agent$provider()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-provider)
- [`Agent$register_tool()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-register_tool)
- [`Agent$register_tools()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-register_tools)
- [`Agent$resolve_tool_result()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-resolve_tool_result)
- [`Agent$rewind_files()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-rewind_files)
- [`Agent$run()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-run)
- [`Agent$run_async()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-run_async)
- [`Agent$run_sync()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-run_sync)
- [`Agent$save_session()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-save_session)
- [`Agent$session_id()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-session_id)
- [`Agent$set_model()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-set_model)
- [`Agent$set_permission_mode()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-set_permission_mode)
- [`Agent$set_system_prompt()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-set_system_prompt)
- [`Agent$set_tools()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-set_tools)
- [`Agent$set_turns()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-set_turns)
- [`Agent$skills()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-skills)
- [`Agent$stream()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-stream)
- [`Agent$stream_async()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-stream_async)
- [`Agent$token_count()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-token_count)
- [`Agent$turns()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-turns)
- [`Agent$usage()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-usage)

------------------------------------------------------------------------

### `LeadAgent$new()`

Create a new LeadAgent.

#### Usage

    LeadAgent$new(
      chat,
      sub_agents = list(),
      tools = list(),
      system_prompt = NULL,
      permissions = NULL,
      usage_limits = NULL,
      context_policy = ContextPolicy(),
      enable_file_checkpointing = FALSE,
      file_checkpoint_max_file_bytes = 50 * 1024^2,
      file_checkpoint_max_journal_bytes = 250 * 1024^2,
      working_dir = getwd(),
      session_id = NULL,
      run_context = list(),
      agent_id = NULL,
      agent_name = NULL
    )

#### Arguments

- `chat`:

  An ellmer Chat object

- `sub_agents`:

  List of
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  objects

- `tools`:

  Additional tools for the lead agent

- `system_prompt`:

  System prompt for the lead agent

- `permissions`:

  Permissions for the lead agent (also applied to sub-agents)

- `usage_limits`:

  Optional
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for each lead-agent run.

- `context_policy`:

  A
  [ContextPolicy](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  controlling automatic compaction and durable offloading of large tool
  results for the lead agent and its delegated agents.

- `enable_file_checkpointing`:

  Whether to journal reversible file preimages in one workspace journal
  shared by the lead agent and its delegated agents.

- `file_checkpoint_max_file_bytes`:

  Maximum bytes captured for one file preimage. Defaults to 50 MiB.

- `file_checkpoint_max_journal_bytes`:

  Maximum aggregate serialized bytes for workspace checkpoint records,
  markers, metadata, and pending captures. Defaults to 250 MiB.

- `working_dir`:

  Working directory

- `session_id`:

  Optional stable session identifier used for correlation. A unique
  identifier is generated by default.

- `run_context`:

  Immutable canonical product context inherited by lead runs and
  delegated agents.

- `agent_id`:

  Optional stable identifier for this LeadAgent instance.

- `agent_name`:

  Optional human-readable LeadAgent name.

#### Returns

A new `LeadAgent` object

------------------------------------------------------------------------

### `LeadAgent$register_sub_agent()`

Register a new sub-agent definition.

#### Usage

    LeadAgent$register_sub_agent(definition)

#### Arguments

- `definition`:

  An
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  object

#### Returns

Invisible self

------------------------------------------------------------------------

### `LeadAgent$available_sub_agents()`

Get available sub-agent names.

#### Usage

    LeadAgent$available_sub_agents()

#### Returns

Character vector of sub-agent names

------------------------------------------------------------------------

### `LeadAgent$list_subagents()`

List delegated sub-agent runs, including failures.

#### Usage

    LeadAgent$list_subagents()

#### Returns

Data frame with one row per sub-agent run

------------------------------------------------------------------------

### `LeadAgent$get_subagent_results()`

Get retained results from delegated sub-agent runs.

#### Usage

    LeadAgent$get_subagent_results(agent_name = NULL, delegation_id = NULL)

#### Arguments

- `agent_name`:

  Optional sub-agent name filter

- `delegation_id`:

  Optional delegation identifier filter

#### Returns

List of
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
objects or `NULL` entries for failed runs

------------------------------------------------------------------------

### `LeadAgent$get_subagent_messages()`

Get stored turn history for delegated sub-agent runs.

#### Usage

    LeadAgent$get_subagent_messages(agent_name = NULL, session_id = NULL)

#### Arguments

- `agent_name`:

  Optional sub-agent name filter

- `session_id`:

  Optional sub-agent session id filter

#### Returns

List of turn histories

------------------------------------------------------------------------

### `LeadAgent$print()`

Print the lead agent.

#### Usage

    LeadAgent$print()

------------------------------------------------------------------------

### `LeadAgent$clone()`

The objects of this class are cloneable with this method.

#### Usage

    LeadAgent$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
