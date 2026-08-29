# deputy (development version)

* `Agent` is now a governed, drop-in chat: `chat()`, `chat_async()`, `stream()`,
  `stream_async()`, `run_sync()`, and `run_async()` are adapters over one async
  run kernel. The public backend escape hatch and separate `run_shiny()` bridge
  are removed. shinychat can consume `agent$stream_async()` directly, including
  attachment content, while permissions, hooks, limits, checkpoints, and
  accounting remain active. `LeadAgent` delegation now uses `run_async()` and
  no longer blocks the R process.

* New `ContextPolicy()` enables automatic pre-request context compaction and
  durable offloading of large tool results. Compaction reports whether it used
  the LLM, a hook, or an explicitly configured text fallback, and includes its
  own usage. Version 2 saved sessions retain cumulative summaries and portable
  copies of offloaded results. Chunkable text sidecars keep model retrieval
  memory-bounded, and explicit relative offload roots remain stable after the
  policy is created. Native file and code tools execute against the Agent
  workspace without changing the R process working directory. Replacing turns
  clears Deputy-owned compacted conversation state while preserving other
  prompt content. Automatic compaction honors run limits before making its
  summary request. Prompt-owned routing and compaction boundaries cannot
  collide with ordinary user headings or summary text, and replacing a prompt
  resets hook-context de-duplication state.
  Loading a saved session transactionally replaces the receiver's active
  offloaded-result set, so results from an earlier conversation cannot leak
  into later session saves.
  `LeadAgent` accepts the same policy and propagates it to delegated agents.
  Prompt updates and sub-agent registration preserve cumulative compaction
  state, while post-tool hooks inspect the original result before large values
  are represented to the model by bounded references.

* Concurrent `LeadAgent` delegations reserve their child budgets before launch,
  so siblings share the lead's remaining usage limits instead of each receiving
  the full balance. Cloned lead agents also recreate their delegate tool against
  the clone's own registry, hooks, and run history.

* The `deputy` command now ships as a tested Rapp 0.4 package executable for
  one-off `rx` use and persistent `ir tool install` launchers. Its task and
  interactive modes now consume streaming generators correctly, report tool
  failures, and restore persisted sessions from an installed package.

* `Agent$new()` and per-run methods now accept immutable, canonical
  JSON-compatible `run_context`. Results, hooks, saved sessions, and
  delegated agents retain that context, while paired tool events and delegated
  results expose Agent, run, parent, tool-call, and delegation identifiers.
  Generated correlation identifiers no longer advance R's global RNG stream.

* Deputy now has a deliberate 52-symbol public API centered on native agents,
  tools, permissions, hooks, skills, delegation, and run usage. Sessions use a
  stable `session_id` for correlation and explicit `Agent$save_session()` and
  `Agent$load_session()` calls for persistence.

* Removed the pre-release Agent SDK/Claude facades, Claude settings loader,
  automatic session stores, vendor tool and permission aliases, deprecated run
  arguments, todo tools, and redundant convenience exports. Saved sessions and
  file-checkpoint journals now use strict native schemas; unsupported earlier
  payloads are rejected rather than migrated.

* `Agent$provider()` no longer errors with "Can't get S7 properties with `$`"
  against current ellmer. ellmer moved `model` off `Provider` onto a new `Model`
  class, so `provider@model` fails for every provider and the `$` fallback threw
  from inside the error handler. The model is now read with `Chat$get_model()`.

* `Agent$set_permission_mode()` now preserves constructor permissions as an
  immutable authority ceiling. Reapplying the current mode is a no-op; other
  changes may only narrow authority. Delegated agents use the same rule and
  retain lead capability, tool-gate, callback, and write-root restrictions.

* `agent_definition()` now validates and canonicalizes AgentDefinition routing
  keys and fields. `LeadAgent` rejects duplicate names and keeps its registry
  private behind a read-only snapshot, so delegation, displayed definitions,
  and the lead prompt cannot diverge (#79).

* `Agent` now rejects a provider tool request whose name is missing,
  unreadable, or malformed before it reaches usage accounting, permissions,
  hooks, or execution (#26).

* `hook_limit_file_writes()` now delegates path decisions to the canonical
  permission policy, rejects sibling-prefix and symlink escapes, and covers all
  native file mutation tools (#75).

* `HookMatcher$new()` now runs callbacks in the caller's process by default,
  validates timeout configuration at construction, and preserves detailed
  subprocess errors when isolated execution is explicitly requested. It also
  rejects callbacks that cannot accept an event's arguments and regex patterns
  that do not compile (#35, #36, #74).

* `Skill$check_requirements()` now treats malformed or unmatched provider names
  as mismatches while preserving compatibility when a skill and chat name the
  same generic provider. Internal provider normalization returns `NA` for
  unknown names as documented (#30).

* `compact()` now summarizes on a clone of the agent's own chat instead of
  constructing a new provider. Previously any provider other than OpenAI,
  Anthropic, or Google fell through to `ellmer::chat_openai("gpt-4o-mini")`,
  sending conversation history to OpenAI when `OPENAI_API_KEY` happened to be
  set. The summary clone preserves configured provider behavior while removing
  tools and callbacks and suppressing console echo.

* `tool_run_r_code()` now rejects timed-out or failed `callr` subprocesses with
  readable tool errors instead of failing later while formatting an unbound
  result (#27).

* `tools_interactive()` now creates an `ask_user` tool with an instance-scoped
  human-input handler and routing context, allowing concurrent Agents to remain
  isolated. Missing handlers signal `deputy_human_input_unavailable`;
  `set_ask_user_callback()` remains a legacy process-wide fallback (#76).

# deputy 0.0.0.9000

* Added semantic content streaming with `tool_start`, `tool_end`, `usage`, and
  `file_checkpoint` events, stable run IDs, cooperative `Agent$interrupt()`,
  and run usage on `AgentResult`.
* Added `UsageLimits()` and `AgentUsage()` for per-run request, tool-call,
  input/output/total-token, and estimated-cost accounting and enforcement,
  including remaining-limit inheritance and aggregation for synchronous
  delegated agents.
* Added persisted, bounded byte-exact file checkpoints and rewind through
  `Agent` for Deputy write and edit tools; lead and delegated agents share one
  workspace journal. Serialized state is size-bounded and loads are
  root-validated and transactional.
* Hardened permission checks so all mutating file tools enforce configured
  roots and readonly mode fails closed for unknown, mutating, destructive, and
  disallowed open-world tools. Constructor permissions, workspace roots, and
  tools remain authoritative when a saved conversation is loaded.
* Post-tool hook output replacement and suppression now apply to emitted tool
  lifecycle events; interrupting permission denials stop active streams.
* Added lazy, cancellable `run_shiny()` lifecycle management with the Agent's
  run limits, file-root confinement, automatic checkpoints, and incomplete-tool
  recovery; active runs now reject conflicting load, rewind, and compaction
  mutations.
* Added MCP status reporting and richer sub-agent run metadata.
* Initial development version
* Core `Agent` class with streaming `run()` and blocking `run_sync()` methods
* Built-in tools: `tool_read_file`, `tool_write_file`, `tool_list_files`,
  `tool_run_r_code`, `tool_run_bash`, `tool_read_csv`
* Tool bundles: `tools_file()`, `tools_code()`, `tools_data()`, `tools_all()`
* Permission system with `permissions_readonly()`, `permissions_standard()`,
  `permissions_full()`, and custom `Permissions` class
* Hook system with `HookMatcher` and events:
  `PreToolUse`, `PostToolUse`, `Stop`, `UserPromptSubmit`, `PreCompact`
* Multi-agent support with `agent_definition()` and `LeadAgent`
* Skills system with `skill_load()`, `skill_create()`, and `Skill` class
* Explicit session persistence via `Agent$save_session()` and
  `Agent$load_session()`
* Provider-agnostic design works with any ellmer-supported LLM
