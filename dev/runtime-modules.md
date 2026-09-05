# Runtime module boundaries

The ellmer integration is a semantic change; the following file moves are a
separate mechanical commit. Public method signatures, method bodies (excluding
source positions), permission authority, R6 fields, and session/checkpoint
formats remain unchanged by the moves.

| Responsibility | Source |
| --- | --- |
| Public Agent API, construction, runtime wiring and policy | `R/agent.R` |
| Shared governed stream, adapters and finalization | `R/agent-stream.R` |
| Session payload construction and restoration | `R/agent-session.R` |
| Context estimation and compaction | `R/agent-context.R` |
| Permission/hook callbacks and upstream tool content extraction | `R/agent-tool-callbacks.R` |
| Tool call records and delegation correlation | `R/agent-tool-records.R` |
| Public ellmer request callbacks and explicit Chat selection | `R/agent-requests.R` |
| Ellmer structured requests and finite application corrections | `R/structured-run.R` |
| Governance trace adapter | `R/agent-tracing.R` |
| Permissions object and policy presets | `R/permissions.R` |
| Permission values, capability intersections and path policy | `R/permission-policy.R` |
| Checkpoint journal operations | `R/file-checkpoints.R` |
| Checkpoint path and byte operations | `R/file-checkpoint-paths.R` |
| Checkpoint state validation | `R/file-checkpoint-validation.R` |
| Native filesystem tools | `R/tools-files.R` |
| Document conversion helpers and tool | `R/tools-documents.R` |
| Trusted one-shot R and shell execution | `R/tools-execution.R` |

R6 method-list factories are internal source organization: R6 still binds their
methods to the same `self` and `private` environments. Explicit roxygen
`@include` directives generate `DESCRIPTION`'s collation order; no alphabetical
load-order assumptions, dynamic source loading, or new public facade are added.
The factories are not alternate runtimes or provider adapters.

## Size exception

`R/agent.R` remains above 1,000 lines (2,337 immediately after extraction).
It intentionally keeps the complete public class interface and its roxygen
method documentation together, including the constructor and immutable fields.
Streaming, sessions, compaction, and tool lifecycle implementations live in
cohesive internal modules. Splitting that public interface across source files
would make its contract harder to discover and document. This is the explicit
exception allowed by #72, not a target to satisfy with arbitrary fragments.

The other files listed in #72 are below 1,000 lines. Tests now separate hook
registry behavior, hook result values, built-in hook policies, AgentDefinitions,
and delegated permission/budget policy. Whole test cases move along those
boundaries and continue to use shared helper files.
