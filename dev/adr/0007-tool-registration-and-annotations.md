# Tool registration validates a complete batch before publication

Issues #49 and #50 share one tool boundary. Hosts use `ellmer::tool()` to
describe a local function, a package export, or a service call; Deputy does
not infer schemas, import packages, or connect services during registration.
Existing tool bundles and MCP loaders supply the same ellmer objects.

`Agent$register_tool()` and `$register_tools()` reject existing names unless
the host explicitly supplies `replace = TRUE`. Duplicate names within a
batch always fail. List element names do not rename tools. Constructor tools,
tools already on a supplied Chat, skills, and `set_tools()` share validation.
Validation and runtime adaptation finish before a single `Chat$set_tools()`
call publishes the registry. This guarantees that validation failures leave
the previous registry intact; arbitrary backend failures are not a database
transaction. Deputy reserves its internal result reader's name.

Supplied annotations retain their original values. Known boolean annotations
must be scalar, non-missing logical values. Missing values remain absent on
the tool, while permission checks for custom tools assume read-only FALSE,
destructive TRUE, idempotent FALSE, and open-world TRUE. These are the
[MCP annotation defaults](https://modelcontextprotocol.io/specification/2025-06-18/schema#toolannotations).
Destructive defaults are irrelevant when read-only is explicitly TRUE; an
explicit contradictory destructive TRUE remains restrictive. Annotations
describe behavior and do not establish trust or grant authority. Native
capability checks, deny/allow lists, callbacks, and parent permission ceilings
still apply. Full mode and explicit standard-mode callbacks remain host
authorization mechanisms.

## MCP descriptor compatibility

CRAN mcptools 1.0.2 owns transport, authentication, schema conversion, pagination,
and invocation. Its public `mcp_tools()` converter omits server annotations and
origin; ellmer 0.5.0 exposes no replacement MCP client. Until mcptools exposes
descriptors publicly, Deputy reads its existing connection registry through a
bridge qualified for exactly 1.0.2. The bridge checks descriptor cardinality,
the tool closure's exact server/name, and transport identity. It neither
patches the namespace nor makes a second discovery connection. Unsupported
versions and malformed metadata fail explicitly. The existing `tools_mcp()`
failure contract warns and returns an empty list.
Issue #99 tracks replacing this bridge with a public upstream interface.

Server selection uses exact config names before connecting. Only selected
origins are returned even if mcptools retains other connections globally.
Annotations are translated from MCP camelCase to ellmer snake_case while
retaining FALSE values and extensions. `tool_metadata()` exposes supplied
fields separately from missing fields and effective defaults. Deputy runtime
wrappers retain the source object, including its origin and metadata, and
permission callbacks receive this metadata from the registered executable.
MCP names cannot acquire local-file or approval-prompt privileges; remote
arguments are not rewritten relative to the Agent's workspace.

mcptools resolves calls through mutable server names. A retained tool therefore
checks that its original transport is still current before invocation.
Reconnection invalidates old handles rather than letting old annotations
authorize a new executable. The host reloads and explicitly replaces those
tools. Tools in YAML registries remain live host objects, and child Agents
inherit provider configuration with an empty registry before applying their
definition's tools and the parent's permission ceiling.

Explicit refresh replaces the complete tool set of each selected server,
removing obsolete names even for a successful empty discovery. The internal
load result distinguishes success from failure before registry replacement.
mcptools closes an old transport before replacement discovery and validation,
so failed refreshes cannot promise a working old connection. On every exit,
including discovery/registration errors and interrupts, the Agent removes
handles whose connection guards report invalidation, preserves working tools,
and updates its loaded-tool names. Failed discovery or registration records
an error. Failure before reconnecting leaves valid old tools intact.
