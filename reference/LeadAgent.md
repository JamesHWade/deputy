# Agent that delegates to subagents

An [Agent](https://jameshwade.github.io/deputy/reference/Agent.md) that
can hand tasks to subagents. Its model gets a `delegate_to_agent` tool
for picking a registered
[`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md);
each delegation runs a new subagent in its own conversation and returns
its answer. See
[`vignette("multi-agent")`](https://jameshwade.github.io/deputy/articles/multi-agent.md).

## Super class

[`Agent`](https://jameshwade.github.io/deputy/reference/Agent.md) -\>
`LeadAgent`

## Active bindings

- `sub_agent_defs`:

  A copy of the registered definitions. Use `$register_sub_agent()` to
  add one.

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
- [`Agent$microcompact()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-microcompact)
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
- [`Agent$set_chat()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-set_chat)
- [`Agent$set_context_policy()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-set_context_policy)
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

  An ellmer `Chat` for the lead.

- `sub_agents`:

  A list of
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  objects.

- `tools`:

  Tools for the lead, in addition to `delegate_to_agent`.

- `system_prompt`:

  System prompt for the lead; a list of the subagents is appended.

- `permissions`:

  [Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
  for the lead and, by default, its subagents. A definition can only
  narrow them.

- `usage_limits`:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for each lead run, shared with the subagents it starts.

- `context_policy`:

  A
  [ContextPolicy](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  for compaction and large tool results, used by the lead and its
  subagents.

- `enable_file_checkpointing`:

  Whether to checkpoint files before Deputy's file tools change them, so
  changes can be rewound. The lead and its subagents share the
  checkpoints.

- `file_checkpoint_max_file_bytes`:

  Maximum size, in bytes, of one file saved in a checkpoint. Defaults to
  50 MiB.

- `file_checkpoint_max_journal_bytes`:

  Maximum total size, in bytes, of all checkpoint data. Defaults to 250
  MiB.

- `working_dir`:

  Working directory, shared with subagents.

- `session_id`:

  Optional session ID, generated by default.

- `run_context`:

  Named list of JSON-compatible values, such as a user ID, attached to
  every run of the lead and its subagents.

- `agent_id`:

  Optional ID for the lead, generated by default.

- `agent_name`:

  Optional display name for the lead.

- `fallback_chats`:

  Chats to switch to, in order, if the lead's provider fails; see
  [Agent](https://jameshwade.github.io/deputy/reference/Agent.md).
  Subagents have no fallbacks; those that inherit the lead's model use
  its current chat.

- `delegation_sources`:

  Text sources that tasks can cite as evidence (see
  [DelegationInput](https://jameshwade.github.io/deputy/reference/DelegationInput.md)):
  an unnamed list of up to 128 records, 16 MiB in total, each with
  `source_id`, `revision`, `owner_id`, `conversation_id` and `text`, and
  optionally `allowed_agents`, the definitions that may receive it
  (`NULL` for all). Each `source_id` may have one revision per owner and
  conversation. Deputy checks the scope and revision, not whether the
  user may see a source, so include only sources they may see.

- `delegation_scope`:

  A list with `owner_id` and `conversation_id`, required with
  `delegation_sources`. Only sources with the same owner and
  conversation can be used, and the model can't change it. It is also
  passed to the
  [DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  `authorize` function.

- `delegation_max_bytes`:

  Size limit, in bytes, checked separately for a delegation's task,
  evidence, starting prompt and message, and
  [DelegationManifest](https://jameshwade.github.io/deputy/reference/DelegationManifest.md).
  Defaults to 64 KiB. A delegation over this limit, or whose estimated
  tokens exceed the
  [ContextPolicy](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  `max_tokens`, fails before any model request.

- `delegation_policy`:

  A
  [DelegationPolicy](https://jameshwade.github.io/deputy/reference/DelegationPolicy.md)
  for subagent tools, hooks and user questions.

- `delegation_disclosure`:

  A
  [DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  that decides who may inspect subagents and their history. The default
  denies everyone.

- `delegation_observation`:

  A
  [DelegationObservation](https://jameshwade.github.io/deputy/reference/DelegationObservation.md)
  setting the size of the event buffer read by `$observe_subagents()`.

- `approval_dir`:

  Optional directory for durable tool approvals; see
  [Agent](https://jameshwade.github.io/deputy/reference/Agent.md). A
  lead with `approval_dir` set can't delegate.

- `trusted_results`:

  Optional
  [TrustedResults](https://jameshwade.github.io/deputy/reference/TrustedResults.md)
  policy that also covers every subagent and its tools. A designated
  tool may belong to the lead or a subagent, but must be the same tool
  everywhere. Subagents' trusted results are recorded in the lead's run
  and passed to its `on_result`.

#### Returns

A new `LeadAgent` object

------------------------------------------------------------------------

### `LeadAgent$register_sub_agent()`

Add a subagent definition, or replace one with the same name, for
example to give a subagent a different set of tools. Delegations that
are already running keep the definition they started with.

#### Usage

    LeadAgent$register_sub_agent(definition, replace = FALSE)

#### Arguments

- `definition`:

  An
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  object

- `replace`:

  If `TRUE`, replace a registered definition with the same name. If
  `FALSE` (the default), a name clash is an error.

#### Returns

The lead, invisibly.

------------------------------------------------------------------------

### `LeadAgent$available_sub_agents()`

List the names of the registered subagent definitions.

#### Usage

    LeadAgent$available_sub_agents()

#### Returns

A character vector.

------------------------------------------------------------------------

### `LeadAgent$parallel_delegate()`

Ask several subagents for one reply each, in parallel.

Each named definition gets a fresh conversation, no tools and at most
one model request, so definitions with tools, skills or `mcp_servers`
are rejected. The lead's conversation is not changed.

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

  A named character vector, or a named list of strings and
  [DelegationInput](https://jameshwade.github.io/deputy/reference/DelegationInput.md)
  objects. Each name selects a different registered definition.

- `max_active`:

  Maximum number of subagents running at once.

- `mode`:

  Only `"stateless"` is supported.

- `usage_limits`:

  Optional
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for the whole batch; unset fields use the lead's. Token and cost
  limits are split between the subagents running at once and checked
  after each reply, so the batch can overshoot by one reply per running
  subagent.

- `run_context`:

  Named list added to the lead's `run_context` for this batch.

#### Returns

A list with `mode`, `results`
([AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
objects, `NULL` where none was returned), `outcomes`
([DelegationOutcome](https://jameshwade.github.io/deputy/reference/DelegationOutcome.md)
objects), `errors`, `status`, and `run`, an
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
for the whole batch that `$last_run()` also returns. Entries follow the
order of `tasks`, including failed and unstarted ones; a failure doesn't
discard the other results.

------------------------------------------------------------------------

### `LeadAgent$parallel_delegate_async()`

Version of `$parallel_delegate()` that doesn't block R.

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

A promise that resolves to the same list as `$parallel_delegate()`.
Calling `$interrupt()` cancels tasks that haven't started and asks
running subagents to stop.

------------------------------------------------------------------------

### `LeadAgent$interrupt()`

Ask the lead and its running subagents to stop.

#### Usage

    LeadAgent$interrupt(reason = "interrupted")

#### Arguments

- `reason`:

  Reason recorded on the stopped runs.

#### Returns

Invisibly, whether the lead or a subagent was running.

------------------------------------------------------------------------

### `LeadAgent$print()`

Print the lead and the names of its subagent definitions.

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
