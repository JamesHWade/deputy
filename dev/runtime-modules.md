# Runtime module boundaries

The initial extraction separated internal source organization from the ellmer
integration. The table below describes the current owners of runtime behavior.
Public Agent signatures, permission authority, and session/checkpoint formats
remain stable as these internal modules evolve.

| Responsibility | Source |
| --- | --- |
| Public Agent API, construction, runtime wiring and policy | `R/agent.R` |
| S7 AgentDefinition values and routing normalization | `R/agent-definition.R` |
| Portable YAML definition format and explicit registry resolution | `R/agent-definition-files.R` |
| Mutable LeadAgent registry and delegated policy | `R/agents-multi.R` |
| LeadAgent internal prompt, child setup and policy helpers | `R/agents-multi-helpers.R` |
| Immutable briefs and bounded scoped evidence preparation | `R/delegation-input.R` |
| Host governance forwarding, resource leases and owned cleanup | `R/delegation-binding.R` |
| Portable content record/replay, duration projection and sizing | `R/delegation-content-records.R` |
| Compact outcomes, authorized disclosure and history replay | `R/delegation-inspection.R` |
| Bounded child events and independent observation cursors | `R/delegation-observation.R` |
| Descendant tool cards in the lead's shown conversation | `R/delegation-activity.R` |
| Activity presenter lifecycle and async stream merging | `R/delegation-activity-stream.R` |
| Authorized Shiny child conversation panel | `R/subagent-chat.R` |
| Shiny-independent Markdown and nested content sanitization | `R/subagent-chat-content.R` |
| Subagent records saved with a shinychat conversation | `R/subagent-history.R` |
| Typed JSON codec for portable subagent history records | `R/subagent-history-codec.R` |
| Initial context receipts and independent context views | `R/delegation-manifest.R` |
| Authorized host-selected native history forks | `R/context-fork.R` |
| Admitted delegation records, lifecycle hooks and child settlement | `R/delegation-lifecycle.R` |
| Atomic host-curated graph setup and release | `R/delegation-graph.R` |
| Graph lifetime budgets and structural admission | `R/delegation-tree-budget.R` |
| Recursive ancestry, hooks and subtree cancellation | `R/delegation-tree-runtime.R` |
| Stateless responder wave scheduling | `R/parallel-delegate.R` |
| S7 Skill configuration and requirement inspection | `R/skill.R` |
| Skill directory discovery, metadata, and explicit tool loading | `R/skills.R` |
| Shared governed stream generators and adapters | `R/agent-stream.R` |
| Shared run initialization, settlement, end hooks and teardown | `R/agent-run-state.R` |
| Run accounting, usage enforcement and fail-closed limits | `R/run-usage.R` |
| Provider/ellmer token-table accounting and fallbacks | `R/provider-usage.R` |
| Durable approval suspension and governed resume | `R/agent-approval.R` |
| Portable approval control records and S7 inspection | `R/approval-record.R` |
| Locked immutable approval storage revisions | `R/approval-store.R` |
| Durable host-scheduled job public entry points | `R/agent-job.R` |
| AgentJob S7 snapshot, evidence bounds and state transitions | `R/agent-job-record.R` |
| Job store validation, control records, authorization and recovery | `R/agent-job-store.R` |
| Job worker binding, checkpointing, cleanup and settlement | `R/agent-job-worker.R` |
| Job manifests, graph snapshots and governed runtime checkpoints | `R/agent-job-runtime.R` |
| Session payload construction and restoration | `R/agent-session.R` |
| Context estimation and compaction orchestration | `R/agent-context.R` |
| Compaction evidence scanning, bounds and catalog registries | `R/compaction-evidence.R` |
| Selected conversation reconstruction, prompt framing and atomic state transitions | `R/conversation-state.R` |
| Governed asynchronous compaction requests and recovery | `R/compaction-run.R` |
| Permission/hook callbacks and upstream tool content extraction | `R/agent-tool-callbacks.R` |
| Tool adaptation, execution, trusted delivery and offloading | `R/agent-tool-execution.R` |
| Runtime tool wrapping, ownership checks and path resolution | `R/tool-runtime.R` |
| Offloaded tool-result storage, manifests and integrity validation | `R/tool-result-store.R` |
| Offloaded tool-result references, previews and chunk reader | `R/tool-result-reader.R` |
| Tool call records and delegation correlation | `R/agent-tool-records.R` |
| Public ellmer request callbacks and explicit Chat selection | `R/agent-requests.R` |
| Ellmer structured requests and finite application corrections | `R/structured-run.R` |
| Governance trace adapter | `R/agent-tracing.R` |
| S7 hook and permission callback result contracts | `R/callback-result.R` |
| Built-in hook presets (logging, bash, file writes) | `R/hook-presets.R` |
| TrustedResults across retained specialists and graph routes | `R/trusted-results-routes.R` |
| Permissions object and policy presets | `R/permissions.R` |
| Permission modes, capability intersections and path policy | `R/permission-policy.R` |
| Checkpoint journal operations | `R/file-checkpoints.R` |
| Checkpoint path and byte operations | `R/file-checkpoint-paths.R` |
| Checkpoint state validation | `R/file-checkpoint-validation.R` |
| Native filesystem tools | `R/tools-files.R` |
| Document conversion helpers and tool | `R/tools-documents.R` |
| Trusted one-shot R and shell execution | `R/tools-execution.R` |
| Conversation R owner, queue and process lifecycle | `R/r-session.R` |
| Bounded worker data bridge to explicitly selected tools | `R/r-session-tools.R` |
| Governed nested tool invocation and enclosing execution identity | `R/tool-invocation.R` |
| Ordered R output and static plot capture | `R/r-session-worker.R` |
| Portable R execution evidence and display content | `R/r-session-result.R` |
| Model-facing native text and image bounds | `R/tool-rich-results.R` |
| Host-owned MCP connection and immutable admission lists | `R/mcp-connection.R` |
| Qualified mcptools worker boundary and owner validation | `R/mcp-worker.R` |
| Sandboxed MCP Console connection, launch policy and controls | `R/mcp-console.R` |

R6 method-list factories are internal source organization: R6 still binds their
methods to the same `self` and `private` environments. Explicit roxygen
`@include` directives generate `DESCRIPTION`'s collation order; no alphabetical
load-order assumptions, dynamic source loading, or new public facade are added.
The factories are not alternate runtimes or provider adapters.

`ConversationState` owns retained turns, the originals of microcompacted tool
results, and the installed summary. Its operations receive the current Chat;
the owner never caches a Chat or an Agent callback. A compaction plan holds
only a weak reference to the Chat it was prepared from, so a stale automatic
plan is rejected without keeping a replaced Chat alive; the check runs before
any catalog or artifact is written. Re-initializing an Agent with a different
Chat starts a new `ConversationState` and clears the previous conversation's
activity overlay through its existing owner, which also resets the presenter.
Context estimates then trust the new Chat's reported usage, as for a new Agent.
Arguments and tool batches are checked before the switch; if a later step
fails, the Agent returns to the previous Chat, its ownership and conversation.
Re-initializing with the same Chat preserves both conversation and activity.
This keeps reconstruction consistent after cloning, fallback, and explicit Chat
replacement. Agent-owned prompt writes pass through the same module, with
explicit prompt replacement reconciling summary identity and internal appends
preserving it.

Conversation installation rolls back the Chat when a setter or synchronous
installation callback fails, and commits its owned state only after that
callback succeeds. Compaction and session restoration use this seam to register
artifact readers before accepting the conversation. Artifact transactions,
provider selection, approval authority, activity projection, and run accounting
retain their existing owners. Snapshot traversal centralizes the turn-bearing
fields without changing schema 3. Tests exercise these transitions through the
public Agent interface.

## Size exception

`R/agent.R` remains above 1,000 lines (2,337 immediately after extraction,
3,428 on 2026-09-28). It intentionally keeps the complete public class
interface and its roxygen method documentation together, including the
constructor and immutable fields. Streaming, sessions, compaction, and tool
lifecycle implementations live in cohesive internal modules. Splitting that
public interface across source files would make its contract harder to discover
and document. This is the explicit exception allowed by #72, not a target to
satisfy with arbitrary fragments.

The other files listed in #72 — and all other non-exempt `R/` source files
following the cleanup series (#272–#278) — are below 1,000 lines. Count with
`wc -l R/*.R | sort -n`.

`R/delegation-content-records.R` owns portable content record/replay, duration
projection, and recursive payload sizing (`observation_payload_fits()`), keeping
a clean one-way dependency from `R/delegation-inspection.R` and
`R/delegation-observation.R`. `R/delegation-inspection.R` owns compact outcomes
and authorized disclosure; it does not execute children or implement a UI
renderer. `R/tool-display-evidence.R` owns the versioned display/provenance
projection that those records carry (ADR-0032), and `R/subagent-display.R` owns
the adapter's inert rebuild of display HTML. `R/subagent-history-codec.R` owns
the typed JSON codec and `R/subagent-history.R` owns saving those records with
a shinychat conversation (ADR-0034); the panel only asks it for the open
conversation's views. `R/subagent-chat-content.R` owns Shiny-independent
Markdown and nested content sanitization for `R/subagent-chat.R`.

`R/delegation-observation.R` owns bounded event envelopes and authorized cursor
readers. The Agent event kernel appends data; subscribers never consume child
generators or run callbacks inside execution. See ADR-0021.
