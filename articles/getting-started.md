# Getting Started with deputy

deputy is an agentic AI framework for R that builds on
[ellmer](https://ellmer.tidyverse.org/). It enables you to create AI
agents that use tools to accomplish multi-step tasks, with built-in
support for permissions, hooks, and streaming output.

## Installation

``` r
# Install from GitHub
pak::pak("JamesHWade/deputy")
```

## Quick Start

An agent wraps an ellmer chat object and gives it tools, permissions,
and lifecycle hooks:

``` r
library(deputy)

chat <- ellmer::chat_anthropic(model = "claude-sonnet-4-20250514")
agent <- Agent$new(chat = chat, tools = tools_file())

result <- agent$run_sync("List the files in the current directory")
cat(result$response)
```

The agent sends your task to the LLM, which may call tools, and loops
until the task is complete. `run_sync()` blocks until done and returns
an `AgentResult`.

## Tool Bundles

deputy organises built-in tools into bundles you can mix and match:

| Bundle                                                                        | Tools                                   | Purpose         |
|-------------------------------------------------------------------------------|-----------------------------------------|-----------------|
| [`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md) | `read_file`, `write_file`, `list_files` | File operations |
| [`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md) | `run_r_code`, `run_bash`                | Code execution  |
| [`tools_data()`](https://jameshwade.github.io/deputy/reference/tools_data.md) | `read_csv`, `read_file`                 | Data reading    |
| [`tools_web()`](https://jameshwade.github.io/deputy/reference/tools_web.md)   | `web_fetch`, `web_search`               | Web access      |
| [`tools_all()`](https://jameshwade.github.io/deputy/reference/tools_all.md)   | All of the above                        | Everything      |

``` r
# Combine bundles
agent <- Agent$new(
  chat = ellmer::chat_anthropic(),
  tools = c(tools_file(), tools_code())
)
```

There are also named presets available via
[`tools_preset()`](https://jameshwade.github.io/deputy/reference/tools_preset.md):

``` r
list_presets()
tools_preset("dev")
```

See
[`vignette("tools")`](https://jameshwade.github.io/deputy/articles/tools.md)
for custom tools, web tools, MCP integration, and human-in-the-loop.

## Streaming

For real-time feedback, use `run()` which returns a generator:

``` r
chat <- ellmer::chat_anthropic(model = "claude-sonnet-4-20250514")
agent <- Agent$new(chat = chat, tools = tools_file())

for (event in agent$run("What is the name of this package?")) {
  switch(event$type,
    "text" = cat(event$text),
    "tool_start" = cli::cli_alert_info("Calling {event$tool_name}..."),
    "tool_end" = cli::cli_alert_success("Done"),
    "stop" = cli::cli_alert("Finished!")
  )
}
```

Events stream as they happen – you see text tokens arrive, tool calls
start and finish, and a final stop event.

## Permissions

### Read-Only Permissions

``` r
# Only allows reading files - no writes, no code execution
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_file(),
  permissions = permissions_readonly()
)
```

### Full Permissions

``` r
# Allows everything - use with caution!
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_all(),
  permissions = permissions_full()
)
```

### Custom Permissions

For fine-grained control:

``` r
perms <- Permissions$new(
  file_read = TRUE,
  file_write = "/path/to/allowed/dir", # Restrict to specific directory

  bash = FALSE,
  r_code = TRUE,
  web = FALSE,
  max_turns = 10,
  max_cost_usd = 0.50
)

agent <- Agent$new(
  chat = ellmer::chat("openai"),
  permissions = perms
)
```

### Custom Permission Callbacks

For complex permission logic:

``` r
perms <- Permissions$new(
  can_use_tool = function(tool_name, tool_input, context) {
    # Block any file writes to sensitive directories
    if (tool_name == "write_file") {
      if (grepl("^\\.env|secrets|credentials", tool_input$path)) {
        return(PermissionResultDeny(
          reason = "Cannot write to sensitive files"
        ))
      }
    }
    PermissionResultAllow()
  }
)
```

### Tool Allow/Deny Lists (Claude SDK-style)

Use allow/deny lists when you want an explicit tool policy that is
separate from the broader mode flags:

``` r
perms <- Permissions$new(
  mode = "default",
  tool_allowlist = c("read_file", "list_files", "run_r_code"),
  tool_denylist = c("run_bash"),
  permission_prompt_tool_name = "AskUserQuestion"
)

agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_all(),
  permissions = perms
)
```

If both lists are present, `tool_denylist` wins. The
`permission_prompt_tool_name` tool is always allowed and appears in deny
reasons so the model can request approval.

### Applying Tool Policy from `.claude/settings.json`

`setting_sources` now maps Claude-style tool policy keys directly into
permissions:

``` r
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_all(),
  setting_sources = "project"
)
```

Example `.claude/settings.json`:

``` json
{
  "allowedTools": ["read_file", "list_files", "run_r_code"],
  "disallowedTools": ["run_bash"],
  "permissionPromptToolName": "AskUserQuestion"
}
```

## Hooks

Hooks let you intercept and customize agent behavior at key points:

### Available Hook Events

| Event              | When it Fires                  | Can Modify        |
|--------------------|--------------------------------|-------------------|
| `PreToolUse`       | Before a tool executes         | Allow/deny, input |
| `PostToolUse`      | After a tool executes          | Continue flag     |
| `Stop`             | When agent stops               | \-                |
| `UserPromptSubmit` | When user sends a message      | \-                |
| `PreCompact`       | Before conversation compaction | Summary           |

### Example: Logging All Tool Calls

``` r
agent$add_hook(HookMatcher$new(
  event = "PostToolUse",
  callback = function(tool_name, tool_result, context) {
    cli::cli_alert_info("Tool {tool_name} completed")
    HookResultPostToolUse()
  }
))
```

### Example: Block Dangerous Commands

``` r
agent$add_hook(HookMatcher$new(
  event = "PreToolUse",
  pattern = "^run_bash$", # Only match bash tool
  callback = function(tool_name, tool_input, context) {
    if (grepl("rm -rf|sudo|chmod 777", tool_input$command)) {
      HookResultPreToolUse(
        permission = "deny",
        reason = "Dangerous command pattern detected"
      )
    } else {
      HookResultPreToolUse(permission = "allow")
    }
  }
))
```

## Session Management

Save and restore agent sessions:

``` r
# Save the current session
agent$save_session("my_session.rds")

# Later, restore it
agent2 <- Agent$new(chat = ellmer::chat("openai"))
agent2$load_session("my_session.rds")

# Continue the conversation
result <- agent2$run_sync("Continue where we left off...")
```

## Multi-Agent Systems

For complex tasks, you can create a lead agent that delegates to
specialized sub-agents:

``` r
# Define specialized sub-agents
code_agent <- agent_definition(
  name = "code_analyst",
  description = "Analyzes R code and suggests improvements",
  prompt = "You are an expert R programmer. Analyze code for best practices.",
  tools = tools_file()
)

data_agent <- agent_definition(
  name = "data_analyst",
  description = "Analyzes data files and provides statistical summaries",
  prompt = "You are a data analyst. Provide clear statistical insights.",
  tools = tools_data()
)

# Create a lead agent that can delegate
lead <- LeadAgent$new(
  chat = ellmer::chat("openai"),
  sub_agents = list(code_agent, data_agent),
  system_prompt = "You coordinate between specialized agents to complete tasks."
)

# The lead agent will automatically delegate to sub-agents as needed
result <- lead$run_sync(
  "Review the R code in src/ and analyze the data in data/"
)
```

## Working with Results

The `AgentResult` object contains useful information:

``` r
result <- agent$run_sync("Analyze this project")

# The final response
cat(result$response)

# Cost information
result$cost
#> $input
#> [1] 1250
#> $output
#> [1] 450
#> $total
#> [1] 0.0045

# Execution duration
result$duration
#> [1] 3.45  # seconds

# Stop reason
result$stop_reason
#> [1] "complete"

# All events (for detailed analysis)
length(result$events)
#> [1] 12
```

## Provider Support

deputy works with any LLM provider that ellmer supports:

``` r
# OpenAI
agent <- Agent$new(chat = ellmer::chat("openai"))

# Anthropic
agent <- Agent$new(chat = ellmer::chat("anthropic/claude-sonnet-4-5-20250929"))

# Google
agent <- Agent$new(chat = ellmer::chat("google/gemini-1.5-pro"))

# Local models via Ollama
agent <- Agent$new(chat = ellmer::chat("ollama/llama3.1"))
```

## Best Practices

1.  **Start with minimal permissions** - Use
    [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md)
    or
    [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md)
    and only expand as needed.

2.  **Use hooks for logging** - Add a `PostToolUse` hook to track what
    your agent does.

3.  **Set cost limits** - Use `max_cost_usd` in permissions to prevent
    runaway costs.

4.  **Save sessions** - For long-running tasks, save sessions
    periodically.

5.  **Use streaming for UX** - The `run()` method provides real-time
    feedback.

``` r
# Example combining best practices
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_file(),
  permissions = Permissions$new(
    file_write = getwd(),
    max_turns = 20,
    max_cost_usd = 1.00
  )
)
```

## Next Steps

- [`vignette("tools")`](https://jameshwade.github.io/deputy/articles/tools.md)
  – Custom tools, web tools, MCP, and human-in-the-loop
- [`vignette("permissions")`](https://jameshwade.github.io/deputy/articles/permissions.md)
  – Permission presets, modes, and custom policies
- [`vignette("hooks")`](https://jameshwade.github.io/deputy/articles/hooks.md)
  – Lifecycle hooks for logging, blocking, and auditing
- [`vignette("multi-agent")`](https://jameshwade.github.io/deputy/articles/multi-agent.md)
  – Multi-agent delegation with LeadAgent
- [`vignette("structured-output")`](https://jameshwade.github.io/deputy/articles/structured-output.md)
  – JSON schema output and validation
- [`vignette("agent-configuration")`](https://jameshwade.github.io/deputy/articles/agent-configuration.md)
  – Settings, skills, sessions, and AgentResult
