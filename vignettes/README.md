# Vignette Docs Workflow

This project uses explicit docs execution tiers for pkgdown content.

## Status values

- `verified-replay`: Executed in pkgdown CI with deterministic replay chats.
- `verified-vcr`: Executed in pkgdown CI with recorded `vcr` cassettes.
- `illustrative`: Rendered but not executed in pkgdown CI.

## Required article pattern

Each article should:

1. Call `deputy_docs_init()` in its setup chunk.
2. Render a status note via `docs$status_block()`.
3. Mark runnable chunks with `eval = docs$should_eval`.
4. Mark illustrative snippets with explicit `eval = FALSE` rather than relying
   on a global chunk default.

## Refreshing docs

- Default local mode is `DEPUTY_DOCS_MODE=off`.
- Use `DEPUTY_DOCS_MODE=replay` for deterministic pkgdown/CI builds.
- Use `DEPUTY_DOCS_MODE=record` only when refreshing replay fixtures or `vcr`
  cassettes.
- Validate docs sources: `Rscript scripts/check-docs.R`
- Build runnable README + pkgdown site: `Rscript scripts/build-docs.R`
- Refresh recorded cassettes: `Rscript scripts/record-docs.R`

## Notes

- Prefer replay chats for agent loop examples that do not need live provider
  fidelity.
- Use `docs$use_vcr()` only for examples where the real HTTP/provider path is
  important to demonstrate.
