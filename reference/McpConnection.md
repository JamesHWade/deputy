# Own an isolated MCP client connection

A host-owned connection to one configured server. A separate R worker
keeps mcptools' connection registry independent of other connections.
mcptools owns transport and authentication; the selected server owns
execution.

This temporary adapter is qualified for mcptools 1.0.2 and uses its
internal request and shutdown functions. Public replacements are tracked
upstream in issues 129 and 130. Other versions fail explicitly.

## Details

Construct an Agent first, then bind a connection to it. Tool, resource
URI and prompt allowlists are fixed at construction. Discovery never
expands them. Register the tools returned by `$tools()` to apply the
Agent's normal permissions, hooks and budgets. Direct host methods use
the connection's allowlists but do not constitute an Agent run.

Calls return promises, with at most one active call per connection. A
concurrent call fails with a busy error; unrelated connections and the
host event loop remain available. The host must call `$close()` when its
conversation ends. `$cancel()` terminates the connection and its process
tree, discarding server session state. It does not promise a
state-preserving interpreter interrupt. Timeouts also close the
connection; old tools cannot reconnect implicitly.

Owner identifiers and run context prevent accidental cross-Agent reuse;
the host remains responsible for authentication and assigning those
identifiers. Connections and executable tools are not portable
saved-session state.

## Methods

### Public methods

- [`McpConnection$new()`](#method-McpConnection-initialize)

- [`McpConnection$status()`](#method-McpConnection-status)

- [`McpConnection$discover()`](#method-McpConnection-discover)

- [`McpConnection$read_resource()`](#method-McpConnection-read_resource)

- [`McpConnection$get_prompt()`](#method-McpConnection-get_prompt)

- [`McpConnection$tools()`](#method-McpConnection-tools)

- [`McpConnection$capability_tools()`](#method-McpConnection-capability_tools)

- [`McpConnection$cancel()`](#method-McpConnection-cancel)

- [`McpConnection$close()`](#method-McpConnection-close)

------------------------------------------------------------------------

### `McpConnection$new()`

Connect and discover tools from one exact server entry.

#### Usage

    McpConnection$new(
      config,
      server,
      agent,
      tools = character(),
      resources = character(),
      prompts = character(),
      timeout = 60,
      startup_timeout = 60
    )

#### Arguments

- `config`:

  Path to an mcptools JSON configuration.

- `server`:

  Exact configured server name.

- `agent`:

  Agent whose identity, session and run context own this connection.

- `tools`:

  Exact tool names the host allows. Empty by default.

- `resources`:

  Exact resource URIs the host allows. Empty by default.

- `prompts`:

  Exact prompt names the host allows. Empty by default.

- `timeout`:

  Maximum seconds for each request.

- `startup_timeout`:

  Maximum seconds for client and server startup.

------------------------------------------------------------------------

### `McpConnection$status()`

Inspect local connection state and fixed host allowances.

#### Usage

    McpConnection$status()

#### Returns

A list. This is local process state, not a remote health probe.

------------------------------------------------------------------------

### `McpConnection$discover()`

Inspect one catalogue page without registering or authorizing items.

#### Usage

    McpConnection$discover(
      kind = c("tools", "resources", "resource_templates", "prompts"),
      cursor = NULL
    )

#### Arguments

- `kind`:

  One of `"tools"`, `"resources"`, `"resource_templates"`, `"prompts"`.

- `cursor`:

  Opaque cursor returned by a previous page, or NULL.

#### Returns

A promise for one server result with connection provenance.

------------------------------------------------------------------------

### `McpConnection$read_resource()`

Read one explicitly allowed resource URI.

#### Usage

    McpConnection$read_resource(uri)

#### Arguments

- `uri`:

  Exact allowed resource URI. Returned links are never fetched
  automatically.

#### Returns

A promise for the upstream resource result and connection provenance.

------------------------------------------------------------------------

### `McpConnection$get_prompt()`

Retrieve one explicitly allowed prompt without changing any Chat.

#### Usage

    McpConnection$get_prompt(name, arguments = list())

#### Arguments

- `name`:

  Exact allowed prompt name.

- `arguments`:

  Named list of prompt argument strings.

#### Returns

A promise for the upstream prompt result and connection provenance.

------------------------------------------------------------------------

### `McpConnection$tools()`

Build allowed tool handles for explicit Agent registration.

#### Usage

    McpConnection$tools()

#### Returns

A named list of ellmer tools, bound to this connection and owner.

------------------------------------------------------------------------

### `McpConnection$capability_tools()`

Build resource and prompt tools restricted to the fixed host allowlists.

#### Usage

    McpConnection$capability_tools(prefix = "mcp")

#### Arguments

- `prefix`:

  Tool name prefix. Use distinct prefixes when registering capability
  tools from multiple connections. Must contain 1 to 50 letters, digits,
  underscores or hyphens.

#### Returns

A named list of ellmer tools for explicit Agent registration.

------------------------------------------------------------------------

### `McpConnection$cancel()`

End the connection and discard its server session state.

#### Usage

    McpConnection$cancel()

#### Returns

Invisibly, NULL. Repeated calls are harmless.

------------------------------------------------------------------------

### `McpConnection$close()`

Close transport when idle, then terminate the client process tree.

#### Usage

    McpConnection$close()

#### Returns

Invisibly, NULL. Closing an active call rejects its promise.
