# Adapt MCP Console as a sandbox-first workbench

`mcp_console_connection()` connects one Agent to one
[MCP Console](https://github.com/t-kalinowski/mcp-console) server through the
existing `McpConnection` machinery. MCP Console keeps R, Python and DuckDB SQL
state in one sandboxed worker for a conversation. This ADR records the trust
boundary of that adapter (#190).

## Context

MCP Console grew out of mcp-repl, which ADR-0005 made Deputy's OS-sandbox seam.
It offers one MCP tool, `send`, over stdio. It is a development preview:
version 0.0.4 is on PyPI, the R package is GitHub-only, and only macOS and
Linux are supported. Its ellmer adapter, `mcp.console::console_tool()`,
blocks the R session during a call, relies on garbage collection for
shutdown, installs the latest release through uv when none is on `PATH`, and
verifies no sandbox. It does not meet Deputy's ownership, lifecycle or
fail-closed requirements, and it is not on CRAN (ADR-0004).

## Decision

- The seam is an MCP connection through mcptools, like
  `mcp_repl_connection()`. Deputy takes no dependency on the upstream R
  package or Python distribution. The host installs a qualified executable
  and names it explicitly (`command` or `DEPUTY_MCP_CONSOLE_BIN`).
- **Qualified versions.** Deputy runs `command --version` before launch and
  accepts only an explicit list, currently `0.0.4`. mcptools does not expose
  `serverInfo`, so the executable's report is the version gate. The `send`
  schema must use only the qualified fields.
- **Sandbox first.** Deputy builds `serve` itself and admits only
  `--writable-root` and the overrides `extends=:workspace`,
  `extends=:read-only` and `sandbox.network=restricted`. `--no-sandbox`,
  filesystem kinds, proxies, targets and other overrides are refused. A
  `.agents/console/config.yaml` in the launch directory is trusted launcher
  input that can widen the sandbox (unrestricted or external filesystems,
  proxies, SSH or container targets), so Deputy refuses to start when it
  exists unless the host passes `project_config = TRUE`. After launch Deputy
  reads the security sentence that the server derives from its effective
  policy and appends to the `send` description. Only the native sandbox with
  restricted networking is accepted: the default policy or the `:workspace`
  or `:read-only` profiles. Anything else, including unknown prose, closes the
  connection. Version 0.0.4 exposes no structured sandbox state, so this
  sentence is the only runtime evidence. There is no unsandboxed mode.
- **Governance.** `send` is code execution with shell-class capability. It
  goes through the Agent's permissions, hooks, limits and events. Standard
  mode requires `bash = TRUE`; because the server supplies no annotations,
  the conservative MCP defaults also require `web = TRUE`. `readonly` and
  `plan` modes deny `send` whatever annotations a server supplies.
- **Dependency preparation runs outside the sandbox** with the server's
  permissions and may download and build packages. It is its own policy
  class. `dependencies = "deny"` (the default) refuses a server that offers
  it: MCP Console 0.0.4 also resolves packages automatically, outside the
  sandbox, when code calls `library()` or imports a missing module, and the
  client cannot turn that off. With `dependencies = "allow"`, calls that
  declare `requirements` also need the Agent's `install_packages` grant.
  Automatic resolution remains part of the host's connection-level decision.
- **Response window.** mcptools 1.0.2/1.0.3 wait about 4 seconds for a stdio
  reply (#196). Deputy forwards `timeout_ms` capped at 2500 ms, so long cells
  return `[running; poll with an empty send]` and a later empty `send`
  collects the output. Restart, explicit dependency preparation, and standard
  input sent to a stopped worker have no upstream deadline. Restart is a host
  control (`mcp_console_control()`); the model-facing `send` refuses it. A
  restart or preparation that outlasts the window closes the connection with
  a typed error; the server session is lost, and the host creates a new
  connection.
- **Lifecycle.** Interrupt and restart map to `send(control = ...)`. Close
  first closes the server's input, MCP Console's shutdown signal, then stops
  the process. Cancel, Agent interruption during a call, and a desynchronized
  reply stop it directly. The private sandbox runner owns descendant cleanup
  and retires its worker when it sees its parent exit; descendants that escape
  it are outside Deputy's control.
- **Recordings.** MCP Console writes unredacted transcripts, source, stdin,
  requirements, outputs and plots under `.agents/console/sessions/<run-id>/`
  in its working directory, with no retention quota. Version 0.0.4 has no
  setting for this location. Deputy launches the server in the Agent's working
  directory, reports the recording path in `status()$execution`, and leaves
  retention to the host.
- **Output.** Text and plots arrive as ellmer text and inline image content
  through mcptools' converter; Deputy's rich-result bounds apply to them.

## Composition is blocked upstream

#187 asked whether MCP Console offers a supported channel for code in the
sandboxed worker to request a host-governed tool call and receive data. It
does not. The worker and relay protocols are private and unversioned,
`send(stdin = ...)` is untyped and has no request identity, and the only
socket allowance is a macOS network setting, not a contract. Worker-originated
composition (ADR-0028) therefore stays on the trusted callr worker until an
upstream contract exists; #187 records the proposed producer contract.

## Consequences

- Hosts get a persistent three-language workbench without Deputy running
  model code outside an OS sandbox.
- Most installations offer dependency preparation, so hosts must decide
  `dependencies = "allow"` explicitly. A bare runtime avoids it but has no
  Python unless an older reticulate is installed.
- The adapter depends on upstream prose for sandbox verification and on
  mcptools internals; a new MCP Console or mcptools release needs
  requalification.

## References

- MCP Console v0.0.4: `README.md`, `docs/SEND_OPERATIONS.md`,
  `docs/SANDBOX_CONFIGURATION.md`, `docs/REQUIREMENTS.md`,
  `src/server/execution.rs`
- ADR-0004, ADR-0005, ADR-0028; issues #187, #190, #196
