# Agent Instructions

See [CLAUDE.md](CLAUDE.md) for the full guide: project overview, code conventions, architecture, and the feature-branch + PR workflow.

## Quick Reference

Issues live in GitHub Issues (`JamesHWade/deputy`). Use the `gh` CLI.

```bash
gh issue list --state open                   # Find available work
gh issue view <number> --comments            # View issue details
gh issue edit <number> --add-assignee @me    # Claim work
gh issue create --title "..." --body "..."   # File new work
```

Agent skill configuration lives in `dev/agents/`.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

1. **File issues for remaining work** — `gh issue create` for anything that needs follow-up
2. **Run quality gates** (if code changed) — `air format R/ tests/testthat/`, `jarl check R/`, `devtools::test()`, `devtools::check()`
3. **Push to remote** — this is MANDATORY:
   ```bash
   git pull --rebase
   git push
   git status  # MUST show "up to date with origin"
   ```
4. **Open a PR** — `gh pr create --body "Closes #<issue-number>"`
5. **Clean up** — clear stashes, prune remote branches
6. **Hand off** — provide context for the next session

**CRITICAL RULES:**
- Never commit directly to `main` — always use a feature branch
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing — that leaves work stranded locally
- NEVER say "ready to push when you are" — YOU must push
- If push fails, resolve and retry until it succeeds
