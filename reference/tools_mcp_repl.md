# Load sandboxed R tools from mcp-repl

Loads the tools of one [mcp-repl](https://github.com/posit-dev/mcp-repl)
server, which runs R inside an OS sandbox. Use it when model-written
code must not have your full user access;
[tool_run_r_code](https://jameshwade.github.io/deputy/reference/tool_run_r_code.md)
and
[tool_run_bash](https://jameshwade.github.io/deputy/reference/tool_run_bash.md)
can reach your files and network.

The server's configuration entry must run the mcp-repl executable over
stdio with `--sandbox` set to `sandbox`. A missing flag, a different
mode, or a mode that doesn't guarantee a sandbox (`inherit`,
`inherit-codex`, `external-sandbox`, `danger-full-access`) is an error.
For a connection owned by one agent that you can interrupt, reset and
close, use
[`mcp_repl_connection()`](https://jameshwade.github.io/deputy/reference/mcp_repl_connection.md).

## Usage

``` r
tools_mcp_repl(
  config = NULL,
  server = "r",
  sandbox = c("workspace-write", "read-only")
)
```

## Arguments

- config:

  Path to an mcptools JSON configuration. Defaults to
  `~/.config/mcptools/config.json`.

- server:

  Name of the server in `config`. Defaults to `"r"`, the name mcp-repl's
  installation examples use.

- sandbox:

  The sandbox mode the server must use. `"workspace-write"` limits
  writes to the configured workspace roots; `"read-only"` blocks
  workspace writes. Network access follows the server's own
  configuration.

## Value

A list of tools from the server. The `repl` tool waits at most 3 seconds
per call (see
[`mcp_repl_connection()`](https://jameshwade.github.io/deputy/reference/mcp_repl_connection.md));
longer work returns a busy result, and a later call with empty `input`
collects its output.

## Examples

``` r
if (FALSE) { # \dontrun{
repl_tools <- tools_mcp_repl(
  config = "~/.config/mcptools/config.json",
  server = "r",
  sandbox = "workspace-write"
)
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = repl_tools,
  permissions = Permissions(web = FALSE)
)
} # }
```
