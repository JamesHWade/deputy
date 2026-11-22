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

## Temporary GitHub coro dependency (2026-09-24)

CRAN coro 1.1.0 builds each generator and async instance with a unique closure
body, so R's JIT recompiles the whole state machine on every instance
(r-lib/coro#71). In Deputy that was 73 to 85% of main-process test CPU and about
0.3 to 0.7 s of CPU per model request (#185, #192). The fix, r-lib/coro#72, is
merged but unreleased.

The maintainer accepted a GitHub dependency until coro releases the fix.
`DESCRIPTION` requires `coro (>= 1.1.0.9000)` with `Remotes: r-lib/coro`, which
tracks coro's main branch. GitHub dependencies are deliberately not pinned to a
commit: the maintainer prefers following upstream development over freezing a
revision, and CI surfaces any upstream break. This is a deliberate, time-limited
exception to this ADR's release policy:

- The required CI matrix installs coro's current main branch.
- CRAN submission (#86) is blocked until a coro release includes #72. At that
  point remove `Remotes:` and require the released version.
- coro's main branch also contains unreleased 2025 generator-environment
  changes (r-lib/coro#67). The full suite and R CMD check qualified main at
  a8efdec; later upstream changes are qualified by ordinary CI runs.

## Temporary GitHub httr2 dependency (2026-11-22)

Deputy uses httr2's development branch while the streaming fix in
[r-lib/httr2#919](https://github.com/r-lib/httr2/pull/919) is unreleased.
`DESCRIPTION` requires httr2 >= 1.3.0.9000 and declares `r-lib/httr2` as a
remote. httr2's own `Remotes` entry selects a curl build with
[jeroen/curl#460](https://github.com/jeroen/curl/pull/460), which must also
be installed for the fix to take effect.

When response headers arrive promptly, `Agent$stream_async()` and
`Agent$chat_async()` can service the R event loop while waiting for the body.
A provider or proxy that holds back the headers can still block the R
process. [Deputy #200](https://github.com/JamesHWade/deputy/issues/200) tracks
that remaining delay and qualification of the released transport. Repeat
both delay cases with the loopback probe before dropping the httr2 remote
and returning to released dependencies.
