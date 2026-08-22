# Track the development versions of ellmer and shinychat

deputy develops and tests against the **development** versions of ellmer and shinychat, not their CRAN releases. `DESCRIPTION` should declare development floors and a `Remotes:` field pointing at the upstream repositories, and CI should install from those sources.

## Why

deputy is built on ellmer and hosted by shinychat (ADR-0002), and defers conversation persistence to shinychat's store (ADR-0003). That store is development-only — CRAN's shinychat 0.4.0 does not have it. Building against releases would mean deferring every capability by a release cycle, and designing against an API a cycle behind the one the maintainers are actually shaping.

Staying current also changes when problems surface. An upstream change that breaks deputy is found the week it lands, while the maintainer still has it in mind and the fix is a conversation. Found at release time it is deputy's emergency, and the window for influencing the design has closed.

The same currency is what makes upstream contribution possible. The export request in issue #66 is only well timed because deputy is looking at unreleased code.

## Consequences

- **`Remotes:` must be removed before CRAN submission.** CRAN does not accept it, and every dependency must be a released version. This ADR therefore has an expiry: at submission time deputy must be buildable against CRAN releases of ellmer and shinychat, which means those releases must have landed first. That is a real scheduling dependency on two other packages, and it is accepted deliberately.
- **CI must install from development sources**, otherwise it tests something nobody runs. See issue #67.
- **Version floors should name development versions** — `ellmer (>= 0.4.2.9000)`, `shinychat (>= 0.4.0.9000)` — so an install that silently resolved to CRAN fails loudly rather than at first use.
- **Upstream breaking changes are deputy's to absorb promptly**, not to work around. See ADR-0003 on why insulation is the wrong instinct.
- **Contributors need the dev versions installed.** This should be stated in the development setup instructions, not discovered through a confusing failure.
