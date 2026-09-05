# Track released versions of ellmer and shinychat

deputy's primary compatibility target is the released dependency set available
from CRAN. `DESCRIPTION`, contributor setup, and the required CI matrix must be
installable without `Remotes:` or development-only version floors.

This supersedes the development-only policy originally recorded here. That
policy was deliberately temporary: it expired when deputy began preparing its
first CRAN submission and its required upstream versions were available on
CRAN.

## Why

A CRAN package must be reproducible from released dependencies. Making that
environment the primary target catches dependency floors, accidental use of
unreleased APIs, and installation failures before submission. It also gives
users and contributors one supported setup rather than a GitHub-only graph.

Focused compatibility work against upstream development versions remains
valuable. It is an early-warning signal, but it cannot define the required
installation path or silently raise deputy's supported floor before an
upstream release exists.

## Consequences

- `DESCRIPTION` does not contain `Remotes:` and names only released minimum
  versions.
- Required CI checks release R on Ubuntu, macOS, and Windows against released
  dependencies.
- Upstream development versions may be tested in an explicitly experimental
  job or local compatibility pass, but that signal does not replace the
  released-dependency matrix.
- Features that require unreleased upstream APIs wait behind a release or use
  a documented optional boundary; they do not enter the CRAN package through
  an undeclared development dependency.
- Issue #67's development-only dependency target is superseded by this release
  policy.

## Released ellmer 0.5.0 adoption (2026-09-04)

Deputy now requires ellmer >= 0.5.0, published on CRAN on 2026-09-04.
The integration uses public request-start/end callbacks for streaming model
rounds, `conversation_id` for tracing, model objects, and native structured
streaming. Structured async calls in 0.5.0 bypass the request callbacks, so
Deputy counts that public method's dispatch explicitly. Neither signal exposes
individual HTTP retries. No upstream private provider, schema, or telemetry
implementation is copied.

The pre-CRAN `output_format` path was removed. Ellmer types and converted values
are the sole structured-output contract; existing JSON Schema enters through
`ellmer::type_from_schema()`. This is an intentional pre-release API change,
without a compatibility shim or Deputy validator dependency.

Evidence: [ellmer on CRAN](https://cran.r-project.org/package=ellmer) and
[ellmer 0.5.0 source](https://github.com/tidyverse/ellmer/tree/v0.5.0).
