# Reviewed stack qualification, 7 September 2026

All 93 assertions passed with no failures, errors, warnings or skips at source
`2f049800f8ca7d1391def60d0e920dd34154be9c`.

This repeats the original real R journey after the execution-time ownership fix,
HTTP-configuration rejection, and history report corrections. The new ownership
regressions verify that clone/session loading and per-run context overrides are
rejected before dispatch. The original 86-assertion archive remains unchanged.

The recorded host used macOS arm64, R 4.6.1, mcptools 1.0.2, ellmer 0.5.0 and
posit-mcp-repl 0.3.0. The invocation records the binary SHA-256 and dependency
versions. No model API was called. The real journey covers persistent and isolated
R state, image content, bounded previews with accessible full transcripts,
interrupt, reset, interpreter exit, stale handles and cleanup.

`results.json` retains individual outcomes; `execution.txt` records the complete
run. `manifest.json` hashes these files and the invocation. Reproduce with
`dev/evaluations/mcp-repl/qualify.R` and a new output directory. These observations
do not establish other platforms, Python behavior, production Shiny load or
external-catalogue scaling.
