# Capability review qualification, 7 September 2026

All 115 assertions passed with no failures, errors, warnings or skips at source
`d2eee8af0c2f98f1dbbcdcdc96b1d7d842403bc5`.

This repeats the real R lifecycle journey after the capability review fixes and
stack rebase. New strict producers advertise only resources or only prompts and
reject unsupported methods. They connect without a tools/list request. Another
journey registers and calls four capability tools from two connections on one
Agent using distinct prefixes, verifying each connection ID and producer log.
The earlier 86- and 93-assertion archives remain unchanged.

The recorded host used macOS arm64, R 4.6.1, mcptools 1.0.2, ellmer 0.5.0 and
posit-mcp-repl 0.3.0. No model API was called. The real R journey continues to
cover persistent and isolated state, plots, bounded previews with accessible
full transcripts, interrupt, reset, interpreter exit, stale handles and cleanup.

The invocation records the binary hash and dependency versions. Individual
outcomes and durations are in results.json; execution.txt records the complete
run. manifest.json hashes these evidence files. Reproduce with
`dev/evaluations/mcp-repl/qualify.R` and a new output directory. These observations
do not establish other platforms, Python behavior, production Shiny load or
external-catalogue scaling.
