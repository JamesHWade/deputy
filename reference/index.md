# Package index

## Agent

Core agent class for agentic AI workflows

- [`Agent`](https://jameshwade.github.io/deputy/reference/Agent.md) :
  Agent R6 Class
- [`AgentResult`](https://jameshwade.github.io/deputy/reference/AgentResult.md)
  : Agent Result R6 Class
- [`AgentEvent()`](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
  : Create an agent event

## Tools

Built-in tools and tool bundles

- [`tool_ask_user()`](https://jameshwade.github.io/deputy/reference/tool_ask_user.md)
  : AskUserQuestion tool
- [`tool_list_files()`](https://jameshwade.github.io/deputy/reference/tool_list_files.md)
  : List files in a directory
- [`tool_read_csv()`](https://jameshwade.github.io/deputy/reference/tool_read_csv.md)
  : Read a CSV file
- [`tool_read_file()`](https://jameshwade.github.io/deputy/reference/tool_read_file.md)
  : Read file contents
- [`tool_run_bash()`](https://jameshwade.github.io/deputy/reference/tool_run_bash.md)
  : Execute bash commands
- [`tool_run_r_code()`](https://jameshwade.github.io/deputy/reference/tool_run_r_code.md)
  : Execute R code
- [`tool_web_fetch()`](https://jameshwade.github.io/deputy/reference/tool_web_fetch.md)
  : Fetch web page content
- [`tool_web_search()`](https://jameshwade.github.io/deputy/reference/tool_web_search.md)
  : Search the web
- [`tool_write_file()`](https://jameshwade.github.io/deputy/reference/tool_write_file.md)
  : Write content to a file
- [`tools_all()`](https://jameshwade.github.io/deputy/reference/tools_all.md)
  : All built-in tools
- [`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md)
  : Code execution tools
- [`tools_data()`](https://jameshwade.github.io/deputy/reference/tools_data.md)
  : Data reading tools
- [`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md)
  : File operation tools
- [`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)
  : Tools for interactive workflows
- [`tools_mcp()`](https://jameshwade.github.io/deputy/reference/tools_mcp.md)
  : Get tools from MCP servers
- [`tools_preset()`](https://jameshwade.github.io/deputy/reference/tools_preset.md)
  : Get a tool preset by name
- [`tools_web()`](https://jameshwade.github.io/deputy/reference/tools_web.md)
  : Web tools
- [`ToolPresets`](https://jameshwade.github.io/deputy/reference/ToolPresets.md)
  : Available tool preset names
- [`list_presets()`](https://jameshwade.github.io/deputy/reference/list_presets.md)
  : List available tool presets
- [`set_ask_user_callback()`](https://jameshwade.github.io/deputy/reference/set_ask_user_callback.md)
  : Set callback for non-interactive user input

## MCP Integration

Model Context Protocol server support

- [`mcp_available()`](https://jameshwade.github.io/deputy/reference/mcp_available.md)
  : Check if MCP support is available
- [`mcp_servers()`](https://jameshwade.github.io/deputy/reference/mcp_servers.md)
  : List available MCP servers

## Permissions

Control what agents can do

- [`Permissions`](https://jameshwade.github.io/deputy/reference/Permissions.md)
  : Permissions R6 Class
- [`PermissionMode`](https://jameshwade.github.io/deputy/reference/PermissionMode.md)
  : Permission modes for agent tool access
- [`PermissionResultAllow()`](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md)
  : Create an allow permission result
- [`PermissionResultDeny()`](https://jameshwade.github.io/deputy/reference/PermissionResultDeny.md)
  : Create a deny permission result
- [`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md)
  : Create a full access permission policy
- [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md)
  : Create a read-only permission policy
- [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md)
  : Create a standard permission policy

## Hooks

Intercept and customize agent behavior

- [`HookMatcher`](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
  : HookMatcher R6 Class
- [`HookRegistry`](https://jameshwade.github.io/deputy/reference/HookRegistry.md)
  : HookRegistry R6 Class
- [`HookEvent`](https://jameshwade.github.io/deputy/reference/HookEvent.md)
  : Hook events supported by deputy
- [`HookResultPostToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPostToolUse.md)
  : Create a PostToolUse hook result
- [`HookResultPreCompact()`](https://jameshwade.github.io/deputy/reference/HookResultPreCompact.md)
  : Create a PreCompact hook result
- [`HookResultPreToolUse()`](https://jameshwade.github.io/deputy/reference/HookResultPreToolUse.md)
  : Create a PreToolUse hook result
- [`HookResultSessionEnd()`](https://jameshwade.github.io/deputy/reference/HookResultSessionEnd.md)
  : Create a SessionEnd hook result
- [`HookResultSessionStart()`](https://jameshwade.github.io/deputy/reference/HookResultSessionStart.md)
  : Create a SessionStart hook result
- [`HookResultStop()`](https://jameshwade.github.io/deputy/reference/HookResultStop.md)
  : Create a Stop hook result
- [`HookResultSubagentStop()`](https://jameshwade.github.io/deputy/reference/HookResultSubagentStop.md)
  : Create a SubagentStop hook result
- [`hook_block_dangerous_bash()`](https://jameshwade.github.io/deputy/reference/hook_block_dangerous_bash.md)
  : Create a hook that blocks dangerous bash commands
- [`hook_limit_file_writes()`](https://jameshwade.github.io/deputy/reference/hook_limit_file_writes.md)
  : Create a hook that limits file writes to a directory
- [`hook_log_tools()`](https://jameshwade.github.io/deputy/reference/hook_log_tools.md)
  : Create a hook that logs all tool calls

## Skills

Extend agents with specialized capabilities

- [`Skill`](https://jameshwade.github.io/deputy/reference/Skill.md) :
  Skill R6 Class
- [`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md)
  : Load a skill from a directory
- [`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md)
  : Create a skill programmatically
- [`skills_list()`](https://jameshwade.github.io/deputy/reference/skills_list.md)
  : List available skills in a directory

## Multi-Agent

Coordinate multiple specialized agents

- [`LeadAgent`](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
  : LeadAgent R6 Class
- [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  : Create an Agent Definition
- [`agent_with_delegation()`](https://jameshwade.github.io/deputy/reference/agent_with_delegation.md)
  : Create a simple delegation agent

## Errors

Error classes and constructors

- [`deputy-errors`](https://jameshwade.github.io/deputy/reference/deputy-errors.md)
  [`DeputyError`](https://jameshwade.github.io/deputy/reference/deputy-errors.md)
  : Deputy Error Classes
- [`is_deputy_error()`](https://jameshwade.github.io/deputy/reference/is_deputy_error.md)
  : Check if an object is a deputy error
- [`abort_budget_exceeded()`](https://jameshwade.github.io/deputy/reference/abort_budget_exceeded.md)
  : Abort with a budget exceeded error
- [`abort_deputy()`](https://jameshwade.github.io/deputy/reference/abort_deputy.md)
  : Abort with a structured deputy error
- [`abort_hook()`](https://jameshwade.github.io/deputy/reference/abort_hook.md)
  : Abort with a hook error
- [`abort_permission_denied()`](https://jameshwade.github.io/deputy/reference/abort_permission_denied.md)
  : Abort with a permission denied error
- [`abort_provider()`](https://jameshwade.github.io/deputy/reference/abort_provider.md)
  : Abort with a provider error
- [`abort_session_load()`](https://jameshwade.github.io/deputy/reference/abort_session_load.md)
  : Abort with a session load error
- [`abort_session_save()`](https://jameshwade.github.io/deputy/reference/abort_session_save.md)
  : Abort with a session save error
- [`abort_tool_execution()`](https://jameshwade.github.io/deputy/reference/abort_tool_execution.md)
  : Abort with a tool execution error
- [`abort_turn_limit()`](https://jameshwade.github.io/deputy/reference/abort_turn_limit.md)
  : Abort with a turn limit error
