# Delegate OS sandboxing to mcp-repl

Deputy treats its built-in R and shell tools as trusted-code execution. It does
not implement a second operating-system sandbox. Model-generated R that needs
confinement runs through an explicitly configured mcp-repl server loaded by
`tools_mcp_repl()`.

## Context

Deputy's permission system gates tool calls, write roots, and open-world
capabilities at the application boundary. Once `tool_run_r_code` or
`tool_run_bash` starts, however, that code has the current user's filesystem
and network authority. `callr` provides a fresh R process, failure isolation,
and a timeout; it is not a security boundary.

Implementing confinement inside Deputy would duplicate platform-sensitive
machinery already maintained by Posit's mcp-repl: Seatbelt profiles on macOS,
filesystem namespaces plus seccomp on Linux, and restricted-account machinery
on Windows. A partial reimplementation would create two superficially similar
policies with different guarantees and patch cadence.

## Decision

- `permissions_standard()` denies arbitrary R and shell execution.
- `tools_preset("standard")` does not register a code-execution tool.
- `tool_run_r_code`, `tool_run_bash`, and `tools_code()` remain available for
  explicitly trusted workflows. Their documentation never calls them
  sandboxed.
- `tools_mcp_repl()` is Deputy's supported OS-sandbox seam. It reads one exact
  server entry, verifies that the command is mcp-repl, and requires the final
  CLI policy to equal the caller's requested `"read-only"` or
  `"workspace-write"` policy before starting the server.
- The helper refuses an implicit default, `danger-full-access`,
  `external-sandbox`, and `inherit-codex`. Inherited Codex policy requires
  per-call metadata that mcptools does not provide, so accepting it would defer
  the check until after Deputy had advertised a guarantee it cannot establish.
- mcp-repl owns platform detection and enforcement. A missing prerequisite or
  unsupported host must fail server startup; Deputy never substitutes a weaker
  local runner.

## Threat model

The mcp-repl boundary is intended to constrain filesystem writes, filesystem
reads when the selected profile restricts them, and network access according to
the configured mcp-repl policy. Its exact guarantees and platform limitations
are mcp-repl's public contract, not Deputy's application permission model.

The boundary does not claim to make model output correct, prevent excessive
provider spending, protect secrets deliberately mounted into an allowed root,
undo authorized file changes, or constrain Deputy tools running outside that
mcp-repl process. Run limits, least-authority permissions, credential hygiene,
and file checkpoints remain separate controls.

Deputy's validation protects against policy ambiguity and silent downgrade in
its own integration. It cannot attest to a substituted executable at an
otherwise trusted path, a compromised host, or defects in the operating system
or mcp-repl.

## Consequences

- Existing code that relied on the standard policy to execute R must opt into a
  trusted-code permission or configure mcp-repl.
- Deputy gains one small, inspectable integration contract instead of a broad
  cross-platform security subsystem.
- The sandbox implementation and threat model remain independently testable by
  the project that owns them, while Deputy tests exact configuration parsing
  and fail-closed selection.
- New execution backends need their own explicit trust and enforcement
  contract; adding a tool to a preset does not establish one.

## References

- [mcp-repl sandbox contract](https://github.com/posit-dev/mcp-repl/blob/main/docs/sandbox.md)
- [mcp-repl source](https://github.com/posit-dev/mcp-repl)
- Deputy issue #32
