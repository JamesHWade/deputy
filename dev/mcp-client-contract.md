# Temporary MCP client contract

Deputy uses mcptools 1.0.2 as its minimum and current released compatibility
target. The public client remains `mcp_tools(config)`. The development client
inspected at `079e011e6f2a515565f903dc8a5b7c4d793746f1` has no public descriptor,
resource, prompt or independently owned connection API. An unreleased API is
not inferred from the server-side embedding work.

| Capability | mcptools 1.0.2 public surface | Temporary Deputy integration |
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
calling `tools/list`, which mcptools 1.0.2 otherwise requests unconditionally.
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

Only mcptools 1.0.2 is accepted. Tool descriptions, schemas and annotations are
validated before handles become available. A connection has at most one active
call; overlap returns a busy error. Cancellation, timeout, shutdown and detected
server exit invalidate every handle. No operation silently reconnects with old
annotations. Unsupported protocol methods return their upstream error and never
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
Other transport/authentication configuration stays with mcptools; upstream
sandbox configuration remains the host's responsibility.

The qualified producer is mcp-repl 0.3.0 with mcptools 1.0.2. The convenience
function validates the tool shape, not the binary version. Its R journey on
macOS demonstrates persistent values, isolation across two Agents using the
same server name, ellmer image content, bounded output with a full transcript
artifact, busy-interpreter output, a successful state-preserving Ctrl-C,
Ctrl-D reset, interpreter exit/state loss, and cleanup with invalid old handles.
`tests/testthat/test-mcp-repl-lifecycle.R` runs that journey when
`DEPUTY_MCP_REPL_BIN` names the qualified executable. Ordinary CI retains the
deterministic real MCP producer without requiring an installed REPL binary.

`mcp_repl_control()` sends the documented Ctrl-C or Ctrl-D input and returns
the actual upstream result. It does not infer success from dispatch, invent a
generic lifecycle API, or run a second interpreter. Controls require an idle
client connection, although the upstream interpreter may still be executing
after a busy result. A control request is a direct host operation; model-issued
control input goes through the registered `repl` tool's normal governance.

Agent interruption and internal stream stops cancel that Agent's active owned
MCP requests. Cancellation closes the connection and discards its state. Idle
connections remain available. A server process exit also invalidates the
connection. An interpreter exit can instead be reported by a surviving
mcp-repl server, followed by a fresh interpreter on the next request. Preserve
that state-loss message; a stable connection ID is not an interpreter-state
receipt.

The R client worker only runs mcptools. mcp-repl owns execution, interruption,
reset, OS confinement, preview truncation and spill artifacts. ellmer owns
ordered text/image content. Deputy's usual offloading can bound a resulting
Agent context without copying the upstream artifact store. The host owns any
durable artifact retention before the upstream session is closed.
