# CLAUDE.md

This file provides guidance for AI assistants working with the deputy codebase.

## Project Overview

**deputy** is a provider-agnostic R runtime for building agentic workflows on
the [ellmer](https://ellmer.tidyverse.org/) LLM framework. Its native `Agent`
and `LeadAgent` APIs are the only supported runtime surface.

Key capabilities:
- Multi-step AI reasoning with tool use
- Fine-grained permission system with tool annotations
- Hook-based lifecycle event interception
- Human-in-the-loop via `tool_ask_user`
- Multi-agent delegation (LeadAgent)
- Explicit session persistence through `Agent$save_session()` and
  `Agent$load_session()`
- Streaming output support

## Directory Structure

```
deputy/
├── R/                      # Source code (R6 classes and functions)
│   ├── agent.R             # Agent class - main agentic workflow engine
│   ├── agents-multi.R      # LeadAgent for multi-agent orchestration
│   ├── agent-definition-files.R # Portable YAML AgentDefinitions
│   ├── agent-result.R      # AgentResult and AgentEvent objects
│   ├── run-usage.R         # Run accounting and fail-closed limits
│   ├── stall-detection.R   # Canonical repeated-tool progress signal
│   ├── permissions.R       # Permission system and tool annotations
│   ├── hooks.R             # HookRegistry for lifecycle events
│   ├── skills.R            # Skill loading system
│   ├── tools-builtin.R     # Built-in tools (read_file, write_file, etc.)
│   ├── tools-bundles.R     # Tool presets (minimal, standard, dev, data, full)
│   ├── tools-interactive.R # tool_ask_user for human-in-the-loop
│   ├── tools-mcp.R         # MCP discovery and sandboxed mcp-repl boundary
│   ├── errors.R            # Custom error hierarchy
│   └── utils.R             # Internal utilities
├── tests/testthat/         # Unit tests (testthat edition 3)
├── inst/skills/            # Built-in skills with YAML metadata
├── inst/examples/          # Runnable recipes, standalone scripts, and Shiny app
├── exec/deputy.R           # Terminal CLI using Rapp
├── vignettes/              # User documentation (R Markdown)
├── man/                    # Auto-generated roxygen2 docs
├── dev/agents/             # Agent skill configuration (issue tracker, labels, domain)
├── dev/adr/                # Architecture decision records
├── CONTEXT.md              # Domain glossary - use these terms in issues and docs
├── .claude/                # Claude Code environment setup
└── .github/workflows/      # CI/CD pipelines
```

> `docs/` is the generated pkgdown site and is gitignored. Hand-written docs for
> humans go in `vignettes/`; docs for agents go in `dev/`.

## Development Setup

### Remote (Claude Code Web)

The repository includes a SessionStart hook (`.claude/setup-r.sh`) that automatically installs R and Air when working in Claude Code web environments.

### Local

```bash
# Install dependencies
Rscript -e "devtools::install_deps(dependencies = TRUE)"

# Install the released dependency set used by CRAN and CI.
Rscript -e "pak::pak()"

# Load package for development
Rscript -e "devtools::load_all()"
```

The scripts in `inst/examples/standalone/` are executed by
`tests/testthat/test-standalone-examples.R` using deterministic provider responses.
Keep examples independent and use the public Agent APIs.

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

# Validate and build the pkgdown site
Rscript -e "pkgdown::check_pkgdown()"
Rscript -e "pkgdown::build_site()"
```

### Building

```bash
# Build package
Rscript -e "devtools::build()"

# Install locally
Rscript -e "devtools::install()"
```

### Versioning

deputy stays on `0.0.0.9xxx` until it is ready for CRAN.

- **Do not bump the major or minor version.** Not to `0.1.0`, not to mark a
  milestone, not to signal that a batch of work is done. A release number
  means "submitted to CRAN" and nothing else.
- **Do not add a release heading to `NEWS.md`.** New entries go under
  `# deputy (development version)`. A `# deputy 0.1.0` heading reads as a
  release announcement.
- Milestones carry direction; the version carries release state.

### Upstream dependencies

deputy's primary compatibility target is the released dependency set available
from CRAN; see `dev/adr/0004-track-upstream-development-versions.md`. Test
upstream development versions in focused compatibility work before raising a
minimum version or adopting an unreleased API.

## Code Conventions

### Style

- **Formatter**: Air (configuration in `air.toml`)
- **Documentation**: roxygen2 with markdown support
- **Classes**: R6 for complex objects (Agent, Permissions, HookRegistry, Skill)
- **Errors**: Signal with the `abort_*()` constructors in `R/errors.R` (e.g. `abort_permission_denied()`), never bare `stop()`
- **Messages**: All user-facing output goes through cli — `cli_abort()`, `cli_warn()`, `cli_inform()`, never `stop()`/`warning()`/`message()`

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
# Signalling: abort_*() constructors signal directly, so don't wrap in stop()
abort_permission_denied(
  "Write operations not allowed in {.val readonly} mode",
  tool_name = "write_file",
  permission_mode = "readonly"
)

# Catching: classes are prefixed with deputy_ and inherit from deputy_error
tryCatch(
  agent$run_sync(task),
  deputy_permission_denied = function(e) {
    cli::cli_alert_danger("Permission denied: {conditionMessage(e)}")
  },
  deputy_error = function(e) {
    cli::cli_alert_danger("Deputy error: {conditionMessage(e)}")
  }
)
```

Available constructors: `abort_deputy()`, `abort_permission_denied()`, `abort_tool_execution()`,
`abort_budget_exceeded()`, `abort_turn_limit()`, `abort_provider()`, `abort_session_load()`,
`abort_session_save()`, `abort_hook()`. Test membership with `is_deputy_error(x, class)`.

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

- `"standard"` - Check tools against configured capabilities
- `"plan"` - Allow constrained reads and a dedicated approval prompt
- `"readonly"` - Allow known reads within configured capabilities
- `"full"` - Allow all capabilities (dangerous)

Permissions configured at construction are an immutable authority ceiling.
`Agent$set_permission_mode()` may keep or narrow a policy but cannot widen it;
delegated agents are bounded by the same rule and by their lead's restrictions.

### AgentDefinition Routing

`agent_definition()` canonicalizes names to lowercase routing keys. A
`LeadAgent` keeps definitions in a private, uniquely keyed registry;
`sub_agent_defs` is a read-only snapshot, and new definitions must go through
`register_sub_agent()` so the registry and lead prompt stay synchronized.

`agent_definition_read()`, `agent_definition_write()`, and `agent_definitions()`
provide versioned Deputy YAML files, conventionally in `.deputy/agents/`.
Tools and skills resolve through explicit host registries; file loading never
sources R code, loads skills, or connects services. See ADR-0006 and the
Multi-Agent vignette for the format and authoring examples.

### Human Input

Concurrent and hosted Agents bind their own handler with
`tools_interactive(callback, context)`. The context carries stable routing
values and may be resolved lazily. `set_ask_user_callback()` is only a legacy
process-wide fallback for single-Agent scripts; do not use it for Shiny or
other concurrent hosts.

### Tool Presets

- `tools_preset("minimal")` - read_file, list_files
- `tools_preset("standard")` - + write_file; no code execution
- `tools_preset("dev")` - + trusted run_r_code and run_bash
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
| `R/agent.R` | Main Agent class with run/run_sync/run_shiny |
| `R/permissions.R` | Permission system and tool annotations |
| `R/hooks.R` | HookRegistry and event system |
| `R/tools-builtin.R` | Built-in tools implementation |
| `exec/deputy.R` | CLI application using Rapp |
| `tests/testthat/helper-mocks.R` | Mock objects for testing |

## Dependencies

**Core** (in Imports):
- `ellmer` (>= 0.3.0) - LLM abstraction layer
- `R6` - Object-oriented programming
- `cli` - CLI formatting
- `rlang` - Language utilities
- `coro` - Coroutines for streaming
- `digest` - Hashing
- `Rapp` (>= 0.4.0) - CLI framework
- `callr` - Fault isolation and timeouts for explicitly trusted R code
- `mcp-repl` (optional, through mcptools) - OS-sandboxed model-generated R;
  `tools_mcp_repl()` verifies an explicit fail-closed policy before loading it

**Development** (in Suggests):
- `testthat` (>= 3.0.0) - Testing
- `knitr` - Vignettes

**Shiny Integration** (in Suggests):
- `promises` - Async support for `run_shiny()`
- `shiny` - Shiny framework
- `shinychat` - Chat UI component

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `JamesHWade/deputy`, managed with the `gh` CLI. See `dev/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles use their default label strings. See `dev/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` at the root, ADRs in `dev/adr/`. See `dev/agents/domain.md`.

## Issue Tracking

Issues live in GitHub Issues. Use the `gh` CLI.

```bash
# Finding work
gh issue list --state open                       # All open issues
gh issue list --state open --label ready-for-agent
gh issue view <number> --comments                # Detailed view

# Working on issues
gh issue edit <number> --add-assignee @me        # Claim work
gh issue close <number> --comment "Fixed in #<pr>"

# Creating issues (always include a body with context)
gh issue create --title "Fix bug" --body "Details here" --label bug
```

Use a heredoc for multi-line bodies:

```bash
gh issue create --title "..." --body "$(cat <<'BODY'
## Problem
...

## Proposed fix
...
BODY
)"
```

### Tracking Work

Use GitHub Issues for work that must persist across sessions, has dependencies,
or needs a handoff. Transient personal notes do not replace the issue record.

## Feature Branch + PR Workflow

> **⚠️ All changes must go through Pull Requests.** Never commit directly to main. Create a feature branch, make your changes, and open a PR for review.

### Before Creating a PR

**IMPORTANT**: Review and update CLAUDE.md if your changes affect:
- New directories or files that should be documented
- New code conventions or patterns
- New commands or workflows
- Changes to architecture or dependencies

### 1. Find Work and Create Feature Branch

**⚠️ IMPORTANT: Create the feature branch BEFORE claiming the issue or writing any code.**

```bash
gh issue list --state open            # Find available work
gh issue view <number>                # Review issue details

# CREATE BRANCH FIRST - before any code changes!
git checkout -b feature/<short-description>
# or: git checkout -b fix/<short-description>

gh issue edit <number> --add-assignee @me   # Now claim the work
```

### 2. Run Quality Gates

```bash
# Format ALL code with air (R/ and tests/)
air format R/ tests/testthat/

# Lint with jarl
jarl check R/

# Run tests
Rscript -e "devtools::test()"

# Run R CMD check
Rscript -e "devtools::check()"

# Build pkgdown site
Rscript -e "devtools::document(); pkgdown::build_site(preview = FALSE)"
```

### 3. Create PR

```bash
git add .
git commit -m "feat: description (#<issue-number>)"   # Reference the issue!
git push -u origin HEAD
gh pr create --title "..." --body "Closes #<issue-number>"
```

Putting `Closes #<n>` in the PR body lets GitHub close the issue automatically when the PR merges. Don't close the issue by hand.

### 4. Human Reviews and Merges PR

Agents create PRs but **do not merge them**. Humans review and merge PRs to main.

### 5. After PR Merged (Cleanup)

```bash
git checkout main
git pull
git branch -d feature/<short-description>
```

Or use:
```r
usethis::pr_finish()
```

## Session Completion Protocol

**CRITICAL**: Before ending a session, complete ALL steps. Work is NOT complete until `git push` succeeds.

```bash
# 1. Verify you're on a feature branch (NOT main!)
git branch --show-current  # Should NOT be 'main'

# 2. File issues for remaining work
gh issue create --title "Follow-up task" --body "..."

# 3. Run quality gates (if code changed)
air format R/ tests/testthat/
jarl check R/
Rscript -e "devtools::check()"

# 4. Commit referencing the issue
git add .
git commit -m "feat: description (#<issue-number>)"
git push -u origin HEAD

# 5. Create PR (if not already created)
gh pr create --title "..." --body "Closes #<issue-number>"

# 6. Verify
git status  # Should show "up to date with origin"
```

### Critical Rules

- **NEVER commit directly to main** - always use feature branches
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing—that leaves work stranded locally
- NEVER say "ready to push when you are"—YOU must push
- If push fails, resolve and retry until it succeeds
- Always reference the issue number in commit messages and PR bodies

## Parallel Sessions & Worktrees

This project supports parallel work via git worktrees.

```bash
# From main repo, create worktree for a feature
git worktree add ../deputy-feature-x -b feature/feature-x
cd ../deputy-feature-x
```

### Cleanup After PR Merged

```bash
git worktree remove ../deputy-feature-x
git worktree prune
```

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- `R-CMD-check.yaml` - Package check on multiple platforms
- `test-coverage.yaml` - Code coverage to codecov
- `pkgdown.yaml` - Documentation site
- `format-suggest.yaml` - Code formatting suggestions
- `claude.yml` / `claude-code-review.yml` - Claude integration

The automatic Claude review workflow runs only for PR branches in this
repository. Fork PRs receive an explicit skip explanation in the workflow
summary and require maintainer review; their ordinary CI still runs. The fork
notice has no token permissions, checkout, or secrets. Keep this workflow on
`pull_request`; do not use a privileged fork checkout to bypass authentication
restrictions. This policy applies to automatic review, not the separate
mention-triggered Claude workflow.
