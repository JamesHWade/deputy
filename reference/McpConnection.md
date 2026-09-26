# MCP server connection

A connection to one MCP server, owned by one agent. Use it instead of
[`tools_mcp()`](https://jameshwade.github.io/deputy/reference/tools_mcp.md)
when you need a fixed list of allowed tools, resources and prompts, a
request timeout, or control over when the server stops. Each connection
runs its own mcptools client in a separate R process. Requires mcptools
1.0.2 or 1.0.3.

## Details

Create the
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) first,
then the connection. The allowlists are fixed when the connection is
created; `$discover()` never adds to them. Register `$tools()` on the
agent so that calls go through its permissions, hooks and limits. The
other methods call the server directly, outside any agent run.

Methods that contact the server return promises. A connection handles
one request at a time; a second request made meanwhile errors, but other
connections are not blocked. Call `$close()` when the conversation ends.
`$cancel()`, and any request that times out, stop the connection and
discard the server's session state; its tools then stop working.

mcptools waits about 4 seconds for a stdio server's reply and doesn't
match replies to requests, so a late or mismatched reply fails the call
with a `deputy_mcp_desynchronized` error and closes the connection.
Create a new connection to continue.

The connection is tied to the agent's ID, session and run context: its
tools can't be registered on another agent and stop working if the
agent's session changes. Connections are not saved with the agent's
session.

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

Start the server and connect to it.

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

  Name of the server in `config`.

- `agent`:

  The agent that owns the connection. The server starts in its working
  directory.

- `tools`:

  Names of the server tools to allow. None by default. The connection
  fails if the server doesn't offer all of them.

- `resources`:

  Resource URIs to allow. None by default.

- `prompts`:

  Prompt names to allow. None by default.

- `timeout`:

  Maximum seconds for each request. A request that takes longer closes
  the connection.

- `startup_timeout`:

  Maximum seconds for the client and server to start.

------------------------------------------------------------------------

### `McpConnection$status()`

Report the connection's state and allowlists.

#### Usage

    McpConnection$status()

#### Returns

A list with the connection's ID, server, owner, `state`, the `reason` it
closed, its allowlists and version details. It doesn't contact the
server.

------------------------------------------------------------------------

### `McpConnection$discover()`

List one page of what the server offers. Listing an item doesn't allow
it.

#### Usage

    McpConnection$discover(
      kind = c("tools", "resources", "resource_templates", "prompts"),
      cursor = NULL
    )

#### Arguments

- `kind`:

  One of `"tools"`, `"resources"`, `"resource_templates"`, `"prompts"`.

- `cursor`:

  Cursor from a previous page, or `NULL` for the first page.

#### Returns

A promise for a list with `source` (the server and connection) and the
server's `result`.

------------------------------------------------------------------------

### `McpConnection$read_resource()`

Read an allowed resource.

#### Usage

    McpConnection$read_resource(uri)

#### Arguments

- `uri`:

  An allowed resource URI. Links in the result are not followed.

#### Returns

A promise for a list with `source` and the server's `result`.

------------------------------------------------------------------------

### `McpConnection$get_prompt()`

Get an allowed prompt. The prompt is not added to any conversation.

#### Usage

    McpConnection$get_prompt(name, arguments = list())

#### Arguments

- `name`:

  An allowed prompt name.

- `arguments`:

  Named list of strings to fill in the prompt.

#### Returns

A promise for a list with `source` and the server's `result`.

------------------------------------------------------------------------

### `McpConnection$tools()`

Create tools for the allowed server tools, to register on the owning
agent.

#### Usage

    McpConnection$tools()

#### Returns

A named list of ellmer tools.

------------------------------------------------------------------------

### `McpConnection$capability_tools()`

Create `<prefix>_read_resource` and `<prefix>_get_prompt` tools that let
the model read allowed resources and get allowed prompts. Each is
created only if its allowlist isn't empty. Prompts that need arguments
can't be fetched this way.

#### Usage

    McpConnection$capability_tools(prefix = "mcp")

#### Arguments

- `prefix`:

  Prefix for the tool names: 1 to 50 letters, digits, underscores or
  hyphens. Use a different prefix for each connection on the same agent.

#### Returns

A named list of ellmer tools, possibly empty.

------------------------------------------------------------------------

### `McpConnection$cancel()`

Stop the connection at once and discard the server's session state.

#### Usage

    McpConnection$cancel()

#### Returns

`NULL`, invisibly. Safe to call more than once.

------------------------------------------------------------------------

### `McpConnection$close()`

Close the connection. If no request is running, the server is first
asked to shut down; then its processes are stopped.

#### Usage

    McpConnection$close()

#### Returns

`NULL`, invisibly. A request still running is rejected.
