# CLAUDE.md

This file provides guidance for AI assistants working with the deputy
codebase.

## Project Overview

**deputy** is an R package implementing Anthropic’s Claude Agent SDK
patterns. It provides a provider-agnostic framework for building agentic
AI workflows in R, built on the [ellmer](https://ellmer.tidyverse.org/)
LLM framework.

Key capabilities: - Multi-step AI reasoning with tool use - Fine-grained
permission system with tool annotations - Hook-based lifecycle event
interception - Human-in-the-loop via `tool_ask_user` - Multi-agent
delegation (LeadAgent) - Session persistence - Streaming output support

## Directory Structure

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

## Development Setup

### Remote (Claude Code Web)

The repository includes a SessionStart hook (`.claude/setup-r.sh`) that
automatically installs R and Air when working in Claude Code web
environments.

### Local

``` bash
# Install dependencies
Rscript -e "devtools::install_deps(dependencies = TRUE)"

# Load package for development
Rscript -e "devtools::load_all()"
```

## Common Commands

### Testing

``` bash
# Run all tests
Rscript -e "devtools::test()"

# Run specific test file
Rscript -e "testthat::test_file('tests/testthat/test-agent.R')"

# Run tests with filter
Rscript -e "devtools::test(filter = 'permissions')"
```

### Code Quality

``` bash
# Check package (runs R CMD check)
Rscript -e "devtools::check()"

# Format code with Air
air format R/

# Generate documentation
Rscript -e "devtools::document()"
```

### Building

``` bash
# Build package
Rscript -e "devtools::build()"

# Install locally
Rscript -e "devtools::install()"
```

## Code Conventions

### Style

- **Formatter**: Air (configuration in `air.toml`)
- **Documentation**: roxygen2 with markdown support
- **Classes**: R6 for complex objects (Agent, Permissions, HookRegistry,
  Skill)
- **Errors**: Use custom error classes from `R/errors.R` (e.g.,
  `deputy_error_permission_denied`)

### R6 Class Pattern

``` r
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

``` r
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

``` r
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

``` r
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

1.  **Agent** wraps an ellmer Chat object
2.  User calls `agent$run(task)` (streaming) or `agent$run_sync(task)`
    (blocking)
3.  Agent sends task to LLM via ellmer
4.  LLM may request tool calls
5.  **Permissions** check tool annotations and policy
6.  **HookRegistry** fires PreToolUse/PostToolUse events
7.  Tool executes and returns result
8.  Loop continues until LLM stops or limits reached

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

| File                            | Purpose                                |
|---------------------------------|----------------------------------------|
| `R/agent.R`                     | Main Agent class with run/run_sync     |
| `R/permissions.R`               | Permission system and tool annotations |
| `R/hooks.R`                     | HookRegistry and event system          |
| `R/tools-builtin.R`             | Built-in tools implementation          |
| `exec/deputy`                   | CLI application using Rapp             |
| `tests/testthat/helper-mocks.R` | Mock objects for testing               |

## Dependencies

**Core** (in Imports): - `ellmer` (\>= 0.3.0) - LLM abstraction layer -
`R6` - Object-oriented programming - `cli` - CLI formatting - `rlang` -
Language utilities - `coro` - Coroutines for streaming - `digest` -
Hashing

**Development** (in Suggests): - `testthat` (\>= 3.0.0) - Testing -
`Rapp` - CLI framework - `knitr` - Vignettes

## Issue Tracking with Beads

This project uses **bd** (beads) for issue tracking. Issues are stored
in `.beads/` and synced via git.

### Git Integration

Beads integrates with git via: - **JSONL sync**: Issues stored in
`.beads/issues.jsonl` (git-tracked) - **Merge driver**: Intelligent
JSONL conflict resolution (auto-configured) - **Hooks**: Auto-sync on
git operations

Files that should be committed: `.beads/.gitignore`, `.gitattributes`
Files that are gitignored: `.beads/beads.db`, daemon files

### Essential Commands

``` bash
# Finding work
bd ready                              # Show issues ready to work (no blockers)
bd list --status=open                 # All open issues
bd show <id>                          # Detailed issue view with dependencies

# Working on issues
bd update <id> --status=in_progress   # Claim work
bd close <id>                         # Mark complete
bd close <id1> <id2> ...              # Close multiple issues

# Creating issues (always include description for context)
bd create "Fix bug" --description="Details here" -t bug -p 1

# Dependencies
bd dep add <issue> <depends-on>       # Add dependency
bd blocked                            # Show blocked issues
bd dep tree <id>                      # View dependency tree

# Sync
bd sync                               # Sync with git remote
bd sync --status                      # Check sync status
```

### When to Use Beads vs TodoWrite

| Use **Beads (`bd`)** for         | Use **TodoWrite** for        |
|----------------------------------|------------------------------|
| Multi-session work               | Single-session execution     |
| Work with dependencies           | Simple task checklists       |
| Discovered work needing tracking | Immediate step-by-step tasks |
| Collaborative/handed-off work    | Personal progress tracking   |

When in doubt, prefer beads—persistence you don’t need beats lost
context.

## Feature Branch + PR Workflow

> **⚠️ All changes must go through Pull Requests.** Never commit
> directly to main. Create a feature branch, make your changes, and open
> a PR for review.

### Before Creating a PR

**IMPORTANT**: Review and update CLAUDE.md if your changes affect: - New
directories or files that should be documented - New code conventions or
patterns - New commands or workflows - Changes to architecture or
dependencies

### 1. Find Work and Create Feature Branch

**⚠️ IMPORTANT: Create the feature branch BEFORE claiming the issue or
writing any code.**

``` bash
bd ready                              # Find available work
bd show <id>                          # Review issue details

# CREATE BRANCH FIRST - before any code changes!
git checkout -b feature/<short-description>
# or: git checkout -b fix/<short-description>

bd update <id> --status=in_progress   # Now claim the work
```

### 2. Work and Sync

``` bash
# Make changes...
bd sync                               # Sync beads periodically
```

### 3. Run Quality Gates

``` bash
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

### 4. Create PR and Close Issue

When code is complete and ready for review:

``` bash
git add .
git commit -m "feat: description (deputy-xxx)"  # Include beads issue ID!
bd close <id>                         # Close beads issue - work is done
bd sync
git push -u origin HEAD
gh pr create --title "..." --body "Resolves deputy-XXX"
```

**Important**: Close the beads issue when the *work* is complete, not
when the PR is merged. The issue tracks your work; the PR tracks the
review/merge process.

### 5. Human Reviews and Merges PR

Agents create PRs but **do not merge them**. Humans review and merge PRs
to main.

### 6. After PR Merged (Cleanup)

``` bash
git checkout main
git pull
git branch -d feature/<short-description>
```

Or use:

``` r
usethis::pr_finish()
```

## Session Completion Protocol

**CRITICAL**: Before ending a session, complete ALL steps. Work is NOT
complete until `git push` succeeds.

### Mandatory Checklist (Feature Branch Workflow)

``` bash
# 1. Verify you're on a feature branch (NOT main!)
git branch --show-current  # Should NOT be 'main'

# 2. File issues for remaining work
bd create "Follow-up task" --description="..." -t task -p 2

# 3. Run quality gates (if code changed)
air format R/ tests/testthat/
jarl check R/
Rscript -e "devtools::check()"

# 4. Update issue status
bd close <completed-issues>           # Include reason if helpful
bd update <in-progress-issues> --status=open  # If not finished

# 5. Commit with beads issue ID
git add .
git commit -m "feat: description (deputy-xxx)"  # Always include issue ID!
bd sync
git push -u origin HEAD

# 6. Create PR (if not already created)
gh pr create --title "..." --body "Resolves deputy-xxx"

# 7. Verify
git status  # Should show "up to date with origin"
```

### Critical Rules

- **NEVER commit directly to main** - always use feature branches
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing—that leaves work stranded locally
- NEVER say “ready to push when you are”—YOU must push
- If push fails, resolve and retry until it succeeds
- Always run `bd sync` before ending session
- Always include beads issue ID in commit messages (enables `bd doctor`
  to detect orphans)

## Parallel Sessions & Worktrees

This project supports parallel work via git worktrees. The beads daemon
commits changes to a dedicated branch, preventing conflicts when
multiple Claude sessions run simultaneously.

### Creating Worktrees for Parallel Features

``` bash
# From main repo, create worktree for a feature
git worktree add ../deputy-feature-x -b feature/feature-x
cd ../deputy-feature-x

# Beads commands work normally - shared database, safe daemon
bd ready
bd create "Implement feature" -t task -p 2
bd sync
```

All worktrees share the same `.beads` database in the main repo. Changes
are immediately visible across sessions.

### Cleanup After PR Merged

``` bash
git worktree remove ../deputy-feature-x
git worktree prune
```

### Troubleshooting: “Branch already checked out”

If git says a branch is checked out in a beads worktree:

``` bash
rm -rf .git/beads-worktrees
git worktree prune
```

## CI/CD

GitHub Actions workflows in `.github/workflows/`: - `R-CMD-check.yaml` -
Package check on multiple platforms - `test-coverage.yaml` - Code
coverage to codecov - `pkgdown.yaml` - Documentation site -
`format-suggest.yaml` - Code formatting suggestions - `claude.yml` /
`claude-code-review.yml` - Claude integration
