# Package index

## Agents

Create an agent, run a task, and inspect what happened.

- [`Agent`](https://jameshwade.github.io/deputy/reference/Agent.md) :
  Agent that runs tasks with tools
- [`AgentResult()`](https://jameshwade.github.io/deputy/reference/AgentResult.md)
  : Create an agent run result
- [`result_is_success()`](https://jameshwade.github.io/deputy/reference/result_is_success.md)
  : Check whether a run completed
- [`result_n_turns()`](https://jameshwade.github.io/deputy/reference/result_n_turns.md)
  : Count the turns in a result
- [`result_text_chunks()`](https://jameshwade.github.io/deputy/reference/result_text_chunks.md)
  : Get the streamed text chunks from a result
- [`result_tool_calls()`](https://jameshwade.github.io/deputy/reference/result_tool_calls.md)
  : Get the tool calls from a result
- [`result_tool_results()`](https://jameshwade.github.io/deputy/reference/result_tool_results.md)
  : Get the finished tool calls from a result
- [`AgentEvent()`](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
  : Create an agent event
- [`AgentUsage()`](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  : Create a usage record
- [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  : Set usage limits for a run

## Conversations and context

Keep long conversations within the model’s context window.

- [`ContextPolicy()`](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  : Configure automatic context management
- [`DeputyCompaction()`](https://jameshwade.github.io/deputy/reference/DeputyCompaction.md)
  : Create a compaction result

## Built-in tools

Tools for files, data, the web and code, and presets that bundle them.

- [`tools_preset()`](https://jameshwade.github.io/deputy/reference/tools_preset.md)
  : Get a tool preset by name
- [`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md)
  : Get the basic file tools
- [`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md)
  : Get the code execution tools
- [`tools_data()`](https://jameshwade.github.io/deputy/reference/tools_data.md)
  : Get the data reading tools
- [`tools_web()`](https://jameshwade.github.io/deputy/reference/tools_web.md)
  : Get web tools
- [`tools_all()`](https://jameshwade.github.io/deputy/reference/tools_all.md)
  : Get all built-in tools
- [`tool_read_file()`](https://jameshwade.github.io/deputy/reference/tool_read_file.md)
  : Read file contents
- [`tool_read_markdown()`](https://jameshwade.github.io/deputy/reference/tool_read_markdown.md)
  : Convert a file to Markdown using MarkItDown
- [`tool_write_file()`](https://jameshwade.github.io/deputy/reference/tool_write_file.md)
  : Write content to a file
- [`tool_edit_file()`](https://jameshwade.github.io/deputy/reference/tool_edit_file.md)
  : Edit file contents by replacing text
- [`tool_multi_edit()`](https://jameshwade.github.io/deputy/reference/tool_multi_edit.md)
  : Apply multiple text edits to a file
- [`tool_list_files()`](https://jameshwade.github.io/deputy/reference/tool_list_files.md)
  : List files in a directory
- [`tool_glob_files()`](https://jameshwade.github.io/deputy/reference/tool_glob_files.md)
  : Find files using a glob pattern
- [`tool_grep_files()`](https://jameshwade.github.io/deputy/reference/tool_grep_files.md)
  : Search file contents with grep-like matching
- [`tool_read_csv()`](https://jameshwade.github.io/deputy/reference/tool_read_csv.md)
  : Read a CSV file
- [`tool_run_r_code()`](https://jameshwade.github.io/deputy/reference/tool_run_r_code.md)
  : Execute R code
- [`tool_run_bash()`](https://jameshwade.github.io/deputy/reference/tool_run_bash.md)
  : Execute bash commands
- [`tool_web_fetch()`](https://jameshwade.github.io/deputy/reference/tool_web_fetch.md)
  : Fetch web page content
- [`tool_web_search()`](https://jameshwade.github.io/deputy/reference/tool_web_search.md)
  : Search the web
- [`tool_metadata()`](https://jameshwade.github.io/deputy/reference/tool_metadata.md)
  : Inspect a tool's origin and annotations

## Running code

Persistent R sessions and OS-sandboxed interpreters.

- [`RSession`](https://jameshwade.github.io/deputy/reference/RSession.md)
  : Persistent R session for a conversation
- [`tools_mcp_repl()`](https://jameshwade.github.io/deputy/reference/tools_mcp_repl.md)
  : Load sandboxed R tools from mcp-repl
- [`mcp_repl_connection()`](https://jameshwade.github.io/deputy/reference/mcp_repl_connection.md)
  : Connect an agent to a sandboxed mcp-repl session
- [`mcp_repl_control()`](https://jameshwade.github.io/deputy/reference/mcp_repl_control.md)
  : Interrupt or reset an mcp-repl session
- [`mcp_console_connection()`](https://jameshwade.github.io/deputy/reference/mcp_console_connection.md)
  : Connect an agent to a sandboxed MCP Console session
- [`mcp_console_control()`](https://jameshwade.github.io/deputy/reference/mcp_console_control.md)
  : Interrupt or restart an MCP Console session

## MCP servers

Use tools, resources and prompts from Model Context Protocol servers.

- [`tools_mcp()`](https://jameshwade.github.io/deputy/reference/tools_mcp.md)
  : Get tools from MCP servers
- [`McpConnection`](https://jameshwade.github.io/deputy/reference/McpConnection.md)
  : MCP server connection

## Permissions

Decide which tool calls an agent may make.

- [`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md)
  : Create a permission policy
- [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md)
  : Create a standard permission policy
- [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md)
  : Create a read-only permission policy
- [`permissions_plan()`](https://jameshwade.github.io/deputy/reference/permissions_plan.md)
  : Create a planning permission policy
- [`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md)
  : Create a full access permission policy
- [`PermissionMode`](https://jameshwade.github.io/deputy/reference/PermissionMode.md)
  : Permission modes
- [`permissions_check()`](https://jameshwade.github.io/deputy/reference/permissions_check.md)
  : Check a tool call against a permission policy
- [`PermissionResultAllow()`](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md)
  : Create an allow permission result
- [`PermissionResultDeny()`](https://jameshwade.github.io/deputy/reference/PermissionResultDeny.md)
  : Create a deny permission result
- [`PermissionResultPending()`](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md)
  : Pause a tool call for approval

## Human input and approvals

Ask a person questions, and hold tool calls until someone approves them.

- [`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)
  : Create an ask_user tool with its own handler
- [`tool_ask_user()`](https://jameshwade.github.io/deputy/reference/tool_ask_user.md)
  : Ask the user questions
- [`AskUserDeferred()`](https://jameshwade.github.io/deputy/reference/AskUserDeferred.md)
  : Defer answers to a later user turn
- [`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)
  : Set a process-wide handler for ask_user
- [`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md)
  : Read a pending approval
- [`ApprovalContinuation()`](https://jameshwade.github.io/deputy/reference/ApprovalContinuation.md)
  : Pending approval record
- [`approval_review_ui()`](https://jameshwade.github.io/deputy/reference/approval_review_ui.md)
  [`approval_review_server()`](https://jameshwade.github.io/deputy/reference/approval_review_ui.md)
  : Review a pending tool call in Shiny
- [`tool_input_review()`](https://jameshwade.github.io/deputy/reference/tool_input_review.md)
  : Tabulate a tool call's arguments for review

## Trusted results

Make one tool the only source of each kind of result.

- [`TrustedResults()`](https://jameshwade.github.io/deputy/reference/TrustedResults.md)
  : Designate trusted tools
- [`result_trusted_results()`](https://jameshwade.github.io/deputy/reference/result_trusted_results.md)
  : Get the trusted results from a run

## Hooks

Run R code at fixed points in an agent’s lifecycle.

- [`HookEvent`](https://jameshwade.github.io/deputy/reference/HookEvent.md)
  : Hook events
- [`HookMatcher()`](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
  : Create a hook
- [`hook_matches()`](https://jameshwade.github.io/deputy/reference/hook_matches.md)
  : Test whether a hook matches a tool name
- [`hook_log_tools()`](https://jameshwade.github.io/deputy/reference/hook_log_tools.md)
  : Create a hook that logs tool calls
- [`hook_block_dangerous_bash()`](https://jameshwade.github.io/deputy/reference/hook_block_dangerous_bash.md)
  : Create a hook that blocks dangerous bash commands
- [`hook_limit_file_writes()`](https://jameshwade.github.io/deputy/reference/hook_limit_file_writes.md)
  : Create a hook that limits file writes to a directory
- [`HookResultPreToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPreToolUse.md)
  : Create a PreToolUse hook result
- [`HookResultPostToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPostToolUse.md)
  : Create a PostToolUse hook result
- [`HookResultPreCompact()`](https://jameshwade.github.io/deputy/reference/HookResultPreCompact.md)
  : Create a PreCompact hook result
- [`HookResult()`](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
  [`PermissionResult()`](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
  : Hook and permission results

## Skills

Package instructions and tools for reuse.

- [`Skill()`](https://jameshwade.github.io/deputy/reference/Skill.md) :
  Reusable instructions and tools
- [`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md)
  : Create a skill in code
- [`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md)
  : Load a skill from a directory
- [`skills_list()`](https://jameshwade.github.io/deputy/reference/skills_list.md)
  : List available skills in a directory
- [`skill_check_requirements()`](https://jameshwade.github.io/deputy/reference/skill_check_requirements.md)
  : Check a skill's requirements

## Subagents

Delegate parts of a task from a lead agent to specialists.

- [`LeadAgent`](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
  : Agent that delegates to subagents
- [`AgentDefinition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  : Define a subagent
- [`agent_definition_read()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md)
  [`agent_definition_write()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md)
  [`agent_definitions()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md)
  : Read and write agent definition files
- [`DelegationInput()`](https://jameshwade.github.io/deputy/reference/DelegationInput.md)
  : Describe a task for a subagent
- [`DelegationPolicy()`](https://jameshwade.github.io/deputy/reference/DelegationPolicy.md)
  : Configure subagent tools, hooks and user input
- [`DelegationResources()`](https://jameshwade.github.io/deputy/reference/DelegationResources.md)
  : Return tools from a resource factory
- [`DelegationManifest()`](https://jameshwade.github.io/deputy/reference/DelegationManifest.md)
  : Record what a subagent started with
- [`DelegationOutcome()`](https://jameshwade.github.io/deputy/reference/DelegationOutcome.md)
  : Result of a delegation
- [`DelegationDisclosure()`](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  : Control who can inspect subagents
- [`delegation_history()`](https://jameshwade.github.io/deputy/reference/delegation_history.md)
  : Replay saved subagent history
- [`DelegationObservation()`](https://jameshwade.github.io/deputy/reference/DelegationObservation.md)
  : Set limits for the subagent event buffer
- [`DelegationSubscription`](https://jameshwade.github.io/deputy/reference/DelegationSubscription.md)
  : Subscription to subagent events
- [`subagent_chat_ui()`](https://jameshwade.github.io/deputy/reference/subagent_chat_ui.md)
  [`subagent_chat_server()`](https://jameshwade.github.io/deputy/reference/subagent_chat_ui.md)
  : Show subagent conversations in a Shiny panel

## Retained specialists

Keep a specialist’s conversation across several delegations.

- [`adopt_chat()`](https://jameshwade.github.io/deputy/reference/adopt_chat.md)
  : Turn an ellmer chat into a retained agent
- [`delegation_tool()`](https://jameshwade.github.io/deputy/reference/delegation_tool.md)
  : Create a tool that calls a retained agent
- [`ContextFork()`](https://jameshwade.github.io/deputy/reference/ContextFork.md)
  : Capture conversation turns for a fork
- [`fork_agent()`](https://jameshwade.github.io/deputy/reference/fork_agent.md)
  : Start a retained agent from a conversation fork

## Background jobs

Queue work in one R process and run it in another.

- [`job_create()`](https://jameshwade.github.io/deputy/reference/job_create.md)
  : Create a background job
- [`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md)
  : Run a background job
- [`job_read()`](https://jameshwade.github.io/deputy/reference/job_read.md)
  : Read a background job
- [`job_cancel()`](https://jameshwade.github.io/deputy/reference/job_cancel.md)
  : Cancel a background job
- [`AgentJob()`](https://jameshwade.github.io/deputy/reference/AgentJob.md)
  : Background job record

## Errors

Catch Deputy errors by class.

- [`deputy-errors`](https://jameshwade.github.io/deputy/reference/deputy-errors.md)
  [`DeputyError`](https://jameshwade.github.io/deputy/reference/deputy-errors.md)
  : Deputy error classes
- [`is_deputy_error()`](https://jameshwade.github.io/deputy/reference/is_deputy_error.md)
  : Check whether a condition is a Deputy error
