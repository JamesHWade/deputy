# Connect an agent to a sandboxed mcp-repl session

Starts one mcp-repl server from an mcptools configuration and connects
it to `agent`. mcp-repl runs R inside an OS sandbox and keeps variables
between calls; each connection has its own R session. Register
`connection$tools()` on the agent so that calls go through its
permissions, hooks and limits. The server entry must pass `--sandbox`,
as described in
[`tools_mcp_repl()`](https://jameshwade.github.io/deputy/reference/tools_mcp_repl.md).

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

  The agent that owns the connection.

- server:

  Name of the mcp-repl server in `config`.

- sandbox:

  The sandbox mode the server must be configured with.

- timeout:

  Maximum seconds to wait for one MCP request before closing the
  connection. This is separate from the per-call `timeout_ms` limit
  described in Details.

- startup_timeout:

  Maximum seconds for the client and server to start.

## Value

A
[McpConnection](https://jameshwade.github.io/deputy/reference/McpConnection.md).
Call its `$close()` method when the conversation ends.

## Details

Supported with mcptools 1.0.2 or 1.0.3 and mcp-repl 0.3.0. You install
and configure the mcp-repl executable yourself; it handles the sandbox,
interrupts, resets, rich output and large outputs. The connection errors
if the server's `repl` tool doesn't take exactly the arguments `input`
and `timeout_ms`.

mcptools waits only about 4 seconds for a reply, so each `repl` call
waits at most 3 seconds: `timeout_ms` is capped at 3000 and defaults to
3000 (instead of mcp-repl's 60 seconds). Longer work keeps running: the
call returns a busy result, and a later call with empty `input` collects
the rest of the output. The tool description tells the model this.

A busy result means the code hasn't finished. Use
[`mcp_repl_control()`](https://jameshwade.github.io/deputy/reference/mcp_repl_control.md)
to interrupt it or reset the session. A connection handles one request
at a time; `$cancel()` ends the connection and discards the R session.
Interrupting the agent also cancels its active MCP connections.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(chat = ellmer::chat("openai/gpt-6-luna"))
connection <- mcp_repl_connection(agent = agent)
agent$register_tools(connection$tools())
# In a Shiny app: session$onSessionEnded(function() connection$close())
connection$close()
} # }
```
