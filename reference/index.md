# Package index

## Agent

Run a task and inspect its response, tool calls, and usage.

- [`Agent`](https://jameshwade.github.io/deputy/reference/Agent.md) :
  Agent R6 Class
- [`AgentResult()`](https://jameshwade.github.io/deputy/reference/AgentResult.md)
  : Create a completed agent result
- [`result_n_turns()`](https://jameshwade.github.io/deputy/reference/result_n_turns.md)
  : Count conversation turns
- [`result_tool_calls()`](https://jameshwade.github.io/deputy/reference/result_tool_calls.md)
  : Inspect tool calls
- [`result_tool_results()`](https://jameshwade.github.io/deputy/reference/result_tool_results.md)
  : Inspect completed tool calls
- [`result_text_chunks()`](https://jameshwade.github.io/deputy/reference/result_text_chunks.md)
  : Inspect streamed text
- [`result_is_success()`](https://jameshwade.github.io/deputy/reference/result_is_success.md)
  : Inspect run success
- [`AgentEvent()`](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
  : Create an agent event
- [`AgentUsage()`](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  : Create an agent usage record
- [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  : Configure run-scoped usage limits
- [`ContextPolicy()`](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
  : Configure automatic context management
- [`DeputyCompaction()`](https://jameshwade.github.io/deputy/reference/DeputyCompaction.md)
  : Record a conversation compaction outcome

## Tools

Built-in tools and tool bundles

- [`tool_read_file()`](https://jameshwade.github.io/deputy/reference/tool_read_file.md)
  : Read file contents
- [`tool_read_markdown()`](https://jameshwade.github.io/deputy/reference/tool_read_markdown.md)
  : Convert a file to markdown using MarkItDown
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
- [`tool_run_r_code()`](https://jameshwade.github.io/deputy/reference/tool_run_r_code.md)
  : Execute R code
- [`RSession`](https://jameshwade.github.io/deputy/reference/RSession.md)
  : Own a conversation's trusted R session
- [`tool_run_bash()`](https://jameshwade.github.io/deputy/reference/tool_run_bash.md)
  : Execute bash commands
- [`tool_read_csv()`](https://jameshwade.github.io/deputy/reference/tool_read_csv.md)
  : Read a CSV file
- [`tool_web_fetch()`](https://jameshwade.github.io/deputy/reference/tool_web_fetch.md)
  : Fetch web page content
- [`tool_web_search()`](https://jameshwade.github.io/deputy/reference/tool_web_search.md)
  : Search the web
- [`tool_ask_user()`](https://jameshwade.github.io/deputy/reference/tool_ask_user.md)
  : Ask user tool
- [`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md)
  : File operation tools
- [`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md)
  : Code execution tools
- [`tools_data()`](https://jameshwade.github.io/deputy/reference/tools_data.md)
  : Data reading tools
- [`tools_web()`](https://jameshwade.github.io/deputy/reference/tools_web.md)
  : Web tools
- [`tools_all()`](https://jameshwade.github.io/deputy/reference/tools_all.md)
  : All built-in tools
- [`tools_preset()`](https://jameshwade.github.io/deputy/reference/tools_preset.md)
  : Get a tool preset by name
- [`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)
  : Tools for interactive workflows
- [`tools_mcp()`](https://jameshwade.github.io/deputy/reference/tools_mcp.md)
  : Get tools from MCP servers
- [`McpConnection`](https://jameshwade.github.io/deputy/reference/McpConnection.md)
  : Own an isolated MCP client connection
- [`tool_metadata()`](https://jameshwade.github.io/deputy/reference/tool_metadata.md)
  : Inspect a tool's origin and annotation coverage
- [`tools_mcp_repl()`](https://jameshwade.github.io/deputy/reference/tools_mcp_repl.md)
  : Load an R REPL with an enforced OS sandbox
- [`mcp_repl_connection()`](https://jameshwade.github.io/deputy/reference/mcp_repl_connection.md)
  : Connect an Agent to an independent sandboxed REPL
- [`mcp_repl_control()`](https://jameshwade.github.io/deputy/reference/mcp_repl_control.md)
  : Request an upstream REPL interrupt or reset
- [`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)
  : Set callback for non-interactive user input

## Permissions

Control what agents can do

- [`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md)
  : Create a permission policy
- [`permissions_check()`](https://jameshwade.github.io/deputy/reference/permissions_check.md)
  : Evaluate a tool call against a permission policy
- [`PermissionMode`](https://jameshwade.github.io/deputy/reference/PermissionMode.md)
  : Permission modes for agent tool access
- [`PermissionResultAllow()`](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md)
  : Create an allow permission result
- [`PermissionResultDeny()`](https://jameshwade.github.io/deputy/reference/PermissionResultDeny.md)
  : Create a deny permission result
- [`PermissionResultPending()`](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md)
  : Request a durable tool approval
- [`ApprovalContinuation()`](https://jameshwade.github.io/deputy/reference/ApprovalContinuation.md)
  : Durable approval inspection value
- [`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md)
  : Inspect a durable approval continuation
- [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md)
  : Create a standard permission policy
- [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md)
  : Create a read-only permission policy
- [`permissions_plan()`](https://jameshwade.github.io/deputy/reference/permissions_plan.md)
  : Create a planning permission policy
- [`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md)
  : Create a full access permission policy

## Hooks

Intercept and customize agent behavior

- [`HookEvent`](https://jameshwade.github.io/deputy/reference/HookEvent.md)
  : Hook events supported by deputy
- [`HookMatcher()`](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
  : Match a lifecycle hook
- [`hook_matches()`](https://jameshwade.github.io/deputy/reference/hook_matches.md)
  : Test whether a hook matches a tool name
- [`HookResult()`](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
  [`PermissionResult()`](https://jameshwade.github.io/deputy/reference/CallbackResult.md)
  : Callback result value families
- [`HookResultPreToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPreToolUse.md)
  : Create a PreToolUse hook result
- [`HookResultPostToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPostToolUse.md)
  : Create a PostToolUse hook result
- [`HookResultPreCompact()`](https://jameshwade.github.io/deputy/reference/HookResultPreCompact.md)
  : Create a PreCompact hook result
- [`hook_log_tools()`](https://jameshwade.github.io/deputy/reference/hook_log_tools.md)
  : Create a hook that logs all tool calls
- [`hook_block_dangerous_bash()`](https://jameshwade.github.io/deputy/reference/hook_block_dangerous_bash.md)
  : Create a hook that blocks dangerous bash commands
- [`hook_limit_file_writes()`](https://jameshwade.github.io/deputy/reference/hook_limit_file_writes.md)
  : Create a hook that limits file writes to a directory

## Skills

Load reusable instructions for an agent.

- [`Skill()`](https://jameshwade.github.io/deputy/reference/Skill.md) :
  Declarative Skill Configuration
- [`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md)
  : Load a skill from a directory
- [`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md)
  : Create a skill programmatically
- [`skill_check_requirements()`](https://jameshwade.github.io/deputy/reference/skill_check_requirements.md)
  : Check Skill Requirements
- [`skills_list()`](https://jameshwade.github.io/deputy/reference/skills_list.md)
  : List available skills in a directory

## Multi-Agent

Coordinate multiple specialized agents

- [`LeadAgent`](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
  : LeadAgent R6 Class
- [`AgentDefinition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  : Create an Agent Definition
- [`agent_definition_read()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md)
  [`agent_definition_write()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md)
  [`agent_definitions()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md)
  : Read, write, and discover AgentDefinition files

## Errors

Catch errors by class and inspect their details.

- [`deputy-errors`](https://jameshwade.github.io/deputy/reference/deputy-errors.md)
  [`DeputyError`](https://jameshwade.github.io/deputy/reference/deputy-errors.md)
  : Deputy Error Classes
- [`is_deputy_error()`](https://jameshwade.github.io/deputy/reference/is_deputy_error.md)
  : Check if an object is a deputy error
