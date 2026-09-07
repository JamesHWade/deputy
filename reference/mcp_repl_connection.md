# Connect an Agent to an independent sandboxed REPL

Creates a
[McpConnection](https://jameshwade.github.io/deputy/reference/McpConnection.md)
for one explicitly configured mcp-repl server. Each connection owns an
independent client and upstream interpreter session. Register its
`$tools()` on the supplied Agent to retain normal permissions, hooks,
budgets and execution provenance.

## Usage

``` r
mcp_repl_connection(
  config = NULL,
  agent,
  server = "r",
  sandbox = c("workspace-write", "read-only"),
  timeout = 60,
  startup_timeout = 60
)
```

## Arguments

- config:

  Path to an mcptools configuration. Defaults to
  `~/.config/mcptools/config.json`.

- agent:

  Agent that owns the connection.

- server:

  Exact configured mcp-repl server name.

- sandbox:

  Required explicit upstream sandbox policy.

- timeout:

  Maximum seconds for one MCP request. This is distinct from mcp-repl's
  `timeout_ms`, which can return a busy result while code continues.

- startup_timeout:

  Maximum seconds for client/server startup.

## Value

A
[McpConnection](https://jameshwade.github.io/deputy/reference/McpConnection.md).
The host must close it when the conversation ends.

## Details

The producer contract is qualified with mcptools 1.0.2 and mcp-repl
0.3.0. The executable must be installed and configured by the host.
mcp-repl owns interpreter startup, sandbox enforcement, reset,
interrupt, rich content and oversized-output artifacts. The client
requires its `repl(input, timeout_ms)` tool contract; it does not infer
a binary version from the executable name.

A busy interpreter result is upstream output, not a completed
calculation. After such a response,
[`mcp_repl_control()`](https://jameshwade.github.io/deputy/reference/mcp_repl_control.md)
can request an interrupt or reset. An active client request cannot
accept a second request: use `$cancel()` to terminate the connection and
discard state, or wait for the request to return. Interrupting the
owning Agent also cancels its active MCP connections.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(chat = ellmer::chat("openai/gpt-5.6-luna"))
connection <- mcp_repl_connection(agent = agent)
agent$register_tools(connection$tools())
# In a Shiny host: session$onSessionEnded(function() connection$close())
connection$close()
} # }
```
