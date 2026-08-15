# Changelog

## deputy (development version)

- The `deputy` command now ships as a tested Rapp 0.4 package executable
  for one-off `rx` use and persistent `ir tool install` launchers. Its
  task and interactive modes now consume streaming generators correctly,
  report tool failures, and restore persisted sessions from an installed
  package.

- `Agent$provider()` no longer errors with “Can’t get S7 properties with
  `$`” against current ellmer. ellmer moved `model` off `Provider` onto
  a new `Model` class, so `provider@model` fails for every provider and
  the `$` fallback threw from inside the error handler. The model is now
  read with `Chat$get_model()`.

## deputy 0.0.0.9000

- Added semantic content streaming with `tool_start`, `tool_end`,
  `usage`, and `file_checkpoint` events, stable run IDs, cooperative
  `Agent$interrupt()`, and run usage on `AgentResult`.
- Added
  [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  and
  [`AgentUsage()`](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  for per-run request, tool-call, input/output/total-token, and
  estimated-cost accounting and enforcement, including remaining-budget
  inheritance and aggregation for synchronous delegated agents.
- Added persisted, bounded byte-exact file checkpoints and rewind
  through `Agent` and `AgentSDKClient` for native and SDK-compatible
  write/edit tools; lead and delegated agents share one workspace
  journal. Serialized state is size-bounded and restores are
  root-validated and transactional.
- Hardened permission checks so native and SDK tool aliases share policy
  IDs, all mutating file tools enforce configured roots, and readonly
  mode fails closed for unknown, write/edit/multi-edit/todo,
  destructive, and disallowed open-world tools. Constructor permissions,
  workspace roots, and tools remain authoritative when sessions resume
  unless serialized tools are explicitly trusted.
- Post-tool hook output replacement and suppression now apply to emitted
  tool lifecycle events; interrupting permission denials stop active
  streams.
- Added lazy, cancellable `run_shiny()` lifecycle management with the
  Agent’s run limits, file-root confinement, automatic checkpoints, and
  incomplete-tool recovery; active runs now reject conflicting session,
  rewind, and compaction mutations.
- Added external and in-memory session-store adapters, MCP status
  reporting, richer sub-agent run metadata, and an evidence-backed Agent
  SDK parity inventory with remaining gaps documented explicitly.
- Initial development version
- Core `Agent` class with streaming `run()` and blocking `run_sync()`
  methods
- Built-in tools: `tool_read_file`, `tool_write_file`,
  `tool_list_files`, `tool_run_r_code`, `tool_run_bash`, `tool_read_csv`
- Tool bundles:
  [`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md),
  [`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md),
  [`tools_data()`](https://jameshwade.github.io/deputy/reference/tools_data.md),
  [`tools_all()`](https://jameshwade.github.io/deputy/reference/tools_all.md)
- Permission system with
  [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md),
  [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md),
  [`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md),
  and custom `Permissions` class
- Hook system with `HookMatcher`, `HookRegistry`, and events:
  `PreToolUse`, `PostToolUse`, `Stop`, `UserPromptSubmit`, `PreCompact`
- Multi-agent support with
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  and `LeadAgent`
- Skills system with
  [`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md),
  [`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md),
  and `Skill` class
- Session persistence via `save_session()` and `load_session()`
- Provider-agnostic design works with any ellmer-supported LLM
