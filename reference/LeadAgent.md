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

- [`LeadAgent$parallel_delegate()`](#method-LeadAgent-parallel_delegate)

- [`LeadAgent$parallel_delegate_async()`](#method-LeadAgent-parallel_delegate_async)

- [`LeadAgent$interrupt()`](#method-LeadAgent-interrupt)

- [`LeadAgent$print()`](#method-LeadAgent-print)

- [`LeadAgent$clone()`](#method-LeadAgent-clone)

Inherited methods

- [`Agent$add_hook()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-add_hook)
- [`Agent$add_turn()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-add_turn)
- [`Agent$cancel_agent()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-cancel_agent)
- [`Agent$chat()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-chat)
- [`Agent$chat_async()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-chat_async)
- [`Agent$chat_structured()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-chat_structured)
- [`Agent$chat_structured_async()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-chat_structured_async)
- [`Agent$checkpoint()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-checkpoint)
- [`Agent$compact()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-compact)
- [`Agent$continue_agent()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-continue_agent)
- [`Agent$continue_agent_async()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-continue_agent_async)
- [`Agent$cost()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-cost)
- [`Agent$delegation_graph_usage()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-delegation_graph_usage)
- [`Agent$export_subagents()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-export_subagents)
- [`Agent$get_context_turns()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_context_turns)
- [`Agent$get_cost()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_cost)
- [`Agent$get_model()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_model)
- [`Agent$get_model_object()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_model_object)
- [`Agent$get_permission_mode()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_permission_mode)
- [`Agent$get_provider()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_provider)
- [`Agent$get_subagent_contexts()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_subagent_contexts)
- [`Agent$get_subagent_messages()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_subagent_messages)
- [`Agent$get_subagent_results()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_subagent_results)
- [`Agent$get_system_prompt()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_system_prompt)
- [`Agent$get_tokens()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_tokens)
- [`Agent$get_tools()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_tools)
- [`Agent$get_turns()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-get_turns)
- [`Agent$inspect_subagents()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-inspect_subagents)
- [`Agent$interrupt_subagent()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-interrupt_subagent)
- [`Agent$last_compaction()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-last_compaction)
- [`Agent$last_run()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-last_run)
- [`Agent$last_turn()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-last_turn)
- [`Agent$list_checkpoints()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-list_checkpoints)
- [`Agent$list_subagents()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-list_subagents)
- [`Agent$load_mcp()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-load_mcp)
- [`Agent$load_session()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-load_session)
- [`Agent$load_skill()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-load_skill)
- [`Agent$mcp_status()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-mcp_status)
- [`Agent$mcp_tools()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-mcp_tools)
- [`Agent$observe_subagents()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-observe_subagents)
- [`Agent$on_tool_request()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-on_tool_request)
- [`Agent$on_tool_result()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-on_tool_result)
- [`Agent$pending_approval()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-pending_approval)
- [`Agent$provider()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-provider)
- [`Agent$read_subagent_result()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-read_subagent_result)
- [`Agent$register_tool()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-register_tool)
- [`Agent$register_tools()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-register_tools)
- [`Agent$release_agent()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-release_agent)
- [`Agent$release_agent_graph()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-release_agent_graph)
- [`Agent$resolve_tool_result()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-resolve_tool_result)
- [`Agent$resume_approval()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-resume_approval)
- [`Agent$retain_agent()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-retain_agent)
- [`Agent$retain_agent_graph()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-retain_agent_graph)
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
      agent_name = NULL,
      fallback_chats = list(),
      delegation_sources = list(),
      delegation_scope = list(),
      delegation_max_bytes = 65536L,
      delegation_policy = DelegationPolicy(),
      delegation_disclosure = DelegationDisclosure(),
      delegation_observation = DelegationObservation(),
      approval_dir = NULL,
      trusted_results = NULL
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

- `fallback_chats`:

  Ordered configured fallback Chats for the lead. Child definitions
  inherit the selected provider, without an implicit fallback policy of
  their own. See
  [Agent](https://jameshwade.github.io/deputy/reference/Agent.md).

- `delegation_sources`:

  Host-owned snapshot: unnamed list of up to 128 text records with
  `source_id`, `revision`, `owner_id`, `conversation_id`, and `text`.
  Optional `allowed_agents` restricts definition names; `NULL` allows
  all registered definitions,
  [`character()`](https://rdrr.io/r/base/character.html) allows none.
  Each source ID has one revision per scope. The host authenticates and
  authorizes this snapshot; Deputy checks scope and exact revision, not
  live freshness.

- `delegation_scope`:

  Plain list with `owner_id` and `conversation_id`; required when
  sources are supplied. Model arguments cannot override it.

- `delegation_max_bytes`:

  Positive finite admission ceiling, default 64 KiB, applied separately
  to the UTF-8 system/message text and serialized complete manifest.
  Known complete-context estimates also obey
  [ContextPolicy](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  `max_tokens`; unknown estimates remain `NULL` and rely on byte bounds.
  Sources are text only, with a 16 MiB catalogue ceiling.

- `delegation_policy`:

  Host-only
  [DelegationPolicy](https://jameshwade.github.io/deputy/reference/DelegationPolicy.md)
  for child governance, resource ownership and interactive routing.

- `delegation_disclosure`:

  Host-only
  [DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  authorizing inspection and saved-history disclosure. Defaults to deny.

- `delegation_observation`:

  [DelegationObservation](https://jameshwade.github.io/deputy/reference/DelegationObservation.md)
  bounds for the transient child activity stream.

- `approval_dir`:

  Optional standalone lead approval directory. Delegation rejects this
  unsupported durable child-continuation combination.

- `trusted_results`:

  Optional
  [TrustedResults](https://jameshwade.github.io/deputy/reference/TrustedResults.md)
  policy for the whole delegation tree. Every child inherits it, so each
  definition's tools must pass the same no-bypass check. A designated
  tool may live in the lead or in children, but must be the same tool
  everywhere. Child trusted results are recorded in the lead's run and
  sent to its `on_result`.

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

### `LeadAgent$parallel_delegate()`

Run independent, stateless responders concurrently.

Each selected AgentDefinition gets a fresh conversation and at most one
model request. Definitions with tools, skills, or MCP servers are
rejected. This is tier-1 fan-out, not background tool-using agents.
Results preserve input order, including failures and unstarted tasks.

#### Usage

    LeadAgent$parallel_delegate(
      tasks,
      max_active = 2L,
      mode = "stateless",
      usage_limits = NULL,
      run_context = list()
    )

#### Arguments

- `tasks`:

  A named character vector or named list of strings and
  [DelegationInput](https://jameshwade.github.io/deputy/reference/DelegationInput.md)
  values. Names select unique registered AgentDefinitions.

- `max_active`:

  Maximum simultaneous responders.

- `mode`:

  Execution contract. Currently only `"stateless"` is supported.

- `usage_limits`:

  Optional batch-wide
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md).
  Unset fields inherit the lead's defaults. Requests are reserved before
  dispatch; token and cost ceilings are divided across each concurrent
  wave and checked after responses, with possible overage by one
  response per active responder.

- `run_context`:

  Additional immutable context for the batch.

#### Returns

A list with `mode`, named `results`
([AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
or `NULL`), named `outcomes`
([DelegationOutcome](https://jameshwade.github.io/deputy/reference/DelegationOutcome.md)),
`errors`, `status`, and an aggregate `run`
([AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)).
`$last_run()` retains the aggregate run. The lead's conversation is
unchanged. Failed responders do not discard successful siblings.

------------------------------------------------------------------------

### `LeadAgent$parallel_delegate_async()`

Run stateless fan-out without blocking the R event loop.

#### Usage

    LeadAgent$parallel_delegate_async(
      tasks,
      max_active = 2L,
      mode = "stateless",
      usage_limits = NULL,
      run_context = list()
    )

#### Arguments

- `tasks, max_active, mode, usage_limits, run_context`:

  See `$parallel_delegate()`.

#### Returns

A promise resolving to the same batch result as `$parallel_delegate()`.
`$interrupt()` cancels queued work and asks active responders to stop at
their next supported provider boundary.

------------------------------------------------------------------------

### `LeadAgent$interrupt()`

Interrupt the lead and its active subagents cooperatively.

#### Usage

    LeadAgent$interrupt(reason = "interrupted")

#### Arguments

- `reason`:

  Stable reason retained on stopped runs.

#### Returns

Invisible logical indicating whether the lead or a Subagent was active.

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
