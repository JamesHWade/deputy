# Temporary MCP client contract

Deputy uses mcptools 1.0.2 as its minimum and qualifies an explicit list of
releases, `mcptools_qualified_versions` (currently 1.0.2 and 1.0.3). CRAN
1.0.3 changed only DESCRIPTION, NEWS.md and one upstream test; its `R/`
sources are identical to 1.0.2. The public client remains `mcp_tools(config)`.
The development client inspected at
`079e011e6f2a515565f903dc8a5b7c4d793746f1` has no public descriptor, resource,
prompt or independently owned connection API. An unreleased API is
not inferred from the server-side embedding work.

| Capability | mcptools 1.0.2/1.0.3 public surface | Temporary Deputy integration |
|---|---|---|
| Configuration, stdio, HTTP, authentication, tool conversion | `mcp_tools()` | Reused without another transport or OAuth implementation |
| Tool annotations and origin | Dropped during public conversion | Existing descriptors, qualified version, connection-bound handles |
| Independent connections using the same configured name | Registry is process-global | One host-owned R client worker per `McpConnection` |
| Resource, resource-template and prompt discovery | No public client accessor | One upstream request per explicit catalogue page |
| Resource reads and prompt retrieval | No public client accessor | Exact immutable host allowlists, with optional governed Agent tools |
| Nonblocking client calls | Public tool calls wait synchronously | Promise polling of the isolated mcptools worker |
| Graceful idle shutdown | No public client control | Existing mcptools transport close, then client process-tree cleanup |
| Cancellation and timeout | R interrupt support during a synchronous request | End the owned connection and discard session state |
| Live remote health or state-preserving interpreter interrupt | No general public guarantee | Not advertised; status describes local process state |

The temporary bridge is explicitly authorized for the current integration.
It does not satisfy #99's eventual public-only replacement criterion. Track that
replacement in [mcptools #129](https://github.com/posit-dev/mcptools/issues/129),
client ownership and async calls in
[#130](https://github.com/posit-dev/mcptools/issues/130), and non-tool client
access in [#109](https://github.com/posit-dev/mcptools/issues/109). No upstream
mcptools implementation PR is part of this work.

## Ownership and authority

`McpConnection` is a mutable host-owned resource, not saved Agent state. It binds
to one Agent ID, session ID and run context. The host supplies authenticated
identity and owns end-of-conversation cleanup. Reusing matching identifiers is
not authentication. Related Agent clones with the same owner values can share
the connection deliberately; unrelated owners cannot register its tools.
Every Agent invocation rechecks the executing Agent's effective run context
before transport dispatch. Loading a different context into a clone or passing
a per-run context override cannot reuse the original connection's authority.

Selection happens before any server starts. The client worker receives only
the selected configuration, with a private temporary configuration file, the
parent's package library paths, and the Agent's working directory. It does not
load the host project's R profile. Each worker loads mcptools once and converts
the allowed tool catalogue from that connection. When no tools are allowed,
the adapter composes mcptools' transport and initialization helpers without
calling `tools/list`, which mcptools otherwise requests unconditionally.
This permits resource-only and prompt-only servers without a tool catalogue.
Metadata inspection makes no second connection.

The immutable allowlists name exact tools, resource URIs and prompts. Catalogue
pages and returned links do not expand these allowances, cause a read, or
register a tool. Explicitly registered resource/prompt tools use normal Agent
permissions, hooks, request limits and result handling. Direct host access is
limited by the host allowlists but is not an Agent run. Prompt results stay
data until the host decides to add them to a conversation.
`capability_tools(prefix = "mcp")` accepts a host-selected name prefix; use
distinct prefixes when registering capabilities from multiple connections.

mcptools owns configuration semantics, protocol IDs, conversion, transport,
authentication, server errors and transport closure. The adapter invokes its
existing functions and uses explicit cursors rather than implementing pagination.
The upstream server owns interpreter state, sandboxing and rich-result previews.
Deputy creates neither an interpreter nor a second output-artifact store.

## Failure and qualification

Only the listed mcptools releases are accepted; the metadata bridge, the
client worker and the producer-test skips share the one list. A new release is
added only after its client sources are reviewed. Tool descriptions, schemas and annotations are
validated before handles become available. A connection has at most one active
call; overlap returns a busy error. Cancellation, timeout, shutdown and detected
server exit invalidate every handle. No operation silently reconnects with old
annotations.

The qualified mcptools releases read a stdio reply by polling 20 times at
0.2 s. They return `NULL` when nothing arrived and otherwise parse the first
output line without checking its JSON-RPC id, so a late reply answers the next
request. The worker therefore sends every request, including tool calls,
through one exchange. Tool calls use mcptools' own request constructor and
result converter, so the converted tool closure is not called. A `NULL`
reply, or one whose id differs from the request, stops the server and fails
with `deputy_mcp_desynchronized`. The host then closes the connection
(`status()$reason` is `"desynchronized"`); later calls fail as closed. A
server that exited is still reported as an exit. `tools_mcp()` handles cannot
see the reply id. They treat a `NULL` tool result as a lost reply, which the
converter returns only when no response was read (a legitimate empty result
converts to `""` or a list), stop the server, and fail on the first lost
reply so no later line is read as another answer. Correlation by id belongs
upstream; the guard stays until a qualified release provides it. Unsupported protocol methods return their upstream error and never
pretend to have read a resource or retrieved a prompt.

`status()` is a local ownership/process record, not a remote health probe. A
remote HTTP service can fail independently of its client worker. Cancellation
terminates local owned processes; it cannot guarantee that a remote service
reverses a request it already received. Hosts must reconcile any external effect
whose outcome is unknown.

Real stdio producer tests exercise independent state, exact selection,
annotations, discovery pages, denied reads without dispatch, resource/prompt
results, Agent permission and hook paths, busy calls, host event-loop progress,
cancellation, timeout, server crash, and invalid handles. Existing producer
coverage retains the YAML registry and delegation journey. Qualification against
a large external catalogue and replacement with released public APIs remain
tracked in #48 and #99; a small producer is not evidence for catalogue scaling.

## Persistent execution with mcp-repl

`mcp_repl_connection()` freezes the selected configuration before checking and
connecting it. It requires an explicit supported `--sandbox` policy and the
`repl(input, timeout_ms)` tool contract. A `--config sandbox_mode` override is
rejected, including when it occurs after an otherwise valid sandbox flag.
URL entries are rejected because mcptools would choose HTTP instead of the
validated local executable even when both fields appear in the configuration.
Other transport/authentication configuration stays with mcptools; upstream
sandbox configuration remains the host's responsibility.

The qualified producer is mcp-repl 0.3.0 with mcptools 1.0.2 or 1.0.3. The convenience
function validates the tool shape, not the binary version. Its R journey on
macOS demonstrates persistent values, isolation across two Agents using the
same server name, ellmer image content, bounded output with a full transcript
artifact, busy-interpreter output, a successful state-preserving Ctrl-C,
Ctrl-D reset, interpreter exit/state loss, and cleanup with invalid old handles.
`tests/testthat/test-mcp-repl-lifecycle.R` runs that journey when
`DEPUTY_MCP_REPL_BIN` names the qualified executable. Ordinary CI retains the
deterministic real MCP producer without requiring an installed REPL binary.

The `repl` tool forwards `timeout_ms` capped at 3000 ms, and sends 3000 ms
when the caller omits it (mcp-repl's own default is 60 s). mcp-repl answers
shortly before that deadline with its busy status while the work continues,
which keeps the reply inside the transport window. A later call with empty
`input` retrieves the remaining output. The registered tool description says
so. `tools_mcp_repl()` applies the same bound.

`mcp_repl_control()` sends the documented Ctrl-C or Ctrl-D input and returns
the actual upstream result. It does not infer success from dispatch, invent a
generic lifecycle API, or run a second interpreter. Controls require an idle
client connection, although the upstream interpreter may still be executing
after a busy result. A control request is a direct host operation; model-issued
control input goes through the registered `repl` tool's normal governance.

Agent interruption and internal stream stops cancel that Agent's active owned
MCP requests. Pending executions retain their cancellation binding when the host
removes or replaces registered tools; those bindings are released when the call
settles. Cloning an Agent does not copy its pending executions. Cancellation
checks the stopping Agent's effective ownership, closes matching busy connections
and discards their state. Idle connections remain available. A server process exit also invalidates the
connection. An interpreter exit can instead be reported by a surviving
mcp-repl server, followed by a fresh interpreter on the next request. Preserve
that state-loss message; a stable connection ID is not an interpreter-state
receipt.

The R client worker only runs mcptools. mcp-repl owns execution, interruption,
reset, OS confinement, preview truncation and spill artifacts. ellmer owns
ordered text/image content. Deputy's usual offloading can bound a resulting
Agent context without copying the upstream artifact store. The host owns any
durable artifact retention before the upstream session is closed.

## Persistent workbench with MCP Console

`mcp_console_connection()` follows the mcp-repl pattern with an explicit
executable instead of a configuration entry (ADR-0029). It checks the
executable's `--version` against `mcp_console_qualified_versions` (0.0.4)
before launch, builds `serve` and the admitted arguments itself, and writes a
private frozen configuration for one server named `console`. The server
starts in the Agent's working directory, which is its sandbox workspace,
project-configuration location and recording location. A
`.agents/console/config.yaml` there blocks launch unless the host opts in.

After initialization the adapter checks the `send` field names and the
security sentence that MCP Console derives from its effective sandbox policy.
Only native enforcement with restricted networking is accepted. The adapter
then attaches a producer adapter to the connection. `McpConnection$tools()`
uses it to bound `send` arguments and extend the description, `status()` and
tool metadata report its `execution` record (backend, version, sandbox
profile, dependency decision, workspace and recordings path), and `close()`
closes the server's input and waits up to 2 seconds before mcptools kills the
process. mcp-repl uses the same adapter hook for `repl`.

`send` forwards `timeout_ms` capped at 2500 ms (also when omitted). MCP Console
starts that wait after admission, and interrupt adds a 100 ms grace, so replies
stay inside the 4 second window and long cells return
`[running; poll with an empty send]`. The model-facing tool refuses
`control = "restart"`; `mcp_console_control()` sends it as a host operation
and turns a desynchronized reply into `deputy_mcp_console_restart`. Explicit
dependency preparation and stdin sent to a stopped worker also have no
upstream deadline; if they outlast the window the connection closes as
desynchronized, as for any other server.

Permission evaluation recognizes the `mcp-console` execution backend. Standard
mode requires `bash`, calls with `requirements` require `install_packages`,
and readonly and plan modes deny `send`. The connection's `dependencies`
setting is enforced before dispatch whatever the permission mode.

`tests/testthat/test-mcp-console.R` runs against a stdio fixture that serves
the released 0.0.4 `tools/list` result (`fixtures/mcp-console-tools.json`) and
emulates polling, interrupt, restart and plot output. The live journey runs
when `DEPUTY_MCP_CONSOLE_BIN` names a qualified executable.
