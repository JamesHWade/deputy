# CI feedback time

Issue: #183. Target: closer to two minutes for ordinary PR feedback, using
standard R package tooling. Keep the complete Linux behavioral suite. Broader
validation runs after merge; a PR run does not certify Windows/macOS or coverage.

## Measured baseline (2026-09-20)

Merged main `cfff431`, [package checks](https://github.com/JamesHWade/deputy/actions/runs/35534655392)
and [coverage](https://github.com/JamesHWade/deputy/actions/runs/35534655393):

| Work | Elapsed |
| --- | ---: |
| Linux job | 23m 10s |
| Linux package-check step | 21m 23s |
| Windows job | 28m 23s |
| Windows package-check step | 26m 57s |
| Coverage step | 44m 16s |
| Linux / Windows dependency setup | 46s / 38s |
| Duplicate standalone-example precheck | 11s / 13s |
| Executable installation job | 4m 17s |

These are observed runs, not performance guarantees. Serial tests and coverage
instrumentation dominate; setup is already mostly cached.

The complete installed-package check using native four-worker testthat finished
locally in 5m 52.7s (test phase: 300.4s), with 7,910 passing expectations, no
failures, and zero R CMD check errors, warnings, or notes. A separate targeted
coverage run passed all 39 process-test expectations; another probe verified
coverage trace collection across native parallel workers. These measurements do
not include GitHub runner queue or setup time.

## Standard execution policy

- PRs run Air, the documentation build, and ordinary Linux R CMD check, including
  every test file and the standalone examples. There is no custom test runner,
  matrix sharding, changed-file filtering, or tests-free package-check result.
- Testthat runs files in its supported native worker pool. The package declares
  `Config/testthat/parallel: true`; CI configures four workers. The standard
  `Config/testthat/start-first` setting starts the measured slow files first.
  The exploratory run measured history recovery at 210s, compaction evidence
  at 119s, trusted mini agents at 101s, recursive delegation at 94s, and
  compaction runs at 84s. Starting these early reduces idle workers at the end.
- Pushes to main/master and manual dispatch also run full Windows/macOS package
  checks, both executable installation modes, and full instrumented coverage.
- New PR commits cancel obsolete validation runs. Main validations remain
  independent. The known macOS archive problem is tracked in #182; Claude review
  behavior is unchanged.

Set the setup-r action's `Ncpus: 4` input, not just `TESTTHAT_CPUS=4`:
setup-r defaults R's `Ncpus` option to one, and testthat prioritizes that option.
This was confirmed in an exploratory GitHub run whose log showed one worker
despite the environment variable requesting four.

An eight-job sharding experiment was removed to keep the workflow standard and
simple. The two-minute target is not yet achieved; do not trade away behavioral
coverage merely to label the check fast.

## Validation and measurement

Run `TESTTHAT_CPUS=4 Rscript -e 'devtools::test()'` for local testing, or ordinary
`devtools::check()` for the complete installed-package check. If a local R
profile sets `options(Ncpus=...)`, update that option to match the desired worker
count. Set `TESTTHAT_PARALLEL=false` for sequential debugging.

Read job and step timestamps from `gh run view <run> --json jobs`. Include
queue/setup time in PR latency and distinguish that from the test phase. The
Actions log must report `Starting 4 test processes.` for the full suite.

Subprocess tests coordinate readiness and observable effects rather than assume
cold R startup meets a fixed latency. The cancellation test keeps its provider
response behind a gate, proving cancellation persists while IO is outstanding.

Reference: [testthat parallel testing](https://testthat.r-lib.org/articles/parallel.html).
