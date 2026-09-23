# Connect an Agent to a sandboxed MCP Console workbench

Creates a
[McpConnection](https://jameshwade.github.io/deputy/reference/McpConnection.md)
to one explicitly selected [MCP
Console](https://github.com/t-kalinowski/mcp-console) server. The server
keeps R, Python and DuckDB SQL state for one conversation. Each
connection starts its own server, owned by exactly one Agent. Register
its `$tools()` on that Agent so that `send` goes through the Agent's
normal permissions, hooks, limits and events.

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

  Agent that owns the connection. Its working directory is the Console
  workspace: the server's launch directory, sandbox workspace root,
  project-configuration location and recording location.

- command:

  Path to a qualified `mcp-console` executable. Defaults to the
  `DEPUTY_MCP_CONSOLE_BIN` environment variable. Deputy never installs
  or discovers the executable.

- args:

  Additional launch arguments for `mcp-console serve`. Only
  `--writable-root PATH` and the overrides `-c extends=:workspace`,
  `-c extends=:read-only` and `-c sandbox.network=restricted` are
  accepted. `--no-sandbox`, filesystem, proxy, target and other
  overrides are refused.

- env:

  Optional named character vector of environment variables for the
  server. mcptools passes the server only a fixed set of inherited
  variables (such as `HOME`, `PATH` and the `R_LIBS` family), so
  resolver settings such as `UV_CACHE_DIR` or `XDG_CACHE_HOME` must be
  given here. Without them, dependency preparation writes to caches
  under `HOME`.

- dependencies:

  `"deny"` (default) or `"allow"`. Dependency preparation runs outside
  the Console sandbox with the server's permissions. With `"deny"`,
  Deputy refuses a server that offers it, and refuses any call that
  declares `requirements`. See Details.

- project_config:

  Set to `TRUE` to launch even though `.agents/console/config.yaml`
  exists in the workspace. That file is trusted launcher input that can
  widen the sandbox. Deputy refuses to start when it exists unless the
  host has reviewed it and opts in.

- timeout:

  Maximum seconds for one MCP request.

- startup_timeout:

  Maximum seconds for client and server startup.

## Value

A
[McpConnection](https://jameshwade.github.io/deputy/reference/McpConnection.md).
The host must close it when the conversation ends.

## Details

### Qualification

This adapter is qualified for MCP Console 0.0.4 with mcptools 1.0.2 or
1.0.3. Before launch, Deputy runs `command --version` and refuses other
versions. After launch it checks the `send` tool contract, and the
security sentence that the server derives from its effective sandbox
policy. Only the native sandbox with restricted networking is accepted
(the default policy or the `:workspace` or `:read-only` profiles). An
unsandboxed, unrestricted, proxied, external, remote or container
boundary closes the connection. mcptools does not expose the server's
`serverInfo`, so the version check relies on the executable.

### Governance

`send` submits code with shell-class capability. In `"standard"` mode
the Agent's policy needs `bash = TRUE`. The server supplies no MCP
annotations, so the conservative defaults also require `web = TRUE`.
`"readonly"` and `"plan"` modes always deny `send`. A call that declares
`requirements` also needs `install_packages = TRUE`, and the connection
must allow dependencies.

With dependency preparation enabled, the server can also resolve
packages automatically, outside the sandbox, when evaluated code calls
[`library()`](https://rdrr.io/r/base/library.html) or imports a missing
Python module. Deputy cannot gate those per call; they are part of the
host's `dependencies = "allow"` decision. MCP Console offers preparation
when `ir`, `uv` or a recent reticulate is available to it. The
server-launch environment, not Deputy, decides where resolvers write.

### Response window

The qualified mcptools releases wait about 4 seconds for a stdio reply.
Deputy forwards `timeout_ms` capped at 2500 ms (also when omitted).
Longer work keeps running: the call returns
`[running; poll with an empty send]`, and a later `send` with no code
retrieves the output. The tool description tells the model this.
Upstream gives explicit dependency preparation, restart, and standard
input sent to a stopped worker no deadline. If one outlasts the window,
the connection closes with a `deputy_mcp_desynchronized` error and the
server session is lost. For that reason restart is a host control,
[`mcp_console_control()`](https://jameshwade.github.io/deputy/reference/mcp_console_control.md),
and the model-facing `send` refuses it.

### Lifecycle and recordings

`$close()` closes the server's input, which asks MCP Console to shut
down and retire its worker, then stops the process. `$cancel()`, an
Agent interrupt during an active call, and a desynchronized reply stop
the server without that shutdown request. The private sandbox runner
then retires the worker when it observes its parent exit. Descendants
that escape the runner's supervision are outside Deputy's control.

MCP Console records every call, result and plot, without redaction,
under `.agents/console/sessions/<run-id>/` in its working directory.
Version 0.0.4 has no setting for that location or its retention. Deputy
therefore uses the Agent's working directory, reports the path in
`$status()$execution$recordings`, and leaves retention to the host.

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-5.6-luna"),
  permissions = Permissions(bash = TRUE, web = TRUE)
)
console <- mcp_console_connection(agent, command = "/path/to/mcp-console")
agent$register_tools(console$tools())
# In a Shiny host: session$onSessionEnded(function() console$close())
console$close()
} # }
```
