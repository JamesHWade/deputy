# Worker event qualification, 7 September 2026

All 128 assertions passed with no failures, errors, warnings or skips at source
`c766135042b42e15424907da3bf879e9a784fe6c`.

This repeats the real R lifecycle journey after the worker-event and direct
argument-binding review fixes. Real-process regressions verify caller variables,
once-only argument evaluation, omitted optional arguments, forwarded conditions
during initialization and requests, and retained server state on the next call.
The earlier qualification archives remain unchanged.

The recorded host used macOS arm64, R 4.6.1, mcptools 1.0.2, ellmer 0.5.0 and
posit-mcp-repl 0.3.0. No model API was called. The real R journey also covers
persistent and isolated state, plots, bounded previews with accessible full
transcripts, interrupt, reset, interpreter exit, stale handles and cleanup.

The invocation records the binary hash and dependency versions. Individual
outcomes and durations are in results.json; execution.txt records the complete
run. manifest.json hashes these evidence files. Reproduce with
`dev/evaluations/mcp-repl/qualify.R` and a new output directory. These observations
do not establish other platforms, Python behavior, production Shiny load or
external-catalogue scaling.
