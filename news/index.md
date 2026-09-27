# Changelog

## deputy (development version)

- A `can_use_tool` permission callback can no longer allow a call that
  the rest of the policy denies. In standard mode its allow used to skip
  the capability checks, so a callback that allowed everything it didn’t
  block let the model run R code with `r_code = FALSE` or write outside
  the `file_write` directory. Plan and full modes ignored the callback.
  It is now called in every mode, for each call the policy allows, and
  can deny the call or pause it for approval. To allow a call the policy
  denies, use a `PermissionRequest` hook.

- Read-only and plan policies now allow an agent’s own delegation tools:
  a `LeadAgent`’s `delegate_to_agent`, and the
  [`delegation_tool()`](https://jameshwade.github.io/deputy/reference/delegation_tool.md)
  and `retain_agent_graph()` route tools that call its retained agents.
  An agent created with
  [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md)
  or
  [`permissions_plan()`](https://jameshwade.github.io/deputy/reference/permissions_plan.md)
  can therefore delegate, and each tool call its subagents and retained
  agents make is still checked against its policy, so they can’t write
  or run code either. A custom tool doesn’t qualify by using one of
  these names
  ([\#227](https://github.com/JamesHWade/deputy/issues/227)).

- [`hook_log_tools()`](https://jameshwade.github.io/deputy/reference/hook_log_tools.md),
  [`hook_block_dangerous_bash()`](https://jameshwade.github.io/deputy/reference/hook_block_dangerous_bash.md)
  and
  [`hook_limit_file_writes()`](https://jameshwade.github.io/deputy/reference/hook_limit_file_writes.md)
  now return `NULL` when they don’t deny a call, so hooks added after
  them for the same event still run.

- `Agent$usage()` and `Agent$cost()` now include turns that compaction
  removed from the model’s context, and `Agent$usage()$tool_calls`
  counts the tool calls the model asked for instead of always being 0.

- The command-line app now reports how many model requests a run made,
  instead of “NA turn(s)”.

- `edit_file` and `multi_edit` now change only the text they replace,
  instead of rewriting the file, which converted CRLF to LF and added a
  final newline. Non-UTF-8 bytes are kept too. Search text written with
  `"\n"` still matches CRLF and mixed files, and new lines take the
  ending of the line they replace
  ([\#217](https://github.com/JamesHWade/deputy/issues/217)).

- `run_bash` now treats a non-zero exit status, including “command not
  found”, as an error and tells the model the status. Standard error is
  returned after a `[stderr]` line instead of being discarded
  ([\#215](https://github.com/JamesHWade/deputy/issues/215)).

- [`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)
  handlers can now answer without blocking, for apps such as Shiny. A
  handler may return a promise for the answers, or
  [`AskUserDeferred()`](https://jameshwade.github.io/deputy/reference/AskUserDeferred.md)
  to show the questions and have the model end its turn so the answers
  arrive as the user’s next message. `AskUserDeferred(extra = )`
  attaches display data to the tool result. Subagents accept promises
  but not deferral
  ([\#215](https://github.com/JamesHWade/deputy/issues/215)).

- New `Agent$microcompact()` replaces old tool results in the model’s
  context with a short marker, like Posit Assistant’s `/microcompact`.
  Results in the last `keep_last` turns, or from tools in `keep_tools`,
  are kept. It makes no model call, keeps any earlier compaction
  summary, and leaves the original results in `$get_turns()`,
  `$last_turn()` and saved sessions
  ([\#209](https://github.com/JamesHWade/deputy/issues/209)).

- `agent_definition(model = )` can now be a bare model id such as
  `"gpt-6-luna"`, which runs the subagent with that model on the lead’s
  provider, endpoint and credentials, including gateway clients built
  outside ellmer. `"inherit"` and `"provider/model"` work as before; ids
  containing `/` still need the `"provider/model"` form
  ([\#210](https://github.com/JamesHWade/deputy/issues/210)).

- New
  [`TrustedResults()`](https://jameshwade.github.io/deputy/reference/TrustedResults.md)
  supports the trusted mini-agent pattern from Will Landau and Sam
  Parmar’s [*Trusted Mini-Agents*](https://trustedminiagents.dev): pass
  it to `Agent$new(trusted_results = )` to name the one local tool that
  may produce each kind of result. That tool’s return value reaches your
  app unchanged, as a `"trusted_result"` event (see
  [`result_trusted_results()`](https://jameshwade.github.io/deputy/reference/result_trusted_results.md))
  and through an optional `on_result` callback, before the model sees
  it; with `model_receipt = TRUE` the model gets only a receipt.
  Registration fails if another tool could produce results: code
  execution and delegation tools always, and tools that may write or
  reach the open world unless listed in `exempt_tools`
  ([\#197](https://github.com/JamesHWade/deputy/issues/197)).

- Permission callbacks and `PreToolUse` hooks now get the tool’s
  argument types in `context$tool_arguments`. New
  [`tool_input_review()`](https://jameshwade.github.io/deputy/reference/tool_input_review.md)
  turns a proposed tool input into a table of each field’s type,
  description and value
  ([\#197](https://github.com/JamesHWade/deputy/issues/197)).

- `LeadAgent$new(trusted_results = )` applies the policy to all
  subagents: each definition’s tools must pass the same check, a
  designated tool must be the same tool everywhere, and subagents’
  trusted results reach the lead’s `on_result` and run events
  ([\#197](https://github.com/JamesHWade/deputy/issues/197)).

- New
  [`approval_review_ui()`](https://jameshwade.github.io/deputy/reference/approval_review_ui.md)
  and
  [`approval_review_server()`](https://jameshwade.github.io/deputy/reference/approval_review_ui.md)
  are a Shiny module for reviewing a pending durable approval. They show
  each argument’s type, description and value, let the reviewer edit
  simple fields, and approve or deny. Pass `decide` to carry out the
  decision elsewhere, such as in a background process
  ([\#197](https://github.com/JamesHWade/deputy/issues/197)).

- New `inst/examples/trusted-results/` app, adapted from Landau and
  Parmar’s R template and weather example, shows chat, input review and
  results side by side. Only the forecast tool can fill the results
  panel ([\#197](https://github.com/JamesHWade/deputy/issues/197)).

- New
  [`vignette("trusted-mini-agents")`](https://jameshwade.github.io/deputy/articles/trusted-mini-agents.md)
  explains Landau and Parmar’s trusted mini-agent pattern and how Deputy
  enforces each of its rules
  ([\#197](https://github.com/JamesHWade/deputy/issues/197)).

- New
  [`mcp_console_connection()`](https://jameshwade.github.io/deputy/reference/mcp_console_connection.md)
  connects an agent to an [MCP
  Console](https://github.com/t-kalinowski/mcp-console) 0.0.4 server, a
  sandboxed workbench that keeps R, Python and DuckDB SQL state for a
  conversation, and
  [`mcp_console_control()`](https://jameshwade.github.io/deputy/reference/mcp_console_control.md)
  interrupts or restarts it
  ([\#190](https://github.com/JamesHWade/deputy/issues/190)). Deputy
  refuses `--no-sandbox`, options that widen file access, add a proxy or
  select a remote target, and an unreviewed
  `.agents/console/config.yaml`, and closes the connection unless the
  server reports its sandbox with restricted networking. `send` counts
  as shell code execution and needs the `bash` and `web` permissions;
  installing dependencies runs outside the sandbox and also needs
  `dependencies = "allow"` and `install_packages = TRUE`. `timeout_ms`
  is capped at 2500 ms, so long cells return a running marker and the
  model polls. MCP Console records every call and result, unredacted,
  under `.agents/console/sessions/` in the agent’s working directory.

- Deputy temporarily requires coro \>= 1.1.0.9000 from GitHub: CRAN coro
  1.1.0 recompiles every generator, costing 0.3 to 0.7 seconds of CPU
  per model request. Deputy will return to CRAN coro once the fix is
  released ([\#192](https://github.com/JamesHWade/deputy/issues/192)).

- `McpConnection` now checks the JSON-RPC id of every MCP stdio reply.
  The supported mcptools releases wait about 4 seconds for a reply, then
  take the next output line without checking its id, so a slow reply
  could become the answer to the next call. A missing or mismatched
  reply now stops the server, losing its session state, and signals a
  `deputy_mcp_desynchronized` error;
  [`tools_mcp()`](https://jameshwade.github.io/deputy/reference/tools_mcp.md)
  tools, which can’t see reply ids, stop the server on the first lost
  reply.
  [`mcp_repl_connection()`](https://jameshwade.github.io/deputy/reference/mcp_repl_connection.md)
  and
  [`tools_mcp_repl()`](https://jameshwade.github.io/deputy/reference/tools_mcp_repl.md)
  cap mcp-repl’s `timeout_ms` at 3000 ms, also when it is omitted, so
  long cells return a busy result and the model polls
  ([\#196](https://github.com/JamesHWade/deputy/issues/196)).

- `McpConnection`,
  [`tools_mcp()`](https://jameshwade.github.io/deputy/reference/tools_mcp.md)
  and
  [`mcp_repl_connection()`](https://jameshwade.github.io/deputy/reference/mcp_repl_connection.md)
  now support CRAN mcptools 1.0.3 as well as 1.0.2. Other versions are
  refused with an error that lists the supported ones
  ([\#195](https://github.com/JamesHWade/deputy/issues/195)).

- Model requests and tool calls use less CPU
  ([\#185](https://github.com/JamesHWade/deputy/issues/185)).

- New
  [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md),
  [`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md),
  [`job_read()`](https://jameshwade.github.io/deputy/reference/job_read.md)
  and
  [`job_cancel()`](https://jameshwade.github.io/deputy/reference/job_cancel.md)
  save an agent task to disk for your own scheduler to run later, in any
  R process. A job keeps the definition and context revisions you
  supply, its budgets, completed tool effects and any pending approval.
  A job interrupted mid-run is marked indeterminate instead of retried,
  so side effects aren’t repeated;
  [`job_cancel()`](https://jameshwade.github.io/deputy/reference/job_cancel.md)
  asks a running job to stop at its next checkpoint
  ([\#42](https://github.com/JamesHWade/deputy/issues/42)).

- New
  [`ContextFork()`](https://jameshwade.github.io/deputy/reference/ContextFork.md)
  and
  [`fork_agent()`](https://jameshwade.github.io/deputy/reference/fork_agent.md)
  start a retained specialist from a copy of turns you select from
  another conversation, either its transcript or its current model
  context. Each continuation rechecks that the source may still be read.
  The copy is inert: tool bindings and private provider data are
  dropped, and current permissions apply
  ([\#62](https://github.com/JamesHWade/deputy/issues/62)).

- Subagent inspection and observation now keep `difftime` values, their
  units and missing values, including in data-frame columns. The
  subagent chat panel shows content nested in tool results, labels where
  it came from, notes anything left out, and keeps the original for
  replay ([\#166](https://github.com/JamesHWade/deputy/issues/166),
  [\#167](https://github.com/JamesHWade/deputy/issues/167)).

- New `Agent$retain_agent_graph()` sets up retained specialists that
  delegate to each other along routes you declare. The graph shares one
  lifetime budget with limits on depth, delegations and concurrency;
  cancelling a run cancels everything beneath it; and the root controls
  who may view each specialist’s conversation. See
  `inst/examples/recursive-agents/`
  ([\#169](https://github.com/JamesHWade/deputy/issues/169)).

- New
  [`adopt_chat()`](https://jameshwade.github.io/deputy/reference/adopt_chat.md)
  turns a configured ellmer chat into a retained specialist, copying its
  provider, system prompt, tools and optionally its history, and
  replacing its callbacks so the owning agent’s permissions and hooks
  apply.
  [`delegation_tool()`](https://jameshwade.github.io/deputy/reference/delegation_tool.md)
  gives the owning agent a tool for sending it tasks
  ([\#168](https://github.com/JamesHWade/deputy/issues/168)).

- New `Agent$retain_agent()` keeps a specialist agent and its
  conversation for repeated use: continue it with `$continue_agent()` or
  `$continue_agent_async()`, stop it with `$cancel_agent()` and free it
  with `$release_agent()`. Its budget is cumulative, the handle works
  only with the agent that retained it, and continuing it while it runs
  is an error. Plain `Agent`s now have the subagent inspection and
  observation methods too
  ([\#152](https://github.com/JamesHWade/deputy/issues/152)).

- New `inst/examples/trusted-mini-agent/` app: a subagent proposes
  inputs for a small plant-weight analysis, a person reviews them, and
  only a designated R tool produces the result
  ([\#154](https://github.com/JamesHWade/deputy/issues/154)).

- New
  [`subagent_chat_ui()`](https://jameshwade.github.io/deputy/reference/subagent_chat_ui.md)
  and
  [`subagent_chat_server()`](https://jameshwade.github.io/deputy/reference/subagent_chat_ui.md)
  add a read-only Shiny panel showing each subagent’s live activity and
  conversation, with shinychat tool cards and attachments. It can replay
  saved history and shows a cancel button if you supply `on_cancel`. See
  `inst/examples/subagent-chats/`
  ([\#158](https://github.com/JamesHWade/deputy/issues/158)).

- New `LeadAgent$observe_subagents()` returns a subscription for
  following subagent activity: a snapshot, then new events each time you
  poll, with access checked on every read. Events dropped from the
  limited buffer, or too large to keep, are reported as gaps. Closing a
  subscription doesn’t stop anything; `$interrupt_subagent()` cancels a
  subagent ([\#157](https://github.com/JamesHWade/deputy/issues/157)).

- Delegation now returns a `DelegationOutcome`, keeping the subagent’s
  reply separate from its history.
  [`DelegationDisclosure()`](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  decides who may inspect subagents with `$inspect_subagents()`,
  `$read_subagent_result()` and `$export_subagents()`, which return
  redacted views.
  [`delegation_history()`](https://jameshwade.github.io/deputy/reference/delegation_history.md)
  replays exported history without running tools or changing the lead’s
  context. Long replies are offloaded like large tool results
  ([\#153](https://github.com/JamesHWade/deputy/issues/153)).

- New
  [`DelegationPolicy()`](https://jameshwade.github.io/deputy/reference/DelegationPolicy.md)
  controls subagents’ tools and human input. Tools can be shared, held
  exclusively (overlapping use is an error), or built per delegation by
  a factory returning
  [`DelegationResources()`](https://jameshwade.github.io/deputy/reference/DelegationResources.md),
  which are cleaned up when the subagent finishes or fails to start. A
  subagent using `ask_user` needs a handler from the policy, and durable
  approvals in subagents are an error for now. Each delegation’s
  manifest records the policy
  ([\#151](https://github.com/JamesHWade/deputy/issues/151)).

- New
  [`DelegationInput()`](https://jameshwade.github.io/deputy/reference/DelegationInput.md)
  describes a delegated task as a brief (task, constraints, evidence,
  deliverable and stop conditions); plain strings still work. Evidence
  names exact revisions of records passed to
  `LeadAgent$new(delegation_sources = )` and is checked before any
  request; each delegation’s `DelegationManifest` records what the
  subagent received, and text in a brief can’t pose as the evidence
  list. Directly invoked subagents now stop when the lead is
  interrupted, parallel delegation enforces the lead’s token limit, and
  a malformed brief no longer loses the other tasks in a batch
  ([\#149](https://github.com/JamesHWade/deputy/issues/149)).

- `LeadAgent$list_subagents()` now lists queued and running delegations
  in the order they were accepted, with exact stop reasons and any hook
  error; stopped runs no longer appear completed. Interrupting the lead
  interrupts its running subagents, and queued parallel tasks stay
  listed after cancellation
  ([\#150](https://github.com/JamesHWade/deputy/issues/150)).

- `Agent$chat()`, `$stream()` and their async versions accept dynamic
  dots (`!!!`), so shinychat can pass its input straight through. The
  Shiny chat example now shows compaction progress and the summary.

- `Agent$get_turns()` and `Agent$turns()` now return the whole
  conversation after compaction, so shinychat history keeps every reply;
  new `Agent$get_context_turns()` returns what the model receives. Saved
  sessions (schema 3) store both, and sessions saved with earlier
  development schemas can’t be loaded
  ([\#146](https://github.com/JamesHWade/deputy/issues/146)).

- `RSession$new(agent, tools = )` lets model-written R code call
  selected registered tools as `tools$name(...)`, through the agent’s
  permissions, hooks and limits, and keep the results as R data. The
  tools must use `convert = FALSE` and can’t pause for durable approval
  ([\#186](https://github.com/JamesHWade/deputy/issues/186)).

- New `RSession` gives a conversation a persistent R process for
  `run_r_code`: variables persist between calls, output and plots come
  back in order, and calls queue. `$cancel()` or a timeout discards the
  variables, and the next call says so. The code runs with your
  account’s access and is not sandboxed. New
  [`ContextPolicy()`](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  arguments `max_tool_result_images` and `max_tool_result_image_bytes`
  limit images in tool results separately from text; the full result
  stays available for display
  ([\#143](https://github.com/JamesHWade/deputy/issues/143)).

- New
  [`mcp_repl_connection()`](https://jameshwade.github.io/deputy/reference/mcp_repl_connection.md)
  gives an agent its own sandboxed mcp-repl session;
  [`mcp_repl_control()`](https://jameshwade.github.io/deputy/reference/mcp_repl_control.md)
  interrupts or resets it and reports the outcome. Interrupting the
  agent cancels its active MCP connections. Plots and output previews
  come back as ellmer content
  ([\#69](https://github.com/JamesHWade/deputy/issues/69)).

- New `McpConnection` connects one agent to an MCP server through a
  client in a separate R process. You can page through the server’s
  tools, resources and prompts, and must allow each one before use.
  Calls return promises; after a cancellation, timeout or
  [`close()`](https://rdrr.io/r/base/connections.html) the connection’s
  tools stop working. It supports mcptools 1.0.2 and is a stopgap until
  mcptools has a public client API
  ([\#48](https://github.com/JamesHWade/deputy/issues/48),
  [\#99](https://github.com/JamesHWade/deputy/issues/99)).

- New durable approvals: in an agent with an `approval_dir`, a
  permission callback can return
  [`PermissionResultPending()`](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md)
  to pause a tool call and save it to disk for a person to decide later,
  even in another R process.
  [`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md)
  shows the pending call, and `Agent$resume_approval()` approves it
  (optionally with edited input or a higher budget) or denies it,
  checking both the saved and the current permissions. The tool must use
  `convert = FALSE`. Completed tool effects are logged, a call
  interrupted mid-run can’t be resumed and must be checked by hand, and
  your app tracks which conversation each approval belongs to
  ([\#43](https://github.com/JamesHWade/deputy/issues/43)).

- Hook and permission result constructors, such as
  [`HookResultPreToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPreToolUse.md)
  and
  [`PermissionResultAllow()`](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md),
  now return read-only S7 objects. Check their class with
  [`S7::S7_inherits()`](https://rconsortium.github.io/S7/reference/S7_inherits.html)
  (for example against `HookResult` or `PermissionResult`) and use
  [`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
  for a plain list. `continue` and `interrupt` must be a single `TRUE`
  or `FALSE`, and text fields must be strings; `suppress_output` is
  still coerced with [`isTRUE()`](https://rdrr.io/r/base/Logic.html)
  ([\#129](https://github.com/JamesHWade/deputy/issues/129)).

- [`Skill()`](https://jameshwade.github.io/deputy/reference/Skill.md)
  now returns a read-only S7 object. `skill$check_requirements()` is
  replaced by `skill_check_requirements(skill)`; to change a skill,
  build a new one from `S7::props(skill)`.
  [`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md)
  and
  [`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md)
  are unchanged
  ([\#127](https://github.com/JamesHWade/deputy/issues/127)).

- [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  and
  [`AgentDefinition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  are now the same constructor and return a read-only S7 object; build a
  changed definition from
  [`S7::props()`](https://rconsortium.github.io/S7/reference/props.html).
  Names, YAML files and delegated limits work as before
  ([\#125](https://github.com/JamesHWade/deputy/issues/125)).

- [`AgentUsage()`](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  and
  [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  now return read-only S7 objects. `$` still reads fields; use
  [`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
  instead of `[[` or [`unclass()`](https://rdrr.io/r/base/class.html)
  for a plain list
  ([\#121](https://github.com/JamesHWade/deputy/issues/121)).

- [`AgentResult()`](https://jameshwade.github.io/deputy/reference/AgentResult.md)
  and
  [`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md)
  now return read-only S7 objects, and their `$new()` and methods are
  removed. Inspect results with
  [`result_n_turns()`](https://jameshwade.github.io/deputy/reference/result_n_turns.md),
  [`result_tool_calls()`](https://jameshwade.github.io/deputy/reference/result_tool_calls.md),
  [`result_tool_results()`](https://jameshwade.github.io/deputy/reference/result_tool_results.md),
  [`result_text_chunks()`](https://jameshwade.github.io/deputy/reference/result_text_chunks.md)
  and
  [`result_is_success()`](https://jameshwade.github.io/deputy/reference/result_is_success.md),
  and test a policy with
  [`permissions_check()`](https://jameshwade.github.io/deputy/reference/permissions_check.md).
  `$` still reads fields.
  [`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md)
  now rejects malformed flags and callbacks
  ([\#117](https://github.com/JamesHWade/deputy/issues/117)).

- [`AgentEvent()`](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
  and
  [`HookMatcher()`](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
  now return read-only S7 objects. Create matchers with
  `HookMatcher(...)` instead of `HookMatcher$new()`, and test a tool
  name with
  [`hook_matches()`](https://jameshwade.github.io/deputy/reference/hook_matches.md).
  Check an event’s type with `event$type` instead of its S3 class;
  `event$data` holds the payload, and `$` still reads its fields
  directly ([\#59](https://github.com/JamesHWade/deputy/issues/59)).

- [`ContextPolicy()`](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  and
  [`DeputyCompaction()`](https://jameshwade.github.io/deputy/reference/DeputyCompaction.md)
  now return read-only S7 objects. Read fields with `$`, or use
  [`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
  for a plain list
  ([\#123](https://github.com/JamesHWade/deputy/issues/123)).

- [`print()`](https://rdrr.io/r/base/print.html) methods now format with
  cli, wrap to the console width, show braces in your values literally,
  and write to stdout so
  [`capture.output()`](https://rdrr.io/r/utils/capture.output.html)
  works ([\#58](https://github.com/JamesHWade/deputy/issues/58)).

- Compaction summaries now include tool results, formatted by ellmer so
  structured results keep their field names. Previously a source
  returned by a tool could be missing from the summarizer’s input.

- New `inst/examples/history-recovery/` experiment tests whether a
  compacted agent answers better when it can also search and read the
  earlier conversation, including after a later instruction replaces an
  earlier rule
  ([\#112](https://github.com/JamesHWade/deputy/issues/112)).

- Automatic compaction now runs within the current run: it shares the
  run’s usage limits, stops when the run is interrupted, and can happen
  between tool rounds without losing completed tool calls or usage. New
  `ContextPolicy(summary_fallback_chats = )` lists chats to try in order
  when the summary request fails with a transient error, separately from
  the agent’s `fallback_chats`. A failed or interrupted compaction
  leaves the context unchanged, an accepted summary survives a later
  task fallback, and each summary attempt is recorded
  ([\#111](https://github.com/JamesHWade/deputy/issues/111)).

- Deputy now requires ellmer 0.5.0 or later.

- Structured output now uses ellmer types. Pass `type` to `$run()`,
  `$run_sync()` or `$run_async()` and the agent finishes its tool calls,
  then returns structured data within the same budget. An optional
  `validate` function can ask for up to `max_corrections` corrections,
  and each attempt is recorded. The `output_format` argument, its JSON
  parsing and validation helpers, and the jsonvalidate dependency are
  removed.

- `Agent$new()` and `LeadAgent$new()` accept `fallback_chats`, tried in
  order when a request fails with a transient error before any response
  or tool request. A request isn’t retried once output has arrived or a
  tool has run. Failed requests still count toward usage, and unknown
  costs stay unknown.

- With otel installed and a tracer configured, each run gets a
  `deputy.run` span around ellmer’s spans, including for async runs and
  subagents, with events for permission decisions, hooks, compaction,
  fallbacks and delegation. These spans contain no prompts, tool
  arguments or results; ellmer’s message capture stays opt-in. The
  standalone `10-evaluation.R` example joins evaluation cases to run
  IDs.

- After a run stops with a limit error, `Agent$last_run()` still returns
  its result.

- The `deputy` command-line tool now defaults to OpenAI’s
  `gpt-5.6-luna`. Models you choose, other providers’ defaults and chats
  you supply are unchanged
  ([\#106](https://github.com/JamesHWade/deputy/issues/106)).

- New standalone example `09-debate.R`: two subagents argue for and
  against a question in parallel, and a moderator weighs their arguments
  with the bundled `debate` skill. If either side fails, the script
  stops before the moderator
  ([\#40](https://github.com/JamesHWade/deputy/issues/40)).

- New `LeadAgent$parallel_delegate()` and `$parallel_delegate_async()`
  ask several tool-free subagents for one reply each, in parallel, at
  most `max_active` at a time. Results come back by name, including
  partial results when some fail. Each request is reserved from the
  lead’s budget in advance, failed requests count toward limits, and
  batches can be cancelled. Each subagent starts from a fresh chat
  without the lead’s history, tools or callbacks
  ([\#39](https://github.com/JamesHWade/deputy/issues/39)).

- New
  [`tool_metadata()`](https://jameshwade.github.io/deputy/reference/tool_metadata.md)
  reports each tool’s origin, declared and missing annotations, and the
  defaults used, including after cloning and delegation. MCP tools now
  keep the server’s annotations, connect only to the servers you name,
  and stop working after their connection reconnects. An MCP tool named
  like a built-in tool gets none of its privileges, and its path
  arguments are not rewritten. Subagents take their tools from their
  definition instead of inheriting the lead’s
  ([\#50](https://github.com/JamesHWade/deputy/issues/50)).

- Registering a tool whose name is taken is now an error unless you pass
  `replace = TRUE`; duplicate names within a batch are always an error.
  Each batch is checked in full before any tool is added, from
  `Agent$new()`, `$register_tools()`, `$set_tools()` or a skill. A
  custom tool without annotations is treated as possibly writing,
  destructive and reaching outside the workspace
  ([\#49](https://github.com/JamesHWade/deputy/issues/49)).

- New
  [`agent_definition_read()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md),
  [`agent_definition_write()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md)
  and
  [`agent_definitions()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md)
  read and write agent definitions as YAML files, by default in
  `.deputy/agents/`. Tools and skills are looked up by name in
  registries you supply; reading a file never runs code
  ([\#41](https://github.com/JamesHWade/deputy/issues/41)).

- A missing suggested package now triggers the standard install prompt,
  naming the feature that needs it. Loading a skill with YAML front
  matter now requires yaml instead of silently dropping the metadata
  ([\#57](https://github.com/JamesHWade/deputy/issues/57)).

- `Agent` can now stand in for an ellmer chat: `$chat()`,
  `$chat_async()`, `$stream()` and `$stream_async()` work like ellmer’s,
  and they, `$run_sync()` and `$run_async()` all apply the agent’s
  permissions, hooks, limits, checkpoints and usage tracking. shinychat
  can use `agent$stream_async()` directly, attachments included.
  `run_shiny()` and public access to the wrapped chat are removed, and
  `LeadAgent` delegation no longer blocks the R process.

- New
  [`ContextPolicy()`](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  compacts the conversation automatically before a request when it gets
  too long, reporting whether it used the model, a `PreCompact` hook or
  the text fallback, and its own usage. It also stores large tool
  results on disk behind a short reference the model can read in chunks;
  `PostToolUse` hooks still see the full result, and a relative
  `offload_dir` is resolved when the policy is created. Saved sessions
  keep the summary and offloaded results, and loading a session replaces
  the agent’s offloaded results so they can’t leak into later saves.
  `$set_turns()` clears the summary but keeps the rest of the system
  prompt, and `LeadAgent` passes the policy to its subagents.

- File and code tools now run in the agent’s `working_dir` without
  changing R’s working directory.

- Concurrent delegations from a `LeadAgent` now share its remaining
  usage limits instead of each receiving the full balance. A cloned
  `LeadAgent` now delegates with the clone’s own subagents, hooks and
  run history.

- The `deputy` command-line tool is now a Rapp 0.4 executable: run it
  once with `rx` or install a launcher with `ir tool install`. Its task
  and interactive modes now stream correctly, report tool failures and
  can resume saved sessions.

- `Agent$new()` and every run method accept `run_context`, a
  JSON-compatible list of your own identifiers, such as a user or
  conversation ID, which is attached to results, hook contexts, saved
  sessions and subagents. ID fields set when the agent was created can’t
  be changed per run. Tool events and subagent results also carry agent,
  run, parent, tool call and delegation IDs, and generating them no
  longer advances R’s random number generator.

- The public API is now smaller, centred on agents, tools, permissions,
  hooks, skills, delegation and usage. Removed: the pre-release Agent
  SDK and Claude compatibility functions, the Claude settings loader,
  automatic session stores, vendor tool and permission aliases,
  deprecated run arguments, the todo tools and redundant convenience
  exports. Each agent has a stable `session_id`, and conversations are
  saved and loaded only with `Agent$save_session()` and
  `Agent$load_session()`; sessions and file checkpoints from earlier
  versions can’t be loaded.

- `Agent$provider()` no longer fails with “Can’t get S7 properties with
  `$`” on current ellmer, which moved the model from `Provider` to a new
  `Model` class.

- `Agent$set_permission_mode()` can now only keep or narrow the
  permissions the agent was created with. Subagents follow the same rule
  and keep all the lead’s restrictions: capability flags, tool allow and
  deny lists, permission callback and write directory.

- [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  now validates its fields and lowercases names. `LeadAgent` rejects
  duplicate names, and `$sub_agent_defs` is a read-only copy: add
  definitions with `$register_sub_agent()` so delegation and the lead’s
  prompt stay in sync
  ([\#79](https://github.com/JamesHWade/deputy/issues/79)).

- `Agent` now rejects a tool request with a missing or malformed tool
  name before it reaches usage accounting, permissions, hooks or the
  tool ([\#26](https://github.com/JamesHWade/deputy/issues/26)).

- [`hook_limit_file_writes()`](https://jameshwade.github.io/deputy/reference/hook_limit_file_writes.md)
  now checks paths the same way permissions do, blocks escapes through
  symlinks and through paths that only share a prefix (`/data2` when
  `/data` is allowed), and covers every built-in file-writing tool
  ([\#75](https://github.com/JamesHWade/deputy/issues/75)).

- [`HookMatcher()`](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
  callbacks now run in your R process by default; a positive `timeout`
  runs them in a subprocess and reports their full error messages.
  [`HookMatcher()`](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
  also validates `timeout`, and rejects callbacks that can’t accept the
  event’s arguments and patterns that aren’t valid regular expressions
  ([\#35](https://github.com/JamesHWade/deputy/issues/35),
  [\#36](https://github.com/JamesHWade/deputy/issues/36),
  [\#74](https://github.com/JamesHWade/deputy/issues/74)).

- [`skill_check_requirements()`](https://jameshwade.github.io/deputy/reference/skill_check_requirements.md)
  now treats malformed or unknown provider names as not matching, while
  a skill and chat that name the same generic provider still match
  ([\#30](https://github.com/JamesHWade/deputy/issues/30)).

- `Agent$compact()` now summarizes with a copy of the agent’s own chat,
  with tools and callbacks removed. Previously, providers other than
  OpenAI, Anthropic and Google fell back to
  `ellmer::chat_openai("gpt-4o-mini")`, which sent the conversation to
  OpenAI whenever `OPENAI_API_KEY` was set.

- `run_r_code` and `run_bash` now tell the model when a command timed
  out or its subprocess failed, instead of failing internally or
  reporting a generic “Command failed”
  ([\#27](https://github.com/JamesHWade/deputy/issues/27)).

- `Agent$cost()` now returns `NA` when the cost of any request is
  unknown; its `complete` and `missing` fields tell a real zero from an
  unknown total. A run with a cost limit stops with reason
  `"cost_unavailable"` when its cost can’t be known, rather than
  enforcing an understated total
  ([\#29](https://github.com/JamesHWade/deputy/issues/29)).

- A run now stops with reason `"tool_loop"` after three consecutive
  identical tool calls that return the same result. Small differences in
  the model’s surrounding text don’t reset the count, but a changed
  result does, so polling still works
  ([\#34](https://github.com/JamesHWade/deputy/issues/34)).

- [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md),
  and
  [`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md)
  policies that don’t set `r_code`, no longer allow running R code, and
  `tools_preset("standard")` no longer includes `run_r_code`. The
  built-in R and shell tools run code with your account’s access and are
  not sandboxed. For sandboxed R, new
  [`tools_mcp_repl()`](https://jameshwade.github.io/deputy/reference/tools_mcp_repl.md)
  loads mcp-repl only with the `read-only` or `workspace-write` sandbox,
  and refuses missing, inherited, external or unrestricted sandbox
  settings ([\#32](https://github.com/JamesHWade/deputy/issues/32)).

- [`tools_web()`](https://jameshwade.github.io/deputy/reference/tools_web.md)
  now behaves as documented. Provider-run web search and fetch tools are
  checked against the `web` permission at registration, because Deputy
  can’t see their individual calls (so a `can_use_tool` callback can’t
  approve them either); other provider-side tools are refused. Narrowing
  permissions to remove web access removes these tools.

- [`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)
  now takes a `callback` and `context` for its `ask_user` tool, so
  concurrent agents, such as one per Shiny session, each get their own
  handler. Without a handler, `ask_user` signals
  `deputy_human_input_unavailable`.
  [`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)
  remains as a process-wide fallback for single-agent scripts
  ([\#76](https://github.com/JamesHWade/deputy/issues/76)).

## deputy 0.0.0.9000

- Streaming now emits `tool_start`, `tool_end`, `usage` and
  `file_checkpoint` events. Each run has a stable ID,
  `Agent$interrupt()` asks a running agent to stop, and `AgentResult`
  includes the run’s usage.
- New
  [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  and
  [`AgentUsage()`](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  track and limit requests, tool calls, input, output and total tokens,
  and estimated cost for each run. Subagents inherit the lead’s
  remaining limits, and their usage is added to the lead’s.
- New file checkpoints: Deputy’s write and edit tools save each file’s
  exact bytes before changing it, so the agent can rewind them. The lead
  and its subagents share one checkpoint journal per workspace, which
  has a size limit and is kept in saved sessions.
- Stricter permission checks: every file-writing tool respects the
  allowed write directory, and `"readonly"` mode denies unknown,
  writing, destructive and disallowed open-world tools. Loading a saved
  conversation keeps the agent’s own permissions, workspace and tools.
- When a `PostToolUse` hook replaces or suppresses a tool’s output,
  streamed tool events show the change too.
  `PermissionResultDeny(interrupt = TRUE)` now stops an active stream.
- New `run_shiny()` runs an agent for Shiny with the agent’s limits,
  file roots and checkpoints. It starts lazily, can be cancelled, and
  recovers from incomplete tool calls. While a run is active, loading a
  session, rewinding files or compacting is an error.
- MCP status reporting and more detailed subagent run metadata.
- Initial development version.
- Core `Agent` class with streaming `run()` and blocking `run_sync()`
  methods.
- Built-in tools: `tool_read_file`, `tool_write_file`,
  `tool_list_files`, `tool_run_r_code`, `tool_run_bash`,
  `tool_read_csv`.
- Tool bundles:
  [`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md),
  [`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md),
  [`tools_data()`](https://jameshwade.github.io/deputy/reference/tools_data.md),
  [`tools_all()`](https://jameshwade.github.io/deputy/reference/tools_all.md).
- Permissions with
  [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md),
  [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md),
  [`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md)
  and custom `Permissions`.
- Hooks with `HookMatcher` for the `PreToolUse`, `PostToolUse`, `Stop`,
  `UserPromptSubmit` and `PreCompact` events.
- Delegation with
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  and `LeadAgent`.
- Skills with
  [`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md),
  [`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md)
  and `Skill`.
- Saving and loading conversations with `Agent$save_session()` and
  `Agent$load_session()`.
- Works with any chat provider that ellmer supports.
