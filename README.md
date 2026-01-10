
<!-- README.md is generated from README.Rmd. Please edit that file -->

# deputy <a href="https://jameshwade.github.io/deputy/"><img src="man/figures/logo.png" align="right" height="138" alt="deputy website" /></a>

<!-- badges: start -->

[![R-CMD-check](https://github.com/JamesHWade/deputy/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JamesHWade/deputy/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/JamesHWade/deputy/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/JamesHWade/deputy/actions/workflows/pkgdown.yaml)
[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![Codecov test
coverage](https://codecov.io/gh/JamesHWade/deputy/graph/badge.svg)](https://app.codecov.io/gh/JamesHWade/deputy)
<!-- badges: end -->

deputy is an R implementation of [Anthropic’s Claude Agent
SDK](https://github.com/anthropics/claude-code/tree/main/agent-sdk),
built on [ellmer](https://ellmer.tidyverse.org/). It enables you to
create AI agents that can use tools to accomplish multi-step tasks, with
built-in support for permissions, hooks, and streaming output.

> **Note:** This package aims to bring the patterns and capabilities of
> the Claude Agent SDK to the R ecosystem. While inspired by Anthropic’s
> SDK, deputy is provider-agnostic and works with any LLM that ellmer
> supports.

## Features

- **Provider-agnostic** - Works with OpenAI, Anthropic, Google, Ollama,
  and any provider ellmer supports
- **Tool bundles** - Pre-built tools for file operations, code
  execution, and data analysis
- **Permission system** - Fine-grained control over what agents can do
- **Hooks** - Intercept and customize agent behavior at key points
- **Streaming output** - Real-time feedback as agents work
- **Multi-agent** - Coordinate specialized sub-agents for complex tasks
- **Session persistence** - Save and restore agent conversations

## Installation

You can install the development version of deputy from GitHub:

``` r
# install.packages("pak")
pak::pak("JamesHWade/deputy")
```

You’ll also need ellmer:

``` r
pak::pak("tidyverse/ellmer")
```

## Quick Start

### Create an Agent

``` r
library(deputy)

# Create an agent with file tools
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_file()
)

# Run a task (blocking)
result <- agent$run_sync("What R files are in the current directory?")
cat(result$response)
```

### Streaming Output

For real-time feedback as the agent works:

``` r
for (event in agent$run("Analyze the structure of this project")) {
  switch(
    event$type,
    "text" = cat(event$text),
    "tool_start" = message("Calling ", event$tool_name, "..."),
    "stop" = message("\nDone! Cost: $", round(event$cost$total, 4))
  )
}
```

### Tools

deputy provides tool presets for common use cases:

``` r
# Use presets for quick setup
tools_preset("minimal")   # read_file, list_files
tools_preset("standard")  # + write_file, run_r_code
tools_preset("dev")       # + run_bash (full development)
tools_preset("data")      # read_file, list_files, read_csv, run_r_code
tools_preset("full")      # all tools

# Or use individual bundles
tools_file()  # File operations
tools_code()  # Code execution
tools_data()  # Data reading
tools_all()   # Everything

# List available presets
list_presets()
```

### Permissions

Control what your agent can do:

``` r
# Read-only: no writes, no code execution
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_file(),
  permissions = permissions_readonly()
)

# Standard: file read/write in working dir, R code, no bash
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_file(),
  permissions = permissions_standard()
)

# Custom permissions with limits
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_all(),
  permissions = Permissions$new(
    file_write = getwd(),
    bash = FALSE,
    r_code = TRUE,
    max_turns = 10,
    max_cost_usd = 0.50
  )
)
```

### Hooks

Intercept agent behavior:

``` r
# Log all tool calls
agent$add_hook(HookMatcher$new(
  event = "PostToolUse",
  callback = function(tool_name, tool_result, context) {
    message("[", Sys.time(), "] ", tool_name)
    HookResultPostToolUse()
  }
))

# Block dangerous bash commands
agent$add_hook(HookMatcher$new(
  event = "PreToolUse",
  pattern = "^run_bash$",
  callback = function(tool_name, tool_input, context) {
    if (grepl("rm -rf|sudo", tool_input$command)) {
      HookResultPreToolUse(permission = "deny", reason = "Dangerous command")
    } else {
      HookResultPreToolUse(permission = "allow")
    }
  }
))

# Track session lifecycle for metrics/logging
agent$add_hook(HookMatcher$new(
  event = "SessionStart",
  callback = function(context) {
    message("Session started with ", context$tools_count, " tools")
    HookResultSessionStart()
  }
))

agent$add_hook(HookMatcher$new(
  event = "SessionEnd",
  callback = function(reason, context) {
    message("Session ended: ", reason, " after ", context$total_turns, " turns")
    HookResultSessionEnd()
  }
))
```

### Error Handling

deputy provides structured error types for programmatic error handling:

``` r
# Catch specific error types
tryCatch(
  agent$run_sync("task"),
  deputy_budget_exceeded = function(e) {
    message("Budget exceeded: $", e$current_cost, " > $", e$max_cost)
  },
  deputy_session_load = function(e) {
    message("Failed to load session from: ", e$path)
  },
  deputy_error = function(e) {
    message("Deputy error: ", conditionMessage(e))
  }
)
```

### Multi-Agent Systems

Coordinate specialized agents:

``` r
# Define sub-agents
code_agent <- agent_definition(
  name = "code_analyst",
  description = "Analyzes R code",
  prompt = "You are an expert R programmer.",
  tools = tools_file()
)

# Create lead agent that can delegate
lead <- LeadAgent$new(
  chat = ellmer::chat("openai"),
  sub_agents = list(code_agent)
)

result <- lead$run_sync("Review the R code in this project")
```

## Provider Support

deputy works with any LLM provider that ellmer supports:

``` r
# OpenAI
Agent$new(chat = ellmer::chat("openai"))

# Anthropic
Agent$new(chat = ellmer::chat("anthropic"))

# Google
Agent$new(chat = ellmer::chat("google_gemini"))

# Local via Ollama
Agent$new(chat = ellmer::chat("ollama/llama3.2"))
```

## Learn More

- `vignette("getting-started")` - Comprehensive introduction
- [ellmer documentation](https://ellmer.tidyverse.org/) - Underlying LLM
  framework

## License

MIT
