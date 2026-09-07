# Active execution qualification, 7 September 2026

All 171 assertions passed with no failures, errors, warnings or skips at source
`dda9add596d3bab2cc8606b23b8b1bc9adc8ce7f`.

This repeats the real R lifecycle journey after active MCP executions retained
cancellation independently of the mutable tool registry. Real-producer regressions
remove or replace a tool during its pending request and then interrupt the Agent;
the original connection closes while the requested registry change remains.
Another regression clones an Agent with a pending execution and an empty registry,
then verifies that the clone cannot cancel a later request after the original
promise settles. Earlier archives remain unchanged.

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
