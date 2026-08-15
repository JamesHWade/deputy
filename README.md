
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

deputy is a provider-agnostic agent runtime for R, built on
[ellmer](https://ellmer.tidyverse.org/). It enables you to create AI
agents that can use tools to accomplish multi-step tasks, with built-in
support for permissions, hooks, and streaming output. It also ships an
Agent SDK-compatible facade for teams that want Anthropic-style
entrypoints, tool aliases, settings, and persisted session workflows
without giving up deputy’s R-native runtime.

> **Note:** deputy keeps its R-native `Agent` and `LeadAgent` APIs as
> the canonical runtime. The compatibility layer is opt-in via either
> `agent_sdk_query()`, `agent_sdk_options()`, and `AgentSDKClient`, or
> the existing Claude-named aliases `claude_sdk_query()`,
> `claude_sdk_options()`, and `ClaudeSDKClient`.

## Features

- **Provider-agnostic** - Works with OpenAI, Anthropic, Google, Ollama,
  and any provider ellmer supports
- **Agent SDK-compatible facade** - Anthropic-style entrypoints,
  permission modes, tool aliases, and session semantics
- **Tool bundles** - Pre-built tools for file operations, code
  execution, and data analysis
- **Permission system** - Fine-grained control over what agents can do
- **Hooks** - Intercept and customize agent behavior at key points
- **Semantic streaming** - Text, content, tool lifecycle, usage, and
  stop events with run IDs
- **Run budgets** - Request, tool-call, token, and estimated-cost limits
- **File checkpoints** - Bounded, persisted byte-exact rewind for Deputy
  file tools
- **Multi-agent** - Coordinate specialized sub-agents for complex tasks
- **Session persistence** - Save and restore agent conversations,
  including Claude-compatible session snapshots

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
events <- agent$run("Analyze the structure of this project")
repeat {
  event <- events()
  if (coro::is_exhausted(event)) {
    break
  }
  switch(
    event$type,
    "text" = cat(event$text),
    "tool_start" = message("Calling ", event$tool_name, "..."),
    "stop" = message("\nDone! Cost: $", round(event$cost$total, 4))
  )
}
```

### CLI (`exec/deputy.R`)

deputy ships a [Rapp](https://github.com/r-lib/Rapp) package executable
that works with [`ir`](https://r-lib.github.io/ir/tools.html). Install
`ir` once, then run the package directly from GitHub without installing
deputy globally:

``` bash
uv tool install r-lib-ir
rx --from github::JamesHWade/deputy deputy --help
rx --from github::JamesHWade/deputy deputy \
  --provider openai "Summarize the R files in this project"
```

For a persistent `deputy` command, install its launcher:

``` bash
ir tool install github::JamesHWade/deputy
deputy --provider openai --model gpt-4o --tools standard
```

If deputy is already installed in an R library, Rapp can install the
same launcher:

``` r
Rapp::install_pkg_cli_apps("deputy")
```

The optional positional task selects non-interactive mode; omit it to
start an interactive session. Common options include short aliases
(`-p`, `-m`, `-t`, `-P`, `-n`, `-c`, `-d`, `-v`, etc.) and repeatable
Rapp 0.4 flags:

``` bash
deputy --setting-source project --setting-source user
deputy --mcp --mcp-server github --mcp-server slack
deputy --debug --debug-file /tmp/deputy-debug.log
```

`--mcp-servers "github,slack"` is still accepted for backward
compatibility, but `--mcp-server` is preferred.

Claude-compatible session controls are available when you want
persistent session ids and resume or fork behavior:

``` bash
deputy --permission-mode plan --persist-session
deputy --resume-session-id <session-id>
deputy --resume-session-id <session-id> --resume-session-at "2026-03-07 10:30:00"
deputy --resume-session-id <session-id> --fork-session
```

### Agent SDK-Compatible API

Use the compatibility facade when you want Claude-style options, tool
names, and session persistence without giving up deputy’s
provider-agnostic runtime:

``` r
options <- agent_sdk_options(
  chat = ellmer::chat("openai/gpt-4o"),
  setting_sources = c("user", "project", "local"),
  permission_mode = "plan"
)

# One-shot query
result <- agent_sdk_query(
  "Summarize the current repository state",
  options = options
)
result$session_id

# Stateful client with resume/fork semantics
client <- AgentSDKClient$new(options)
client$query("Inspect the package structure")
client$resume(result$session_id, fork = TRUE)
```

`agent_sdk_query()` and `AgentSDKClient$query()` are blocking. Use the
native `Agent$run()` generator when an application needs incremental
events. Resuming a compatibility session restores its conversation and
prompt while keeping the new agent’s configured tools,
constructor-supplied permissions, and working directory authoritative.
Native `Agent$load_session(..., restore_tools = TRUE)` is the explicit
opt-in for trusting and restoring serialized tools.

The compatibility layer exposes Anthropic-style tool aliases such as
`Read`, `Write`, `Edit`, `MultiEdit`, `Glob`, `Grep`, `LS`, `TodoRead`,
`TodoWrite`, `WebFetch`, `WebSearch`, and `Agent` or `Task` (when
sub-agents are registered). The Claude-named entrypoints remain fully
supported.

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

# Optional: read selected pages from a PDF
tool_read_file("report.pdf", pages = "1,3-5")

# Optional: convert rich docs to markdown with MarkItDown
tool_read_markdown("slides.pptx")
```

PDF page extraction uses `pdftools` when available, with a fallback to
`reticulate` + Python `pypdf`. `tool_read_markdown()` uses
`reticulate` + Python `markitdown`.

### Permissions

Control what your agent can do:

``` r
# Read-only: no writes, no code execution
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_file(),
  permissions = permissions_readonly()
)

# Standard: accessible reads, workspace-scoped writes, R code, no bash
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

# Claude SDK-style tool policy gates
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_all(),
  permissions = Permissions$new(
    tool_allowlist = c("read_file", "list_files", "run_r_code"),
    tool_denylist = c("run_bash"),
    permission_prompt_tool_name = "AskUserQuestion"
  )
)

# Planning mode: only annotated read-only tools plus AskUserQuestion
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_all(),
  permissions = permissions_plan()
)
```

When both are set, `tool_denylist` takes precedence over
`tool_allowlist`. `permission_prompt_tool_name` is allowed as an
approval escape hatch except in `dontAsk` mode, and is included in deny
messages when prompting is enabled. `permissions_plan()` mirrors
Claude’s `plan` mode by allowing only read-only annotated tools and
`AskUserQuestion`.

### Run Budgets and File Rewind

Limits are scoped to one run, so resuming an older conversation does not
inherit an already-spent budget:

``` r
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_file(),
  usage_limits = UsageLimits(
    max_requests = 12,
    max_tool_calls = 20,
    max_total_tokens = 50000,
    max_cost_usd = 1
  )
)

result <- agent$run_sync("Inspect this package")
result$run_id
result$usage
result$tool_calls()
result$tool_results()
```

Request and tool-call limits are checked at model and tool boundaries.
Token and cost limits use usage reported after a model response, so a
run stops once an overage is observed and can exceed the configured
threshold by one response.

Enable reversible file journals when an agent may edit its workspace:

``` r
agent <- Agent$new(
  chat = ellmer::chat("anthropic"),
  tools = tools_file(),
  enable_file_checkpointing = TRUE,
  working_dir = getwd()
)

checkpoint_id <- agent$checkpoint("before refactor")
agent$run_sync("Refactor R/parser.R")
agent$rewind_files(checkpoint_id)
```

Deputy automatically creates a checkpoint at the beginning of each run
and persists the journal with session snapshots. Captures default to 50
MiB per file. The default maximum aggregate serialized checkpoint-state
size is 250 MiB, counting journal records, checkpoint markers, metadata,
and pending captures. The bounds apply to live captures and restored
session state; violations signal `deputy_file_checkpoint_limit_error`.
Lead agents and their delegated agents share one workspace journal, so
child-agent edits participate in lead-level rewind. Rewind covers writes
through native and Agent SDK-compatible write, edit, multi-edit, and
todo tools; it does not capture writes performed by Bash, R code, or
arbitrary custom tools.

### Hooks

Intercept agent behavior:

``` r
# Log all tool calls
agent$add_hook(HookMatcher$new(
  event = "PostToolUse",
  callback = function(tool_name, tool_result, tool_error, context) {
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

### Skills

Skills bundle tools and prompt extensions. You can load them from disk
or create them programmatically. deputy ships with a built-in example
skill under `inst/skills`.

``` r
# Discover bundled skills
skills_dir <- system.file("skills", package = "deputy")
skills_list(skills_dir)

# Load a skill by path
agent$load_skill(file.path(skills_dir, "data_analysis"))

# Inspect loaded skills
agent$skills()

# Create and load a skill programmatically
custom <- skill_create(
  name = "my_skill",
  description = "Custom helpers",
  prompt = "You are a focused assistant for project-specific tasks."
)
agent$load_skill(custom)
```

### Claude Settings (settingSources)

deputy can load Claude-style settings from `.claude` directories,
including `CLAUDE.md` memory, `.claude/skills`, `.claude/commands` slash
commands, and `.claude/agents` definitions. Tool policy settings from
`settings.json` are also applied to `agent$permissions` (`allowedTools`,
`disallowedTools`, and `permissionPromptToolName`).

``` r
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = tools_file(),
  setting_sources = c("user", "project", "local")
)

# Inspect loaded slash commands
agent$slash_commands()
```

Settings-defined agents are applied automatically when you use
`LeadAgent$new(setting_sources = ...)` or the compatibility client.
Source precedence is fixed as `user`, then `project`, then `local`, with
`.claude/settings.local.json` overriding the broader settings files
without loading extra memory, commands, skills, or agents.

Unsupported `.claude/agents` frontmatter fields are warned on and
ignored. Plugin discovery and marketplace execution are intentionally
deferred from the current compatibility surface.

Example `.claude/settings.json` tool policy:

``` json
{
  "allowedTools": ["read_file", "list_files", "run_r_code"],
  "disallowedTools": ["run_bash"],
  "permissionPromptToolName": "AskUserQuestion"
}
```

### Structured Output

Request JSON output that matches a schema:

``` r
schema <- list(
  type = "object",
  properties = list(status = list(type = "string")),
  required = list("status")
)

result <- agent$run_sync(
  "Respond with status = ok",
  output_format = list(type = "json_schema", schema = schema)
)

result$structured_output
```

### Error Handling

deputy provides structured error types for programmatic error handling:

``` r
# Catch specific error types
tryCatch(
  agent$run_sync(
    "task",
    usage_limits = UsageLimits(max_cost_usd = 0.50, on_exceed = "error")
  ),
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

Direct synchronous child usage is aggregated into `result$usage`. Each
child inherits the lead run’s remaining budget, and the lead enforces
its limits after delegation. Parallel, background, transitive
child-tree, and cross-run global budget accounting remain future work.

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
- `vignette("claude-sdk-parity")` - Anthropic-compatible surface area
  and gaps
- [ellmer documentation](https://ellmer.tidyverse.org/) - Underlying LLM
  framework

## License

MIT
