# Agent SDK Parity

deputy keeps a provider-agnostic R runtime at its core and layers an
opt-in Agent SDK-compatible facade on top. This inventory was refreshed
on 2026-08-09 against Anthropic’s TypeScript and Python Agent SDKs,
PydanticAI and Harness, the OpenAI Agents SDK, and LangChain Deep
Agents. It separates API-shape compatibility from behavior that actually
runs in deputy.

## Cross-framework inventory

| Capability | Reference behavior | deputy status after this pass | Important remaining gap |
|----|----|----|----|
| Agent loop and providers | All four ecosystems support model/tool loops; PydanticAI and Deep Agents have broad provider routing | **Covered:** ellmer-backed provider portability, sync and generator APIs | Ordered model fallback and retry/backoff policy |
| Tools and MCP | Rich typed tools plus MCP transports, filtering, auth, resources, prompts, and approvals | **Partial:** native/SDK aliases, custom tools, MCP tool loading and status | MCP resources/prompts, live reconnect, auth/filter policy, tool search |
| Structured output | Native schema modes validate and retry bad output | **Partial:** JSON parsing and optional JSON Schema validation | Provider-native schema submission, correction retry, streamed partial objects |
| Streaming | Semantic token, tool, state, approval, and child-agent events with cancellation | **Substantial in the native API:** `Agent$run()` emits text/content, `tool_start`, `tool_end`, run IDs, usage, warnings, and cooperative interrupt; SDK facade queries are blocking | SDK-facade streaming and queued input, partial tool arguments, approval/subagent namespaces |
| Sessions and durability | Serializable sessions, pause/resume, checkpoints, forks, and external stores | **Substantial:** snapshots, resume-at-time, fork, in-memory and latest-only external store adapters, persisted file journals | Point-in-time external-store selection, replay-safe arbitrary execution state, and durable approval interrupts |
| File state | Anthropic and sandbox runtimes expose reversible workspace state | **Covered for Deputy file tools:** automatic/manual checkpoints, bounded byte-exact rewind, and one lead/child workspace journal | Shell/R/custom-tool writes and full workspace snapshots are outside the journal |
| Permissions and HITL | Tool availability is separate from durable approval and OS isolation | **Partial:** dynamic modes, callbacks, alias-normalized policy, fail-closed path roots | Serializable pause/edit/approve/reject decisions and an OS sandbox |
| Hooks and middleware | Lifecycle interception can transform, retry, defer, or short-circuit work | **Partial:** run/tool/session/permission/compact/subagent hooks; trace redaction | ellmer cannot apply in-flight `updated_input` or model-visible output rewrites |
| Usage and budgets | Request, tool, token, cost, thread, and child-tree budgets | **Substantial:** per-run request/tool/token/cost stop conditions, typed termination, and direct synchronous child usage aggregated into the lead run | Provider-side token/cost ceilings, parallel/background/transitive child-tree accounting, and cross-run/global spend windows |
| Subagents | Isolated, resumable, sometimes background child agents with custom resources | **Substantial for synchronous delegation:** definitions, custom model/tools/skills, remaining-budget inheritance, aggregated/enforced child usage, and run introspection | Parallel/background/resumable children, transitive child trees, and global budget policy |
| Context, skills, memory | Progressive skills, scoped memory, automatic compaction and offload | **Partial:** Claude settings, skills, memory files, manual compaction hooks | Automatic context thresholds and large tool-result offload |
| Tracing and evals | OpenTelemetry or native traces span models, tools, handoffs, and evaluators | **Missing:** hooks can feed a custom logger | First-class spans/exporters and dataset/evaluator APIs |
| Sandbox | Fail-closed workspace or VM/container isolation with snapshots | **Missing:** `callr` gives process isolation and timeout only | Enforced filesystem/network/process sandbox profiles |

The comparison ceiling is deliberately demanding. Anthropic’s
[sessions](https://code.claude.com/docs/en/agent-sdk/sessions),
[hooks](https://code.claude.com/docs/en/agent-sdk/hooks),
[streaming](https://code.claude.com/docs/en/agent-sdk/streaming-output),
and [file
checkpointing](https://code.claude.com/docs/en/agent-sdk/file-checkpointing)
set the compatibility target. PydanticAI contributes explicit [usage
limits](https://pydantic.dev/docs/ai/core-concepts/agent/), typed
[output validation](https://pydantic.dev/docs/ai/core-concepts/output/),
and Harness [step
persistence](https://pydantic.dev/docs/ai/harness/step-persistence/).
OpenAI’s SDK is especially strong in durable [human
approval](https://openai.github.io/openai-agents-python/human_in_the_loop/)
and [sessions](https://openai.github.io/openai-agents-python/sessions/).
Deep Agents inherits LangGraph’s [checkpoint, replay, and time-travel
model](https://docs.langchain.com/oss/python/langgraph/persistence) and
adds composable
[middleware](https://docs.langchain.com/oss/python/langchain/middleware/built-in)
and isolated
[subagents](https://docs.langchain.com/oss/python/deepagents/subagents).

## What became operational in this pass

- Native and SDK file-tool aliases now share one permission identity.
  Root containment covers write, edit, multi-edit, and todo-write
  variants and rejects missing or escaping paths.
- Content streaming emits real tool lifecycle events around execution.
  Every event emitted by `Agent$run()` carries a `run_id`; final usage
  is available on `AgentResult$usage`.
- [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  applies per-run model-request and tool-call limits, plus
  input/output/total-token and estimated-cost stop conditions. Token and
  cost thresholds are evaluated after provider usage arrives and can
  overshoot by one response. Direct synchronous child usage is added to
  the lead run, and children inherit its remaining limits. Limits can
  return a typed stop reason or signal a structured Deputy error.
- `Agent$interrupt()` cooperatively cancels an active ellmer stream, and
  an interrupting permission denial now stops the run.
- `enable_file_checkpointing = TRUE` creates a checkpoint at the
  beginning of each run. Manual checkpoints, bounded byte-exact file
  rewind, shared lead/child journals, and session persistence are
  exposed through both `Agent` and `AgentSDKClient`.
- Post-tool hook replacement and suppression now affect emitted
  `tool_end` events. They intentionally do not rewrite the tool result
  already visible to the model because ellmer’s callback return value is
  observational.

## Entry Points

Use
[`agent_sdk_options()`](https://jameshwade.github.io/deputy/reference/claude_sdk_options.md)
to express Anthropic-shaped options and translate them into deputy
internals. The Claude-named aliases remain fully supported.

``` r

library(deputy)

options <- agent_sdk_options(
  chat = ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929"),
  setting_sources = c("user", "project", "local"),
  permission_mode = "plan",
  allowed_tools = c("Read", "Grep", "LS"),
  max_turns = 15
)

result <- agent_sdk_query("Summarize the package structure", options = options)
result$session_id
```

For a stateful client:

``` r

client <- AgentSDKClient$new(options)
client$query("Inspect the R/ directory")
```

[`agent_sdk_query()`](https://jameshwade.github.io/deputy/reference/claude_sdk_query.md)
and `AgentSDKClient$query()` block until completion. The native
`Agent$run()` generator is the streaming entry point.

## Run usage, limits, and semantic events

``` r

agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
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

`Agent$run()` yields `start`, semantic content/tool events, a final
`usage` event, and `stop`. `Agent$interrupt()` requests cooperative
cancellation while the stream is active. Request and tool-call limits
are checked at model and tool boundaries. Token and cost limits stop a
run after reported usage crosses the threshold, so they can overshoot by
one model response.

`Agent$run_shiny()` seeds the same run limits, with its `max_tool_calls`
argument as an explicit override, and asks ellmer to cancel the active
stream as soon as an overage is observed. The initial provider response
begins before Deputy can observe its token and cost, so those limits can
still overshoot by one response. For recognized file tools, every path
must be absolute and resolve inside the Agent’s immutable `working_dir`.

## Reversible file checkpoints

``` r

options <- agent_sdk_options(
  chat = ellmer::chat("anthropic"),
  tools = c("Read", "Write", "Edit"),
  enable_file_checkpointing = TRUE,
  cwd = getwd()
)
client <- AgentSDKClient$new(options)

checkpoint_id <- client$checkpoint("before refactor")
client$query("Refactor R/parser.R")
client$list_checkpoints()
client$rewind_files(checkpoint_id)
```

The journal observes Deputy’s native and SDK-compatible
write/edit/multi-edit/ todo tools. It does not claim to capture writes
performed by `run_bash`, `run_r_code`, or arbitrary custom tools.
Captures default to 50 MiB per file. The default maximum aggregate
serialized checkpoint-state size is 250 MiB, counting journal records,
checkpoint markers, metadata, and pending captures. Use
`file_checkpoint_max_file_bytes` and `file_checkpoint_max_journal_bytes`
to tighten those bounds. The caps apply to live captures and restored
session state; violations signal `deputy_file_checkpoint_limit_error`.

## Sessions, Resume, and Fork

The compatibility layer persists snapshots to:

``` r

tools::R_user_dir("deputy", "cache")
```

Snapshots are enabled by default for the compatibility APIs. Each
completed turn writes a new snapshot, and the latest snapshot path is
attached to `AgentResult$snapshot_path`.

An in-memory adapter is useful for tests or process-local workflows:

``` r

store <- session_store_memory()
options <- agent_sdk_options(
  chat = ellmer::chat("anthropic"),
  session_store = store
)
client <- AgentSDKClient$new(options)
result <- client$query("Create a high-level summary")
client$list_session_summaries()
```

External adapters load the latest payload only. Timestamped
`resume(at = ...)` and `list_sessions()` use the local on-disk snapshot
index; use `list_session_summaries()` for an external adapter’s
summaries.

``` r

result <- client$query("Create a high-level summary")

# Restore the latest snapshot for a session id
client$resume(result$session_id)

# Restore the newest snapshot at or before a point in time
client$resume(result$session_id, at = "2026-03-07 10:30:00")

# Clone the restored state into a new session id
client$resume(result$session_id, fork = TRUE)
```

Compatibility resume restores conversation and prompt while keeping the
receiving agent’s configured tools authoritative. Native
`Agent$load_session(..., restore_tools = TRUE)` is the explicit opt-in
for trusting and restoring serialized tools. Session data never replaces
constructor-supplied permissions or the working directory. Checkpoint
journals are restored only when checkpointing was explicitly enabled and
the configured root matches the saved root.

The CLI exposes the same behavior:

``` bash
deputy --permission-mode plan --persist-session
deputy --resume-session-id abc123
deputy --resume-session-id abc123 --resume-session-at "2026-03-07 10:30:00"
deputy --resume-session-id abc123 --fork-session
```

## Permissions and Hooks

Anthropic’s planning behavior maps to deputy’s `plan` mode:

``` r

permissions_plan()
```

`plan` allows only tools annotated with `read_only_hint = TRUE` and
permitted by the configured capabilities, plus the approval tool named
by `permission_prompt_tool_name` (default: `"AskUserQuestion"`). Write,
execution, destructive, unannotated, and disallowed open-world tools are
denied. `dontAsk` deliberately disables the approval-tool escape hatch.

Informational runtime events now use the existing hook system via
`Notification`:

``` r

hook <- HookMatcher$new(
  event = "Notification",
  callback = function(message, context) {
    cli::cli_alert_info("[{context$code}] {message}")
    NULL
  }
)
```

deputy emits `Notification` for cases such as session restore or fork
notices, permission-denied guidance, compaction fallbacks, and cost
warnings.

## Settings, Agents, and Tool Aliases

[`claude_settings_load()`](https://jameshwade.github.io/deputy/reference/claude_settings_load.md)
and
[`claude_settings_apply()`](https://jameshwade.github.io/deputy/reference/claude_settings_apply.md)
now understand:

- `CLAUDE.md` memory blocks
- `.claude/skills`
- `.claude/commands`
- `.claude/agents`
- Tool policy keys such as `allowedTools`, `disallowedTools`, and
  `permissionPromptToolName`

`setting_sources` precedence is fixed as `user`, then `project`, then
`local`. The `local` source only loads `.claude/settings.local.json`, so
it can override settings keys without pulling in extra memory, commands,
skills, or agents.

Custom agents from `.claude/agents` are converted to `AgentDefinition`
objects and registered automatically when you use `LeadAgent` or
`AgentSDKClient`. Unsupported frontmatter fields are warned on and
ignored so compatibility stays resilient when files include metadata
deputy does not map.

Anthropic-style tool names resolve through the compatibility layer
rather than changing deputy’s native tool names:

``` r

compat_tools <- agent_sdk_options(
  custom_tools = list(),
  allowed_tools = c("Read", "Edit", "TodoWrite", "Agent")
)
```

This keeps `read_file`, `edit_file`, `todo_write`, and the rest of
deputy’s snake_case tool surface intact for native R users.

## Design boundary and next priorities

deputy aims for behavioral compatibility, not a literal language-port of
the Node or Python SDKs. The runtime model is intentionally R-native:

- R6 objects instead of Python or TypeScript classes
- `coro` generators for streaming
- Base lists and data frames for snapshots and session indexes
- Existing deputy hooks and permissions reused by the compat facade

That boundary keeps the Anthropic surface available without making the
rest of the package Anthropic-specific. The next parity work should
prioritize durable approval pause/resume, SDK-facade streaming and
queued input, richer MCP resources/prompts/auth/reconnect,
structured-output correction retries, tracing/evals, parallel/background
subagents and transitive budget trees, automatic context management, and
a real sandbox. Options such as `sandbox` and `fallback_model` remain
shape-only and warn when supplied; they are not security or reliability
guarantees.
