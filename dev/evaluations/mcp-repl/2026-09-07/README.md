# 7 September 2026 qualification

The committed producer journey passed all 86 assertions with no failures,
errors, warnings or skips. Source:
`c4a232341c82a538b816d63bb5a25d708da95d16`.

The host used macOS arm64, R 4.6.1, mcptools 1.0.2, ellmer 0.5.0 and the
posit-mcp-repl 0.3.0 wheel installed into a temporary environment. The invocation
records the binary SHA-256 and all dependency versions. No model API was called.

The real R REPL kept a value across calls while another Agent using the same
server name could not see it. Its plot remained ellmer image content. A large
transcript returned fewer than 6,000 bytes with a truncation notice and an
accessible, larger full-output file. An interrupt after a busy response preserved
the value; reset and interpreter exit were each followed by a fresh state.
Closing one connection invalidated its handles while the second still worked.

The deterministic MCP producer covered exact selection, annotations, fixed
resource/prompt allowances, discovery without authorization, Agent permission and
hook paths, event-loop progress, overlap rejection, cancellation, timeout and
server crash. Agent interruption terminated its active connection and produced
an interrupted AgentResult.

The JSON files retain individual test names, outcomes and durations. The execution
log records the complete test run; `manifest.json` hashes those evidence files.
Rerun `../qualify.R` from the repository root with a new output directory to
repeat the journey. This observation does not establish other platforms,
Python runtime behavior, production Shiny load or external-catalogue scaling.
