# Changelog

## deputy (development version)

- New `Agent$run_async()` runs a task without blocking the R process and
  returns a promise that resolves to an `AgentResult`. It shares
  `run_shiny()`’s engine – ellmer’s `stream_async()` with permissions,
  hooks, and `UsageLimits` enforced through callbacks and terminal
  accounting – but collects the final response, run-scoped usage, and
  stop reason instead of streaming to a UI, accepts a per-run
  `UsageLimits` override (including `on_exceed = "error"`, which rejects
  the promise with the structured limit error), and does not impose
  `run_shiny()`’s absolute-file-path rule. Use it when an Agent is a
  worker inside a larger async system, such as a sub-agent invoked from
  a streaming parent chat’s tool. Callback-driven runs now also record
  their run-scoped usage so `AgentResult$usage` and the Agent’s last run
  usage reflect `run_shiny()`/`run_async()` runs.

- The `deputy` command now ships as a tested Rapp 0.4 package executable
  for one-off `rx` use and persistent `ir tool install` launchers. Its
  task and interactive modes now consume streaming generators correctly,
  report tool failures, and restore persisted sessions from an installed
  package.

- `Agent$new()` and per-run methods now accept immutable, canonical
  JSON-compatible `run_context`. Results, hooks, saved sessions, and
  delegated agents retain that context, while paired tool events and
  delegated results expose Agent, run, parent, tool-call, and delegation
  identifiers. Generated correlation identifiers no longer advance R’s
  global RNG stream.

- Deputy now has a deliberate 51-symbol public API centered on native
  agents, tools, permissions, hooks, skills, delegation, and run usage.
  Sessions use a stable `session_id` for correlation and explicit
  `Agent$save_session()` and `Agent$load_session()` calls for
  persistence.

- Removed the pre-release Agent SDK/Claude facades, Claude settings
  loader, automatic session stores, vendor tool and permission aliases,
  deprecated run arguments, todo tools, and redundant convenience
  exports. Saved sessions and file-checkpoint journals now use strict
  native schemas; unsupported earlier payloads are rejected rather than
  migrated.

- `Agent$provider()` no longer errors with “Can’t get S7 properties with
  `$`” against current ellmer. ellmer moved `model` off `Provider` onto
  a new `Model` class, so `provider@model` fails for every provider and
  the `$` fallback threw from inside the error handler. The model is now
  read with `Chat$get_model()`.

- `Agent$set_permission_mode()` now preserves constructor permissions as
  an immutable authority ceiling. Reapplying the current mode is a
  no-op; other changes may only narrow authority. Delegated agents use
  the same rule and retain lead capability, tool-gate, callback, and
  write-root restrictions.

- `compact()` now summarizes on a clone of the agent’s own chat instead
  of constructing a new provider. Previously any provider other than
  OpenAI, Anthropic, or Google fell through to
  `ellmer::chat_openai("gpt-4o-mini")`, sending conversation history to
  OpenAI when `OPENAI_API_KEY` happened to be set. The summary clone
  preserves configured provider behavior while removing tools and
  callbacks and suppressing console echo.

- [`tool_run_r_code()`](https://jameshwade.github.io/deputy/reference/tool_run_r_code.md)
  now rejects timed-out or failed `callr` subprocesses with readable
  tool errors instead of failing later while formatting an unbound
  result ([\#27](https://github.com/JamesHWade/deputy/issues/27)).

## deputy 0.0.0.9000

- Added semantic content streaming with `tool_start`, `tool_end`,
  `usage`, and `file_checkpoint` events, stable run IDs, cooperative
  `Agent$interrupt()`, and run usage on `AgentResult`.
- Added
  [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  and
  [`AgentUsage()`](https://jameshwade.github.io/deputy/reference/AgentUsage.md)
  for per-run request, tool-call, input/output/total-token, and
  estimated-cost accounting and enforcement, including remaining-limit
  inheritance and aggregation for synchronous delegated agents.
- Added persisted, bounded byte-exact file checkpoints and rewind
  through `Agent` for Deputy write and edit tools; lead and delegated
  agents share one workspace journal. Serialized state is size-bounded
  and loads are root-validated and transactional.
- Hardened permission checks so all mutating file tools enforce
  configured roots and readonly mode fails closed for unknown, mutating,
  destructive, and disallowed open-world tools. Constructor permissions,
  workspace roots, and tools remain authoritative when a saved
  conversation is loaded.
- Post-tool hook output replacement and suppression now apply to emitted
  tool lifecycle events; interrupting permission denials stop active
  streams.
- Added lazy, cancellable `run_shiny()` lifecycle management with the
  Agent’s run limits, file-root confinement, automatic checkpoints, and
  incomplete-tool recovery; active runs now reject conflicting load,
  rewind, and compaction mutations.
- Added MCP status reporting and richer sub-agent run metadata.
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
- Hook system with `HookMatcher` and events: `PreToolUse`,
  `PostToolUse`, `Stop`, `UserPromptSubmit`, `PreCompact`
- Multi-agent support with
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  and `LeadAgent`
- Skills system with
  [`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md),
  [`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md),
  and `Skill` class
- Explicit session persistence via `Agent$save_session()` and
  `Agent$load_session()`
- Provider-agnostic design works with any ellmer-supported LLM
