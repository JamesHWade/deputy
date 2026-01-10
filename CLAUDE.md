# CLAUDE.md

This file provides guidance for AI assistants working with the deputy codebase.

## Project Overview

**deputy** is an R package implementing Anthropic's Claude Agent SDK patterns. It provides a provider-agnostic framework for building agentic AI workflows in R, built on the [ellmer](https://ellmer.tidyverse.org/) LLM framework.

Key capabilities:
- Multi-step AI reasoning with tool use
- Fine-grained permission system with tool annotations
- Hook-based lifecycle event interception
- Human-in-the-loop via `tool_ask_user`
- Multi-agent delegation (LeadAgent)
- Session persistence
- Streaming output support

## Directory Structure

```
deputy/
├── R/                      # Source code (R6 classes and functions)
│   ├── agent.R             # Agent class - main agentic workflow engine
│   ├── agents-multi.R      # LeadAgent for multi-agent orchestration
│   ├── agent-result.R      # AgentResult and AgentEvent objects
│   ├── permissions.R       # Permission system and tool annotations
│   ├── hooks.R             # HookRegistry for lifecycle events
│   ├── skills.R            # Skill loading system
│   ├── tools-builtin.R     # Built-in tools (read_file, write_file, etc.)
│   ├── tools-bundles.R     # Tool presets (minimal, standard, dev, data, full)
│   ├── tools-interactive.R # tool_ask_user for human-in-the-loop
│   ├── errors.R            # Custom error hierarchy
│   └── utils.R             # Internal utilities
├── tests/testthat/         # Unit tests (testthat edition 3)
├── inst/skills/            # Built-in skills with YAML metadata
├── exec/deputy             # Terminal CLI using Rapp
├── vignettes/              # User documentation (R Markdown)
├── man/                    # Auto-generated roxygen2 docs
├── .claude/                # Claude Code environment setup
└── .github/workflows/      # CI/CD pipelines
```

## Development Setup

### Remote (Claude Code Web)

The repository includes a SessionStart hook (`.claude/setup-r.sh`) that automatically installs R and Air when working in Claude Code web environments.

### Local

```bash
# Install dependencies
Rscript -e "devtools::install_deps(dependencies = TRUE)"

# Load package for development
Rscript -e "devtools::load_all()"
```

## Common Commands

### Testing

```bash
# Run all tests
Rscript -e "devtools::test()"

# Run specific test file
Rscript -e "testthat::test_file('tests/testthat/test-agent.R')"

# Run tests with filter
Rscript -e "devtools::test(filter = 'permissions')"
```

### Code Quality

```bash
# Check package (runs R CMD check)
Rscript -e "devtools::check()"

# Format code with Air
air format R/

# Generate documentation
Rscript -e "devtools::document()"
```

### Building

```bash
# Build package
Rscript -e "devtools::build()"

# Install locally
Rscript -e "devtools::install()"
```

## Code Conventions

### Style

- **Formatter**: Air (configuration in `air.toml`)
- **Documentation**: roxygen2 with markdown support
- **Classes**: R6 for complex objects (Agent, Permissions, HookRegistry, Skill)
- **Errors**: Use custom error classes from `R/errors.R` (e.g., `deputy_error_permission_denied`)

### R6 Class Pattern

```r
ClassName <- R6::R6Class(
  "ClassName",
  public = list(
    field = NULL,

    initialize = function(param) {
      # Validation
      # Assignment
      invisible(self)
    },

    method = function() {
      # Implementation
    }
  ),
  private = list(
    helper = function() {
      # Private helper
    }
  )
)
```

### Tool Creation Pattern

```r
#' Tool description
#' @export
tool_name <- ellmer::tool(
  fun = function(param) {
    # Implementation
  },
  name = "tool_name",
  description = "What this tool does",
  arguments = list(
    param = ellmer::type_string("Parameter description")
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,      # Doesn't modify state
    destructive_hint = FALSE,   # Not destructive
    open_world_hint = FALSE,    # No external systems
    idempotent_hint = TRUE      # Safe to retry
  )
)
```

### Error Handling

```r
# Use custom error constructors
stop(deputy_error_permission_denied(
  tool_name = "write_file",
  reason = "Write operations not allowed in readonly mode"
))

# Catching errors
tryCatch(
  agent$run_sync(task),
  deputy_error_permission_denied = function(e) {
    cli::cli_alert_danger("Permission denied: {e$message}")
  }
)
```

### Testing Pattern

```r
test_that("descriptive test name", {
  # Setup - use mocks from helper-mocks.R
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Exercise
  result <- agent$run_sync("task")

  # Verify

  expect_s3_class(result, "AgentResult")
  expect_equal(result$stop_reason, "end_turn")
})
```

## Architecture

### Core Flow

1. **Agent** wraps an ellmer Chat object
2. User calls `agent$run(task)` (streaming) or `agent$run_sync(task)` (blocking)
3. Agent sends task to LLM via ellmer
4. LLM may request tool calls
5. **Permissions** check tool annotations and policy
6. **HookRegistry** fires PreToolUse/PostToolUse events
7. Tool executes and returns result
8. Loop continues until LLM stops or limits reached

### Permission Modes

- `"default"` - Check each tool against policy
- `"readonly"` - Only allow read_only_hint tools
- `"acceptEdits"` - Auto-accept file writes
- `"bypassPermissions"` - Allow everything (dangerous)

### Tool Presets

- `tools_preset("minimal")` - read_file, list_files
- `tools_preset("standard")` - + write_file, run_r_code
- `tools_preset("dev")` - + run_bash
- `tools_preset("data")` - read_file, list_files, read_csv, run_r_code
- `tools_preset("full")` - all built-in tools

### Hook Events

- `PreToolUse` / `PostToolUse` - Before/after tool execution
- `Stop` - When agent finishes
- `SessionStart` / `SessionEnd` - Session lifecycle
- `PreCompact` - Before conversation compaction
- `SubagentStop` - When delegated agent finishes
- `UserPromptSubmit` - When user submits input (CLI)

## Key Files for Understanding

| File | Purpose |
|------|---------|
| `R/agent.R` | Main Agent class with run/run_sync |
| `R/permissions.R` | Permission system and tool annotations |
| `R/hooks.R` | HookRegistry and event system |
| `R/tools-builtin.R` | Built-in tools implementation |
| `exec/deputy` | CLI application using Rapp |
| `tests/testthat/helper-mocks.R` | Mock objects for testing |

## Dependencies

**Core** (in Imports):
- `ellmer` (>= 0.3.0) - LLM abstraction layer
- `R6` - Object-oriented programming
- `cli` - CLI formatting
- `rlang` - Language utilities
- `coro` - Coroutines for streaming
- `digest` - Hashing

**Development** (in Suggests):
- `testthat` (>= 3.0.0) - Testing
- `Rapp` - CLI framework
- `knitr` - Vignettes

## Issue Tracking

This project uses **beads (bd)** for issue tracking. See `AGENTS.md` for workflow details.

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress
bd close <id>
bd sync               # Sync with git
```

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- `R-CMD-check.yaml` - Package check on multiple platforms
- `test-coverage.yaml` - Code coverage to codecov
- `pkgdown.yaml` - Documentation site
- `format-suggest.yaml` - Code formatting suggestions
- `claude.yml` / `claude-code-review.yml` - Claude integration
