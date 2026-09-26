# Connect an agent to a sandboxed MCP Console session

Starts an [MCP Console](https://github.com/t-kalinowski/mcp-console)
server for one agent and connects to it. MCP Console runs R, Python and
DuckDB SQL in an OS sandbox and keeps their state for the conversation.
Each connection starts its own server. Register `connection$tools()` on
the agent so that the `send` tool goes through its permissions, hooks
and limits.

## Usage

``` r
mcp_console_connection(
  agent,
  command = Sys.getenv("DEPUTY_MCP_CONSOLE_BIN"),
  args = character(),
  env = NULL,
  dependencies = c("deny", "allow"),
  project_config = FALSE,
  timeout = 60,
  startup_timeout = 60
)
```

## Arguments

- agent:

  The agent that owns the connection. Its working directory becomes the
  Console workspace, where the server starts, the sandbox's workspace is
  rooted, and MCP Console reads its project configuration and writes
  recordings.

- command:

  Path to an `mcp-console` executable, version 0.0.4. Defaults to the
  `DEPUTY_MCP_CONSOLE_BIN` environment variable. Deputy doesn't install
  the executable or search for it.

- args:

  Extra arguments for `mcp-console serve`. Only `--writable-root PATH`
  and the overrides `-c extends=:workspace`, `-c extends=:read-only` and
  `-c sandbox.network=restricted` are accepted. Anything else, including
  `--no-sandbox`, is an error.

- env:

  Optional named character vector of environment variables for the
  server. The server inherits only a few variables (such as `HOME`,
  `PATH` and the `R_LIBS` family), so set others here, for example
  `UV_CACHE_DIR` or `XDG_CACHE_HOME`. Without them, dependency installs
  write to caches under `HOME`.

- dependencies:

  `"deny"` (the default) or `"allow"`. MCP Console can install packages
  that code needs, and it does so outside its sandbox, with the server's
  permissions. With `"deny"`, the connection errors if the server offers
  this, and calls that declare `requirements` are refused. See Details.

- project_config:

  Set to `TRUE` to start even though the workspace contains
  `.agents/console/config.yaml`. That file can widen the sandbox, so by
  default the connection refuses to start when it exists. Review the
  file before you opt in.

- timeout:

  Maximum seconds for one MCP request.

- startup_timeout:

  Maximum seconds for the client and server to start.

## Value

A
[McpConnection](https://jameshwade.github.io/deputy/reference/McpConnection.md).
Call its `$close()` method when the conversation ends.

## Details

### Supported versions

Requires MCP Console 0.0.4 and mcptools 1.0.2 or 1.0.3. The connection
checks the version with `command --version` before starting the server.
After starting, it checks the arguments of `send` and the sandbox
description MCP Console adds to it, and closes the connection unless the
server uses its native sandbox with restricted networking (the default
policy, or the `:workspace` or `:read-only` profile).

### Permissions

`send` runs code, so it is treated like a shell tool: in `"standard"`
mode the agent's permissions need `bash = TRUE`. The server declares no
tool annotations, so the cautious defaults also require `web = TRUE`.
`"readonly"` and `"plan"` modes always deny `send`. A call that declares
`requirements` also needs `install_packages = TRUE` and a connection
created with `dependencies = "allow"`.

With `dependencies = "allow"`, the server can also install packages on
its own, outside the sandbox, when code calls
[`library()`](https://rdrr.io/r/base/library.html) for a missing package
or imports a missing Python module. These installs can't be checked call
by call. MCP Console offers dependency installs when `ir`, `uv` or a
recent reticulate is available to it. The server's environment decides
where they are written.

### Long-running calls

mcptools waits about 4 seconds for a reply, so each `send` waits at most
2.5 seconds: `timeout_ms` is capped at 2500, also when omitted. Longer
work keeps running: the call returns
`[running; poll with an empty send]`, and a later `send` with no code
collects the output. The tool description tells the model this. Installs
requested with `requirements`, restarts, and input sent to a stopped
worker have no time limit in MCP Console. If one takes longer than the
reply window, the connection closes with a `deputy_mcp_desynchronized`
error and the session is lost. That is why only you can restart the
session, with
[`mcp_console_control()`](https://jameshwade.github.io/deputy/reference/mcp_console_control.md);
the model's `send` refuses it.

### Closing and recordings

`$close()` asks MCP Console to shut down cleanly, then stops the
process. `$cancel()`, interrupting the agent during a call, and a lost
reply stop the server without asking; MCP Console's sandbox runner then
stops its worker. Processes that escape the runner are outside Deputy's
control.

MCP Console records every call, result and plot, without redaction,
under `.agents/console/sessions/<run-id>/` in the workspace. Version
0.0.4 can't change that location or how long recordings are kept. The
path is reported in `$status()$execution$recordings`; deleting old
recordings is up to you.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  permissions = Permissions(bash = TRUE, web = TRUE)
)
console <- mcp_console_connection(agent, command = "/path/to/mcp-console")
agent$register_tools(console$tools())
# In a Shiny app: session$onSessionEnded(function() console$close())
console$close()
} # }
```
