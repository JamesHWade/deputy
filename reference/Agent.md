# Agent that runs tasks with tools

An `Agent` wraps an ellmer Chat and uses it to carry out tasks. The
model can call tools over several turns while the agent applies
permissions, hooks and usage limits and reports its progress as
[AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
objects. Use
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
when the agent should delegate work to subagents.

An `Agent` also works as an ellmer Chat (`$chat()`, `$stream_async()`,
`$get_turns()` and so on), so you can pass it to code that expects one,
such as shinychat.

Settings given to `$new()`, such as `permissions`, `usage_limits` and
`working_dir`, are read-only afterwards.

## File checkpoints

With `enable_file_checkpointing = TRUE`, the agent records the previous
contents of files changed by `write_file`, `edit_file` and `multi_edit`.
Changes made any other way, including by `run_r_code` or `run_bash`, are
not recorded. A checkpoint is created at the start of every run, and
`$checkpoint()` creates one on demand. `$rewind_files()` restores files
to a checkpoint without changing the conversation. A file tool call that
would exceed the checkpoint size limits is refused.

## Active bindings

- `agent_id`:

  The agent's ID. Read-only.

- `agent_name`:

  The agent's name, or `NULL`. Read-only.

- `run_context`:

  The `run_context` attached to every run. Read-only.

- `trusted_results`:

  The
  [TrustedResults](https://jameshwade.github.io/deputy/reference/TrustedResults.md)
  policy, or `NULL`. Read-only.

- `permissions`:

  The agent's
  [Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md).
  Read-only; use `$set_permission_mode()` to narrow them.

- `usage_limits`:

  The
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  applied to each run. Read-only.

- `context_policy`:

  The agent's
  [ContextPolicy](https://jameshwade.github.io/deputy/reference/ContextPolicy.md).
  Read-only.

- `working_dir`:

  The directory file tools work in. Read-only.

- `hooks`:

  The agent's
  [HookRegistry](https://jameshwade.github.io/deputy/reference/HookRegistry.md).
  The field can't be replaced; add hooks with `$add_hook()`.

## Methods

### Public methods

- [`Agent$new()`](#method-Agent-initialize)

- [`Agent$retain_agent()`](#method-Agent-retain_agent)

- [`Agent$retain_agent_graph()`](#method-Agent-retain_agent_graph)

- [`Agent$delegation_graph_usage()`](#method-Agent-delegation_graph_usage)

- [`Agent$release_agent_graph()`](#method-Agent-release_agent_graph)

- [`Agent$continue_agent_async()`](#method-Agent-continue_agent_async)

- [`Agent$continue_agent()`](#method-Agent-continue_agent)

- [`Agent$cancel_agent()`](#method-Agent-cancel_agent)

- [`Agent$release_agent()`](#method-Agent-release_agent)

- [`Agent$list_subagents()`](#method-Agent-list_subagents)

- [`Agent$get_subagent_results()`](#method-Agent-get_subagent_results)

- [`Agent$get_subagent_messages()`](#method-Agent-get_subagent_messages)

- [`Agent$get_subagent_contexts()`](#method-Agent-get_subagent_contexts)

- [`Agent$observe_subagents()`](#method-Agent-observe_subagents)

- [`Agent$interrupt_subagent()`](#method-Agent-interrupt_subagent)

- [`Agent$inspect_subagents()`](#method-Agent-inspect_subagents)

- [`Agent$export_subagents()`](#method-Agent-export_subagents)

- [`Agent$read_subagent_result()`](#method-Agent-read_subagent_result)

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

- [`Agent$get_context_turns()`](#method-Agent-get_context_turns)

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

- [`Agent$pending_approval()`](#method-Agent-pending_approval)

- [`Agent$resume_approval()`](#method-Agent-resume_approval)

- [`Agent$checkpoint()`](#method-Agent-checkpoint)

- [`Agent$list_checkpoints()`](#method-Agent-list_checkpoints)

- [`Agent$rewind_files()`](#method-Agent-rewind_files)

- [`Agent$compact()`](#method-Agent-compact)

- [`Agent$microcompact()`](#method-Agent-microcompact)

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

Create a new agent.

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
      fallback_chats = list(),
      approval_dir = NULL,
      delegation_scope = list(),
      delegation_disclosure = DelegationDisclosure(),
      delegation_observation = DelegationObservation(),
      trusted_results = NULL
    )

#### Arguments

- `chat`:

  An ellmer Chat, for example from
  [`ellmer::chat()`](https://ellmer.tidyverse.org/reference/chat-any.html).

- `tools`:

  A list of tools created with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).
  See
  [`tools_preset()`](https://jameshwade.github.io/deputy/reference/tools_preset.md),
  [`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md)
  and
  [`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md)
  for built-in tools.

- `system_prompt`:

  Optional system prompt. Replaces the Chat's system prompt.

- `permissions`:

  A
  [Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
  policy. Defaults to
  [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md)
  for `working_dir`.

- `usage_limits`:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  applied to each run separately. Defaults to 25 model requests per run.
  [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  sets no limits.

- `context_policy`:

  A
  [ContextPolicy](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  controlling automatic compaction and where large tool results are
  stored. The default compacts the conversation once it passes about
  32,000 tokens.

- `enable_file_checkpointing`:

  If `TRUE`, record file changes so they can be undone with
  `$rewind_files()`. See the "File checkpoints" section.

- `file_checkpoint_max_file_bytes`:

  Largest file, in bytes, whose previous contents a checkpoint can
  record. Defaults to 50 MiB.

- `file_checkpoint_max_journal_bytes`:

  Maximum total size, in bytes, of all checkpoint records. Defaults to
  250 MiB.

- `working_dir`:

  Directory that file tools work in. Must exist. Defaults to the current
  directory.

- `session_id`:

  Optional session ID. One is generated if not given.

- `run_context`:

  Named list of JSON-compatible values (strings, numbers, logicals and
  nested lists) attached to every event and result, for example user or
  conversation IDs. Keys that look like credentials, such as `password`
  or `api_key`, are rejected.

- `agent_id`:

  Optional agent ID. One is generated if not given.

- `agent_name`:

  Optional human-readable name.

- `fallback_chats`:

  A list of ellmer Chats to try, in order, when a request fails with a
  transient error (a network failure or HTTP 408, 429, 500, 502, 503
  or 504) before the run has received any response or called any tool.
  Each must have no turns or tools; the agent copies it and gives it the
  agent's system prompt, history and tools. Once used, a fallback stays
  in use for later runs. Compaction summaries don't use these; see
  `summary_fallback_chats` in
  [`ContextPolicy()`](https://jameshwade.github.io/deputy/reference/ContextPolicy.md).

- `approval_dir`:

  A directory, which must already exist, where tool calls waiting for
  approval are saved, so you can decide them later with
  `$resume_approval()`, even after restarting R. Tools that can wait for
  approval must be created with `ellmer::tool(convert = FALSE)`. When
  set, tools run one at a time. See
  [`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md).

- `delegation_scope`:

  Named list identifying what this agent belongs to, such as an owner or
  conversation ID. It is passed as `scope` to the `authorize` function
  of `delegation_disclosure`.

- `delegation_disclosure`:

  A
  [DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  that decides who may inspect this agent's subagents. The default
  denies everyone.

- `delegation_observation`:

  A
  [DelegationObservation](https://jameshwade.github.io/deputy/reference/DelegationObservation.md)
  setting how many subagent events are kept for `$observe_subagents()`.

- `trusted_results`:

  Optional
  [TrustedResults](https://jameshwade.github.io/deputy/reference/TrustedResults.md)
  policy naming the one tool allowed to produce each type of trusted
  result. Registering a tool that could get around it is an error.

#### Returns

A new `Agent` object.

------------------------------------------------------------------------

### `Agent$retain_agent()`

Retain another agent so you can send it more tasks with
`$continue_agent()`. The retained agent keeps its conversation between
tasks.

Until you call `$release_agent()`, the retained agent can't be run
directly, and its conversation, prompt, model, tools, hooks and tool
observers can't be changed (observers it already has keep working). An
agent can retain up to 32 others at a time. See
[`vignette("retained-agents", package = "deputy")`](https://jameshwade.github.io/deputy/articles/retained-agents.md).

#### Usage

    Agent$retain_agent(agent, usage_limits, max_runs = 32L)

#### Arguments

- `agent`:

  Another `Agent` (not a `LeadAgent`) with its own Chat and no
  `approval_dir`, `fallback_chats` or provider-native tools.

- `usage_limits`:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for all of its tasks combined, also capped by the retained agent's own
  limits.

- `max_runs`:

  Maximum number of tasks. Defaults to 32.

#### Returns

A handle (a string) that only this agent can use.

------------------------------------------------------------------------

### `Agent$retain_agent_graph()`

Retain several agents at once and let them delegate to each other
through tools you define in `routes`. This agent is the root of the
graph and holds every conversation in it. The graph's usage limits add
up across all delegated runs until you call `$release_agent_graph()`.

Routes may form a cycle, but delegating to an agent that is already
running fails. An agent waiting on its own delegate still counts toward
`max_concurrency`.

#### Usage

    Agent$retain_agent_graph(
      agents,
      routes,
      usage_limits,
      max_depth,
      max_delegations,
      max_concurrency,
      max_runs = 32L
    )

#### Arguments

- `agents`:

  Named list of distinct agents, each meeting the conditions in
  `$retain_agent()`. The name `root` is reserved for this agent.

- `routes`:

  Named list keyed by `root` or an agent name. Each element is a named
  list of delegation tools to add to that agent, where each tool is a
  list with `target` (an agent name), `description` and `usage_limits`.

- `usage_limits`:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for the whole graph. `max_requests` is required.

- `max_depth`:

  Maximum delegation depth. This agent's direct delegates are at depth
  1.

- `max_delegations`:

  Maximum number of delegations over the graph's lifetime.

- `max_concurrency`:

  Maximum number of delegations running at once.

- `max_runs`:

  Maximum number of tasks for each agent in the graph.

#### Returns

A named character vector of handles, one per agent, for use with
`$continue_agent()`.

------------------------------------------------------------------------

### `Agent$delegation_graph_usage()`

Get the total usage of all delegated runs in this agent's graph,
including runs still in progress. Errors if this agent doesn't own a
graph.

#### Usage

    Agent$delegation_graph_usage()

#### Returns

An
[AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
object.

------------------------------------------------------------------------

### `Agent$release_agent_graph()`

Release the graph, removing its route tools and handles. Errors if
anything in it is still running. This also discards the graph's
delegation records, so save them first with `$export_subagents()` if you
need them. The agents' own tools and connections are left open.

#### Usage

    Agent$release_agent_graph()

#### Returns

`NULL`, invisibly.

------------------------------------------------------------------------

### `Agent$continue_agent_async()`

Send a retained agent its next task. It still has its earlier
conversation. This errors, before any request is made, if the agent is
busy, was changed or released, has used up `max_runs`, or the handle
belongs to another agent. After a failed or cancelled task, call this
again to carry on.

#### Usage

    Agent$continue_agent_async(handle, task, usage_limits)

#### Arguments

- `handle`:

  A handle from this agent's `$retain_agent()` or
  `$retain_agent_graph()`.

- `task`:

  The next task, as one string of at most 64 KiB.

- `usage_limits`:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for this task. It is also capped by what remains of the handle's total
  budget and by the retained agent's own limits.

#### Returns

A promise that resolves to an
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).
If the task is cancelled before it starts, the result has zero usage and
no run ID.

------------------------------------------------------------------------

### `Agent$continue_agent()`

Blocking version of `$continue_agent_async()`.

#### Usage

    Agent$continue_agent(handle, task, usage_limits)

#### Arguments

- `handle, task, usage_limits`:

  See `$continue_agent_async()`.

#### Returns

An
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).

------------------------------------------------------------------------

### `Agent$cancel_agent()`

Ask a retained agent to stop its current task. The run stops at the next
safe point and keeps the conversation so far. Calling this more than
once is harmless.

#### Usage

    Agent$cancel_agent(handle, reason = "interrupted")

#### Arguments

- `handle`:

  A handle from `$retain_agent()`.

- `reason`:

  Stop reason recorded on the cancelled run.

#### Returns

`TRUE`, invisibly, if a task was cancelled; `FALSE` if the agent was
idle.

------------------------------------------------------------------------

### `Agent$release_agent()`

Stop retaining an agent so it can be used on its own again. This also
discards its delegation records, so save them first with
`$export_subagents()` if you need them. Its tools and connections stay
open. Errors while the agent is running: cancel it with
`$cancel_agent()` and wait for the task to end first. Agents in a graph
are released with `$release_agent_graph()`. Handles don't survive an R
restart.

#### Usage

    Agent$release_agent(handle)

#### Arguments

- `handle`:

  A handle from `$retain_agent()`.

#### Returns

`NULL`, invisibly.

------------------------------------------------------------------------

### `Agent$list_subagents()`

List this agent's delegations, oldest first, including ones still
running. The records are kept in memory only.

`status` is `"queued"`, `"running"`, `"completed"`, `"failed"`,
`"stopped"`, `"not_started"` or `"suspended"` (waiting for a tool
approval). `"completed"` means the subagent finished normally, not that
it did the task well; `stop_reason` gives the exact reason. IDs and
times are `NA` until known, and `completed_at` is set when the run ends
or is suspended. `input_error` says why a task was rejected before it
ran: `"invalid"`, `"missing"`, `"stale"`, `"unauthorized"` or
`"oversized"`. `hook_error` records errors from hooks watching the
subagent.

#### Usage

    Agent$list_subagents()

#### Returns

A data frame with one row per delegation.

------------------------------------------------------------------------

### `Agent$get_subagent_results()`

Get the results of delegated runs.

#### Usage

    Agent$get_subagent_results(agent_name = NULL, delegation_id = NULL)

#### Arguments

- `agent_name`:

  Only return results from subagents with this name.

- `delegation_id`:

  Only return the result of this delegation.

#### Returns

A list of
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
objects, oldest first. It holds `NULL` for runs that are still going,
never started, or failed without a result.

------------------------------------------------------------------------

### `Agent$get_subagent_messages()`

Get the conversation turns of each delegation. For a subagent that is
still running, you get the turns completed so far. Reading them doesn't
add anything to this agent's context. No disclosure checks are applied,
so use `$inspect_subagents()` before showing history to users.

#### Usage

    Agent$get_subagent_messages(agent_name = NULL, session_id = NULL)

#### Arguments

- `agent_name`:

  Only return turns from subagents with this name.

- `session_id`:

  Only return turns from the subagent with this session ID.

#### Returns

A list with one list of ellmer turns per delegation.

------------------------------------------------------------------------

### `Agent$get_subagent_contexts()`

See what each subagent was given at the start, or what its model context
holds now, oldest first. Nothing is sent to a model. No disclosure
checks are applied.

#### Usage

    Agent$get_subagent_contexts(
      delegation_id = NULL,
      view = "initial",
      redact = FALSE
    )

#### Arguments

- `delegation_id`:

  Only return this delegation.

- `view`:

  `"initial"` returns the
  [DelegationManifest](https://jameshwade.github.io/deputy/reference/DelegationManifest.md)
  recording what the subagent started with. `"current"` returns a list
  with its `system_prompt` and the `turns` in its model context.

- `redact`:

  If `TRUE` (only with `view = "initial"`), leave out the task,
  instructions and source text. Other metadata is still included.

#### Returns

A list with one entry per delegation, `NULL` where nothing is available.
For a finished subagent, `"current"` shows its context when it finished.

------------------------------------------------------------------------

### `Agent$observe_subagents()`

Follow subagent activity as it happens. The returned subscription lets
you poll for new events without affecting the subagents' runs.

#### Usage

    Agent$observe_subagents(requester, delegation_id = NULL, after = NULL)

#### Arguments

- `requester`:

  Whoever is asking, as identified by your app (for example a user ID).
  The `delegation_disclosure` policy checks it on every read.

- `delegation_id`:

  Only follow this delegation.

- `after`:

  A cursor from an earlier subscription on this agent, to resume from.
  `NULL` starts from now.

#### Returns

A
[DelegationSubscription](https://jameshwade.github.io/deputy/reference/DelegationSubscription.md).
Closing it stops observing but doesn't stop any subagent.

------------------------------------------------------------------------

### `Agent$interrupt_subagent()`

Ask a running subagent to stop. It stops at the next safe point; in a
delegation graph, its own delegations stop too. This doesn't consult
`delegation_disclosure`, so check that the user may do this before
calling it. Models can't call this method.

#### Usage

    Agent$interrupt_subagent(delegation_id, reason = "interrupted")

#### Arguments

- `delegation_id`:

  The delegation to stop.

- `reason`:

  Stop reason to record. Defaults to `"interrupted"`.

#### Returns

`TRUE`, invisibly, if a run was stopped; `FALSE` if the delegation is
unknown or already finished.

------------------------------------------------------------------------

### `Agent$inspect_subagents()`

Get a snapshot of each delegation that `requester` may see: its task,
its outcome (what Deputy observed, kept apart from what the subagent
claimed), usage, the
[DelegationManifest](https://jameshwade.github.io/deputy/reference/DelegationManifest.md)
it started from and any errors. Retained agents also report their total
usage across tasks; unknown usage is `NULL`. Each view passes through
the `delegation_disclosure` policy, which may redact it. Errors if
`requester` isn't allowed. Nothing is run.

#### Usage

    Agent$inspect_subagents(requester, delegation_id = NULL, transcript = FALSE)

#### Arguments

- `requester`:

  Whoever is asking, as identified by your app. Never pass values that
  came from a model.

- `delegation_id`:

  Only return this delegation. Unknown IDs give an empty list.

- `transcript`:

  If `TRUE`, also include the conversation, as `transcript` records and
  as ellmer `turns`. Hidden reasoning and raw provider data are left
  out.

#### Returns

A list of views, one per delegation. Changing them doesn't affect any
agent.

------------------------------------------------------------------------

### `Agent$export_subagents()`

Export finished delegations, with their conversations, so you can store
them and view them later with
[`delegation_history()`](https://jameshwade.github.io/deputy/reference/delegation_history.md).
The export is a record to read, not something you can resume.

#### Usage

    Agent$export_subagents(requester, delegation_id = NULL)

#### Arguments

- `requester, delegation_id`:

  See `$inspect_subagents()`.

#### Returns

A plain list for
[`delegation_history()`](https://jameshwade.github.io/deputy/reference/delegation_history.md).
Errors if a selected delegation is still running. Reading it back checks
a
[DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
again.

------------------------------------------------------------------------

### `Agent$read_subagent_result()`

Read part of a large result that a subagent saved, using a reference
from its `$inspect_subagents()` view. No tool or model is run.

#### Usage

    Agent$read_subagent_result(requester, delegation_id, reference, offset = 0L)

#### Arguments

- `requester, delegation_id`:

  See `$inspect_subagents()`.

- `reference`:

  A reference exactly as it appears in the delegation's view. Errors if
  it isn't there or the saved result is gone.

- `offset`:

  Character position to start reading from, starting at 0.

#### Returns

The view after redaction: a list whose `result` holds up to 8,192
characters from `offset`, with the next offset and total length.

------------------------------------------------------------------------

### `Agent$run()`

Run a task and stream its progress.

Returns a generator that yields
[AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
objects as the agent works. The run continues until the model finishes,
a usage limit is reached or it is interrupted. The `"stop"` event gives
the reason, and `$last_run()` then returns the
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).

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

  The task for the agent.

- `usage_limits`:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for this run. `NULL` fields use the agent's limits.

- `include_partial_messages`:

  If `TRUE` (the default), yield a `"text"` event for each streamed
  chunk. If `FALSE`, skip them; the full text still arrives in the
  `"text_complete"` event.

- `run_context`:

  Named list merged into the agent's `run_context` for this run. It
  can't change or remove ID fields (keys ending in `id`) that the agent
  already sets.

- `type`:

  Optional ellmer type, such as
  [`ellmer::type_object()`](https://ellmer.tidyverse.org/reference/type_boolean.html).
  After the task, the agent extracts data of this type from the
  conversation into the result's `structured_output`. This counts toward
  the run's limits.

- `validate`:

  Optional function that checks the extracted value. Return `TRUE` to
  accept it, or `FALSE` or a message to reject it; a message is sent to
  the model as feedback. An error or any other return value, such as
  `NA`, ends the run with an error.

- `max_corrections`:

  How many times to ask the model to fix a rejected value. Defaults
  to 0. If the value is still rejected, the run errors. Every attempt
  counts toward the run's limits.

#### Returns

A generator yielding
[AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
objects.

------------------------------------------------------------------------

### `Agent$run_sync()`

Run a task and wait for it to finish.

Runs `$run()` to the end and returns the
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md),
which holds every event.

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

  The task for the agent.

- `usage_limits`:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for this run. `NULL` fields use the agent's limits.

- `include_partial_messages`:

  Passed to `$run()`. It doesn't change the returned result, which
  always includes the `"text"` events.

- `run_context`:

  Named list merged into the agent's `run_context` for this run. It
  can't change or remove ID fields (keys ending in `id`) that the agent
  already sets.

- `type`:

  Optional ellmer type, such as
  [`ellmer::type_object()`](https://ellmer.tidyverse.org/reference/type_boolean.html).
  After the task, the agent extracts data of this type from the
  conversation into `result$structured_output`. This counts toward the
  run's limits.

- `validate`:

  Optional function that checks the extracted value. Return `TRUE` to
  accept it, or `FALSE` or a message to reject it; a message is sent to
  the model as feedback. An error or any other return value, such as
  `NA`, ends the run with an error.

- `max_corrections`:

  How many times to ask the model to fix a rejected value. Defaults
  to 0. If the value is still rejected, the run errors. Every attempt
  counts toward the run's limits.

#### Returns

An
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
object.

------------------------------------------------------------------------

### `Agent$chat()`

Send a message and return the reply, like `ellmer::Chat$chat()`, with
the agent's tools, permissions, hooks and usage limits applied.
`$last_run()` then returns the full
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).

#### Usage

    Agent$chat(..., echo = NULL, run_context = list())

#### Arguments

- `...`:

  Message content, as for ellmer.

- `echo`:

  Print the reply unless this is `"none"` or `FALSE`. Defaults to
  `getOption("ellmer_echo", "none")`.

- `run_context`:

  Named list merged into the agent's `run_context` for this run.

#### Returns

The reply text.

------------------------------------------------------------------------

### `Agent$chat_async()`

Asynchronous version of `$chat()`.

#### Usage

    Agent$chat_async(
      ...,
      tool_mode = c("concurrent", "sequential"),
      run_context = list()
    )

#### Arguments

- `...`:

  Message content, as for ellmer.

- `tool_mode`:

  `"concurrent"` runs the tool calls from one response in parallel;
  `"sequential"` runs them one at a time.

- `run_context`:

  Named list merged into the agent's `run_context` for this run.

#### Returns

A promise that resolves to the reply text.

------------------------------------------------------------------------

### `Agent$chat_structured()`

Extract structured data, like `ellmer::Chat$chat_structured()`, with the
agent's permissions, hooks and usage limits applied.

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

  Message content, as for ellmer.

- `type`:

  An ellmer type describing the data, such as
  [`ellmer::type_object()`](https://ellmer.tidyverse.org/reference/type_boolean.html).

- `echo`:

  Passed to ellmer.

- `convert`:

  Passed to ellmer: whether to convert the result to R objects.

- `run_context`:

  Named list merged into the agent's `run_context` for this run.

- `validate`:

  Optional function that checks the extracted value. Return `TRUE` to
  accept it, or `FALSE` or a message to reject it; a message is sent to
  the model as feedback. An error or any other return value, such as
  `NA`, ends the run with an error.

- `max_corrections`:

  How many times to ask the model to fix a rejected value. Defaults
  to 0. If the value is still rejected, the run errors. Every attempt
  counts toward the usage limits.

#### Returns

The extracted data.

------------------------------------------------------------------------

### `Agent$chat_structured_async()`

Asynchronous version of `$chat_structured()`.

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

  Message content, as for ellmer.

- `type`:

  An ellmer type describing the data, such as
  [`ellmer::type_object()`](https://ellmer.tidyverse.org/reference/type_boolean.html).

- `echo`:

  Passed to ellmer.

- `convert`:

  Passed to ellmer: whether to convert the result to R objects.

- `run_context`:

  Named list merged into the agent's `run_context` for this run.

- `validate`:

  Optional function that checks the extracted value. Return `TRUE` to
  accept it, or `FALSE` or a message to reject it; a message is sent to
  the model as feedback. An error or any other return value, such as
  `NA`, ends the run with an error.

- `max_corrections`:

  How many times to ask the model to fix a rejected value. Defaults
  to 0. If the value is still rejected, the run errors. Every attempt
  counts toward the usage limits.

#### Returns

A promise that resolves to the extracted data.

------------------------------------------------------------------------

### `Agent$stream()`

Stream a reply, like `ellmer::Chat$stream()`, with the agent's
permissions, hooks and usage limits applied.

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

  Message content, as for ellmer.

- `stream`:

  `"text"` yields text chunks; `"content"` yields ellmer content
  objects, including tool requests and results.

- `controller`:

  Optional ellmer stream controller.

- `run_context`:

  Named list merged into the agent's `run_context` for this run.

- `type`:

  Optional ellmer type for structured streaming, passed to ellmer. If
  the provider can't stream structured output, use `$chat_structured()`
  instead.

#### Returns

A generator.

------------------------------------------------------------------------

### `Agent$stream_async()`

Asynchronous version of `$stream()`. This is the method shinychat uses:
the stream is the same as ellmer's, with the agent's permissions, hooks,
usage limits and compaction applied.

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

  Message content, as for ellmer, including the attachment `Content`
  objects that shinychat sends.

- `tool_mode`:

  `"concurrent"` runs the tool calls from one response in parallel;
  `"sequential"` runs them one at a time.

- `stream`:

  `"text"` yields text chunks; `"content"` yields ellmer content
  objects, including tool requests and results.

- `controller`:

  Optional ellmer stream controller.

- `run_context`:

  Named list merged into the agent's `run_context` for this run.

- `type`:

  Optional ellmer type for structured streaming, passed to ellmer. If
  the provider can't stream structured output, use `$chat_structured()`
  instead.

#### Returns

An asynchronous generator suitable for
[`shinychat::chat_append()`](https://posit-dev.github.io/shinychat/r/reference/chat_append.html).

------------------------------------------------------------------------

### `Agent$last_run()`

Get the result of the most recent run.

#### Usage

    Agent$last_run()

#### Returns

An
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md),
or `NULL` before the first run finishes.

------------------------------------------------------------------------

### `Agent$last_compaction()`

Get the result of the most recent compaction.

#### Usage

    Agent$last_compaction()

#### Returns

A
[DeputyCompaction](https://jameshwade.github.io/deputy/reference/DeputyCompaction.md),
or `NULL` if there hasn't been one.

------------------------------------------------------------------------

### `Agent$resolve_tool_result()`

Get the full value of a large tool result that was saved outside the
model context.

#### Usage

    Agent$resolve_tool_result(reference)

#### Arguments

- `reference`:

  A `deputy://tool-result/...` reference, or text containing one, such
  as the placeholder the model saw.

#### Returns

The stored R value. ellmer content objects saved during compaction come
back as text.

------------------------------------------------------------------------

### `Agent$add_turn()`

Add a user turn and an assistant turn, as ellmer's `$add_turn()` does.

#### Usage

    Agent$add_turn(user, assistant, log_tokens = TRUE)

#### Arguments

- `user`:

  User turn or content.

- `assistant`:

  Assistant turn or content.

- `log_tokens`:

  Passed to ellmer's `$add_turn()`.

#### Returns

The agent, invisibly.

------------------------------------------------------------------------

### `Agent$get_turns()`

Get the whole conversation, as ellmer's `$get_turns()` does. Unlike
`$get_context_turns()`, this includes turns that compaction removed from
the model context, and the original tool results that `$microcompact()`
cleared. Removed turns stay in memory until `$set_turns()` replaces the
conversation.

#### Usage

    Agent$get_turns(include_system_prompt = FALSE)

#### Arguments

- `include_system_prompt`:

  Include the system prompt as a turn.

#### Returns

A list of ellmer turns.

------------------------------------------------------------------------

### `Agent$get_context_turns()`

Get the turns the model currently sees. After compaction this is shorter
than `$get_turns()`, and tool results cleared by `$microcompact()` show
their marker.

#### Usage

    Agent$get_context_turns(include_system_prompt = FALSE)

#### Arguments

- `include_system_prompt`:

  Include the system prompt, with any compaction summary, as a turn.

#### Returns

A list of ellmer turns.

------------------------------------------------------------------------

### `Agent$set_turns()`

Replace the conversation, as ellmer's `$set_turns()` does. This also
drops any compaction summary and the turns compaction removed. During a
run, usage counted so far still counts.

#### Usage

    Agent$set_turns(value)

#### Arguments

- `value`:

  A list of ellmer turns.

#### Returns

The agent, invisibly.

------------------------------------------------------------------------

### `Agent$get_system_prompt()`

Get the system prompt, as ellmer's `$get_system_prompt()` does. After
compaction it includes the conversation summary.

#### Usage

    Agent$get_system_prompt()

#### Returns

The system prompt or `NULL`.

------------------------------------------------------------------------

### `Agent$set_system_prompt()`

Replace the system prompt, as ellmer's `$set_system_prompt()` does.
After compaction, this also drops the conversation summary unless
`value` still contains it.

#### Usage

    Agent$set_system_prompt(value)

#### Arguments

- `value`:

  The new system prompt or `NULL`.

#### Returns

The agent, invisibly.

------------------------------------------------------------------------

### `Agent$get_tools()`

Get the registered tools, as ellmer's `$get_tools()` does.

#### Usage

    Agent$get_tools()

#### Returns

A named list of ellmer tool definitions.

------------------------------------------------------------------------

### `Agent$set_tools()`

Replace all registered tools. The new tools are checked and wrapped as
in `$register_tools()`.

#### Usage

    Agent$set_tools(tools)

#### Arguments

- `tools`:

  A list of ellmer tool definitions.

#### Returns

The agent, invisibly.

------------------------------------------------------------------------

### `Agent$get_tokens()`

Get token usage by turn, as ellmer's `$get_tokens()` does.

#### Usage

    Agent$get_tokens(include_system_prompt = NULL)

#### Arguments

- `include_system_prompt`:

  Deprecated; passed to ellmer.

#### Returns

A data frame.

------------------------------------------------------------------------

### `Agent$get_cost()`

Get the estimated cost, as ellmer's `$get_cost()` does.

#### Usage

    Agent$get_cost(include = c("all", "last"))

#### Arguments

- `include`:

  `"all"` for every turn or `"last"` for the latest request.

#### Returns

The cost, as returned by ellmer.

------------------------------------------------------------------------

### `Agent$token_count()`

Count tokens, as ellmer's `$token_count()` does.

#### Usage

    Agent$token_count(..., include = c("new", "complete"), type = NULL)

#### Arguments

- `...`:

  Message content, as for ellmer.

- `include`:

  `"new"` counts only the new content; `"complete"` counts the whole
  context too.

- `type`:

  Optional ellmer type, passed to ellmer.

#### Returns

Estimated token count.

------------------------------------------------------------------------

### `Agent$get_provider()`

Get the ellmer provider.

#### Usage

    Agent$get_provider()

#### Returns

An ellmer provider object.

------------------------------------------------------------------------

### `Agent$get_model()`

Get the model name.

#### Usage

    Agent$get_model()

#### Returns

The model name.

------------------------------------------------------------------------

### `Agent$get_model_object()`

Get ellmer's model object.

#### Usage

    Agent$get_model_object()

#### Returns

An ellmer model object, including parameters and extra arguments.

------------------------------------------------------------------------

### `Agent$set_model()`

Change the model.

#### Usage

    Agent$set_model(model)

#### Arguments

- `model`:

  Model name.

#### Returns

The agent, invisibly.

------------------------------------------------------------------------

### `Agent$register_tool()`

Add a tool. Calls to it go through the agent's permission checks and
hooks.

Provider-native web search and fetch tools run on the provider's
servers, not in R, so they are checked once, when you register them. The
permissions must have `web = TRUE`, list the tool in `tool_allowlist`
and have no `can_use_tool` callback.

#### Usage

    Agent$register_tool(tool, replace = FALSE)

#### Arguments

- `tool`:

  A tool created with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  or a supported provider-native web tool.

- `replace`:

  If `TRUE`, replace a registered tool with the same name. If `FALSE`
  (the default), a name clash is an error.

#### Returns

The agent, invisibly, for chaining.

------------------------------------------------------------------------

### `Agent$register_tools()`

Add several tools, as `$register_tool()` does. All of them are checked
before any is added, so if one fails, none are added. List names are
ignored: each tool keeps its own name.

#### Usage

    Agent$register_tools(tools, replace = FALSE)

#### Arguments

- `tools`:

  A list of tools created with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  or supported provider-native web tools.

- `replace`:

  If `TRUE`, replace registered tools with the same names. If `FALSE`
  (the default), a name clash is an error. Two tools with the same name
  in `tools` are always an error.

#### Returns

The agent, invisibly, for chaining.

------------------------------------------------------------------------

### `Agent$on_tool_request()`

Add a callback that runs when the model requests a tool, as ellmer's
`$on_tool_request()` does.

#### Usage

    Agent$on_tool_request(callback)

#### Arguments

- `callback`:

  A function with one `request` argument.

#### Returns

A function that removes the callback.

------------------------------------------------------------------------

### `Agent$on_tool_result()`

Add a callback that runs when a tool returns a result, as ellmer's
`$on_tool_result()` does.

#### Usage

    Agent$on_tool_result(callback)

#### Arguments

- `callback`:

  A function with one `result` argument.

#### Returns

A function that removes the callback.

------------------------------------------------------------------------

### `Agent$add_hook()`

Add a hook. Hooks run at set points in a run (see
[HookEvent](https://jameshwade.github.io/deputy/reference/HookEvent.md)).
They can observe the run and, at some points, change it, for example by
denying a tool call.

#### Usage

    Agent$add_hook(hook)

#### Arguments

- `hook`:

  A
  [HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
  object.

#### Returns

The agent, invisibly, for chaining.

#### Examples

    # Add a hook to block dangerous bash commands
    agent$add_hook(hook_block_dangerous_bash())

    # Add a custom PreToolUse hook
    agent$add_hook(HookMatcher(
      event = "PreToolUse",
      pattern = "^write_file$",
      callback = function(tool_name, tool_input, context) {
        cli::cli_alert_info("Writing to: {tool_input$path}")
        HookResultPreToolUse(permission = "allow")
      }
    ))

------------------------------------------------------------------------

### `Agent$turns()`

Get the whole conversation, including turns removed by compaction. The
same as `$get_turns()`.

#### Usage

    Agent$turns()

#### Returns

A list of ellmer turns.

------------------------------------------------------------------------

### `Agent$last_turn()`

Get the last turn in the conversation with a given role.

#### Usage

    Agent$last_turn(role = c("assistant", "user", "system"))

#### Arguments

- `role`:

  `"assistant"`, `"user"` or `"system"`.

#### Returns

An ellmer turn, or `NULL`.

------------------------------------------------------------------------

### `Agent$session_id()`

Get the agent's session ID.

#### Usage

    Agent$session_id()

#### Returns

A string.

------------------------------------------------------------------------

### `Agent$get_permission_mode()`

Get the current permission mode.

#### Usage

    Agent$get_permission_mode()

#### Returns

The mode, such as `"standard"`.

------------------------------------------------------------------------

### `Agent$set_permission_mode()`

Switch to a narrower permission mode for later tool calls. Permissions
can be narrowed but not widened: from `"full"` any mode is allowed, and
`"standard"` and `"plan"` can only switch to `"readonly"`. Anything else
is an error, so create a new `Agent` instead. Setting the current mode
does nothing. The agent's other permission settings still apply within
the new mode. If the new mode doesn't allow web access, provider-native
web tools are removed, since Deputy can't check their calls.

#### Usage

    Agent$set_permission_mode(mode)

#### Arguments

- `mode`:

  Permission mode, see
  [PermissionMode](https://jameshwade.github.io/deputy/reference/PermissionMode.md).

#### Returns

The agent, invisibly.

------------------------------------------------------------------------

### `Agent$cost()`

Get token counts and estimated cost for the whole conversation,
including turns that compaction removed from the model's context. The
requests that wrote compaction summaries aren't conversation turns, so
they aren't included; see `$last_compaction()`.

#### Usage

    Agent$cost()

#### Returns

A list with `input`, `output` and `cached` token counts, the estimated
`total` cost, `complete` (whether every response had a cost) and
`missing` (how many didn't). `total` is `NA` when `complete` is `FALSE`.

------------------------------------------------------------------------

### `Agent$usage()`

Get usage for the whole conversation, including turns that compaction
removed from the model's context. `tool_calls` counts the tool calls the
model asked for. Compaction summary requests aren't included; see
`$last_compaction()`. For one run's usage, use `$usage` on its
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
or the `"usage"` event from `$run()`.

#### Usage

    Agent$usage()

#### Returns

An
[AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
object.

------------------------------------------------------------------------

### `Agent$interrupt()`

Stop the current run, and any subagent runs it started.

The run stops as soon as ellmer allows, usually during the current model
request or before the next tool call. An
[McpConnection](https://jameshwade.github.io/deputy/reference/McpConnection.md)
call in progress is stopped by closing its connection, which loses the
server's session state.

#### Usage

    Agent$interrupt(reason = "interrupted")

#### Arguments

- `reason`:

  Stop reason recorded on the run's `"stop"` event and result.

#### Returns

`TRUE`, invisibly, if anything was running.

------------------------------------------------------------------------

### `Agent$provider()`

Get the provider and model names.

#### Usage

    Agent$provider()

#### Returns

A list with `name` and `model`.

------------------------------------------------------------------------

### `Agent$save_session()`

Save the conversation to an `.rds` file that `$load_session()` can
restore.

#### Usage

    Agent$save_session(path)

#### Arguments

- `path`:

  File path.

#### Details

The file holds the conversation (including turns removed by compaction),
the system prompt and any compaction summary, copies of large tool
results, the run context, file checkpoint state (when enabled) and some
metadata, such as the time, Deputy version and provider. It doesn't hold
tools, permissions, hooks or the Chat itself.

#### Returns

The path, invisibly.

------------------------------------------------------------------------

### `Agent$load_session()`

Load a conversation saved by `$save_session()`.

#### Usage

    Agent$load_session(path)

#### Arguments

- `path`:

  Path to the session file.

#### Details

Tools, permissions, hooks and the working directory come from the agent
you load into, not from the file. The saved `run_context` is merged into
the agent's, and loading fails if they disagree on an ID field. Saved
tool results and compaction summaries are restored under this agent's
session ID. Files saved by early development versions of Deputy can't be
loaded. Loading errors while a run is active.

#### Returns

The agent, invisibly.

------------------------------------------------------------------------

### `Agent$pending_approval()`

Get the tool approval this agent is waiting on.

#### Usage

    Agent$pending_approval()

#### Returns

An
[ApprovalContinuation](https://jameshwade.github.io/deputy/reference/ApprovalContinuation.md),
or `NULL` if nothing is waiting. Its `source$path` is the path to pass
to `$resume_approval()`.

------------------------------------------------------------------------

### `Agent$resume_approval()`

Approve or deny a tool call that is waiting for approval, then continue
the run. Both the saved permissions and the agent's current permissions
apply. After restarting R, first create an agent with the same
`session_id`, `agent_id`, `working_dir` and `approval_dir`, the same
tool definition (with `convert = FALSE`) and the permission callback.
Tool calls that already ran are not run again, and each approval can be
decided only once.

#### Usage

    Agent$resume_approval(
      path,
      decision = c("approve", "deny"),
      tool_input = NULL,
      usage_limits = NULL
    )

#### Arguments

- `path`:

  The approval's directory, from the `"approval"` event or
  `$pending_approval()`.

- `decision`:

  `"approve"` or `"deny"`.

- `tool_input`:

  Optional named list of edited tool arguments to use instead of the
  original ones. Only allowed with `"approve"`.

- `usage_limits`:

  Optional
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for the resumed run. They can't exceed the agent's limits at the time
  of suspension or now, and usage from before the suspension still
  counts. `NULL` keeps the suspended run's limits.

#### Returns

An
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).
Its usage includes the work done before the suspension.

------------------------------------------------------------------------

### `Agent$checkpoint()`

Create a file checkpoint that `$rewind_files()` can restore. Needs
`enable_file_checkpointing = TRUE`.

#### Usage

    Agent$checkpoint(name = NULL, metadata = list())

#### Arguments

- `name`:

  Optional label.

- `metadata`:

  Optional list of metadata to store with it.

#### Returns

The checkpoint ID.

------------------------------------------------------------------------

### `Agent$list_checkpoints()`

List file checkpoints.

#### Usage

    Agent$list_checkpoints()

#### Returns

A data frame, oldest first.

------------------------------------------------------------------------

### `Agent$rewind_files()`

Restore files to how they were at a checkpoint. Later checkpoints are
discarded. The conversation doesn't change. Errors during a run.

#### Usage

    Agent$rewind_files(checkpoint_id)

#### Arguments

- `checkpoint_id`:

  A checkpoint ID from `$checkpoint()`, `$list_checkpoints()` or a
  `"file_checkpoint"` event.

#### Returns

A list describing the checkpoint, including `restored_changes`, the
number of file changes undone.

------------------------------------------------------------------------

### `Agent$compact()`

Replace older turns in the model context with a summary, so later
requests are smaller. The removed turns stay available from
`$get_turns()`. Errors during a run; runs compact automatically as set
by the
[ContextPolicy](https://jameshwade.github.io/deputy/reference/ContextPolicy.md).

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

  Number of recent turns to keep. `NULL` keeps as many recent turns as
  fit in `max_tokens * compact_to` of the context policy, starting at a
  user turn, or the last 4 turns if `max_tokens` is `NULL`.

- `summary`:

  Optional summary to use. If `NULL`, a `PreCompact` hook can supply
  one; otherwise the model writes one covering decisions, findings,
  files, errors and progress.

- `fallback`:

  `"error"` or `"text"`: what to do if the model can't write the
  summary. Defaults to the context policy's `fallback`.

- `automatic`:

  Set by the agent when a run compacts automatically. Leave it as
  `FALSE`.

- `estimated_tokens`:

  Optional token estimate before compaction, recorded in the result.

#### Details

Compaction:

1.  Fires the `PreCompact` hook, which can cancel compaction or supply a
    summary.

2.  Asks the model to summarise the older turns, unless a summary was
    supplied.

3.  Appends the summary to the system prompt under "Previous
    Conversation Summary".

4.  Keeps only the last `keep_last` turns in the model context.

If the model can't write a summary, `$compact()` errors, unless
`fallback = "text"`, which builds a plain summary from the first 200
characters of each turn instead. The result's `method` shows which was
used.

#### Returns

A
[DeputyCompaction](https://jameshwade.github.io/deputy/reference/DeputyCompaction.md)
describing what happened.

------------------------------------------------------------------------

### `Agent$microcompact()`

Clear old tool results from the model's context, as Posit Assistant's
`/microcompact` does.

Every tool result before the last `keep_last` turns has its value
replaced by `marker` in the model's context, unless its tool is named in
`keep_tools`. Nothing is summarised and no model call is made. Any
earlier compaction summary is kept. Errors during a run.

Like compaction, this changes only what the model sees. `$get_turns()`,
`$last_turn()` and saved sessions keep the original results, so your
app's conversation history is unchanged. `$get_context_turns()` shows
the markers.

#### Usage

    Agent$microcompact(
      keep_last = 2L,
      keep_tools = character(),
      marker = "[Old tool result cleared to save context.]"
    )

#### Arguments

- `keep_last`:

  Number of recent turns whose tool results are left as they are. `Inf`
  keeps every turn.

- `keep_tools`:

  Names of tools whose results are never cleared.

- `marker`:

  The text that replaces a cleared result.

#### Returns

A list with `cleared`, the number of tool results replaced.

------------------------------------------------------------------------

### `Agent$print()`

Print a summary of the agent.

#### Usage

    Agent$print()

------------------------------------------------------------------------

### `Agent$load_skill()`

Load a [Skill](https://jameshwade.github.io/deputy/reference/Skill.md):
register its tools and append its prompt to the system prompt. Warns if
packages the skill needs are missing or it expects a different provider.

#### Usage

    Agent$load_skill(skill, allow_conflicts = FALSE)

#### Arguments

- `skill`:

  A [Skill](https://jameshwade.github.io/deputy/reference/Skill.md)
  object or path to a skill directory.

- `allow_conflicts`:

  If `TRUE`, the skill's tools replace registered tools with the same
  names, with a warning. If `FALSE` (the default), a name clash is an
  error.

#### Returns

The agent, invisibly, for chaining.

------------------------------------------------------------------------

### `Agent$skills()`

Get the loaded skills.

#### Usage

    Agent$skills()

#### Returns

Named list of
[Skill](https://jameshwade.github.io/deputy/reference/Skill.md) objects.

------------------------------------------------------------------------

### `Agent$load_mcp()`

Load tools from the MCP (Model Context Protocol) servers in an mcptools
configuration file.

Needs the mcptools package. If it isn't installed or the tools can't be
fetched, this warns and loads nothing; `$mcp_status()` records each
attempt. If a reload fails, tools whose connections were closed are
removed and the rest stay.

#### Usage

    Agent$load_mcp(config = NULL, servers = NULL, replace = FALSE)

#### Arguments

- `config`:

  Path to the configuration file. `NULL` uses the mcptools default,
  `~/.config/mcptools/config.json`.

- `servers`:

  Names of the servers to load from. `NULL` loads from all of them.

- `replace`:

  If `TRUE`, replace the tools loaded earlier from these servers,
  dropping any a server no longer offers, and replace any other tools
  with the same names. If `FALSE`, a name clash is an error.

#### Returns

The agent, invisibly, for chaining.

------------------------------------------------------------------------

### `Agent$mcp_tools()`

Get the names of loaded MCP tools.

#### Usage

    Agent$mcp_tools()

#### Returns

A character vector.

------------------------------------------------------------------------

### `Agent$mcp_status()`

Get a log of `$load_mcp()` calls.

#### Usage

    Agent$mcp_status()

#### Returns

A data frame with one row per call: `status` (`"connected"`, `"empty"`,
`"failed"` or `"unavailable"`), `config`, `servers`, `tools`,
`loaded_at` and `error`.

------------------------------------------------------------------------

### `Agent$run_async()`

Run a task asynchronously. Works like `$run_sync()` but returns a
promise, so you can use it from async code, such as a Shiny app or a
tool that runs another agent while its own chat is streaming.

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

  The task for the agent.

- `usage_limits`:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for this run. `NULL` fields use the agent's limits.

- `run_context`:

  Named list merged into the agent's `run_context` for this run. It
  can't change or remove ID fields (keys ending in `id`) that the agent
  already sets.

- `type`:

  Optional ellmer type, such as
  [`ellmer::type_object()`](https://ellmer.tidyverse.org/reference/type_boolean.html).
  After the task, the agent extracts data of this type from the
  conversation into `result$structured_output`. This counts toward the
  run's limits.

- `validate`:

  Optional function that checks the extracted value. Return `TRUE` to
  accept it, or `FALSE` or a message to reject it; a message is sent to
  the model as feedback. An error or any other return value, such as
  `NA`, ends the run with an error.

- `max_corrections`:

  How many times to ask the model to fix a rejected value. Defaults
  to 0. If the value is still rejected, the run errors. Every attempt
  counts toward the run's limits.

#### Returns

A promise that resolves to an
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).
It is rejected if the provider request fails or a limit with
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
  chat = ellmer::chat("openai/gpt-6-luna"),
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
agent$add_hook(HookMatcher(
  event = "PreToolUse",
  pattern = "^write_file$",
  callback = function(tool_name, tool_input, context) {
    cli::cli_alert_info("Writing to: {tool_input$path}")
    HookResultPreToolUse(permission = "allow")
  }
))
} # }
```
