# CI feedback time

Issue: #183. Target: approximately two minutes for ordinary PR feedback, without
omitting files from the Linux behavioral suite. Broader validation runs after
merge; a fast PR run does not certify Windows/macOS or instrumented coverage.

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

The preceding PR run had a 25m 11s Linux check step. These are observed runs,
not a stable performance guarantee. Setup is already mostly cached; serial tests
and coverage instrumentation dominate. Local four-worker exploration completed
the full suite in 312.9s, finding an approval example's implicit `utils` search
path dependency. The explicit namespace fix passes in parallel workers. The subsequent complete
installed-package check finished in 5m 52.7s (tests: 300.4s), with 7,910 passing
expectations, no failures, and zero R CMD check errors, warnings, or notes.
These local measurements do not include GitHub runner queue or setup time.
The first shard completed in 27.7s locally (778 passing expectations); all 92
files were verified to appear exactly once across the eight partitions.
Deliberately failing, invalid-argument, and empty-test fixtures return nonzero.

The first sharded GitHub run exposed an additional configuration bottleneck:
`setup-r` defaults `options(Ncpus = 1)`, which testthat prioritizes over
`TESTTHAT_CPUS=4`. Its logs showed only one worker per shard. The workflows now
set the action's `Ncpus: 4` input explicitly, and the runner rejects a mismatch
between the requested and configured worker limits.

## Execution policy

- PRs: Air, documentation build, Linux package check, and eight test shards.
  Every discovered test file is assigned exactly once, with four native testthat
  workers per shard. No tests are selected merely by changed filenames.
- Linux package checks skip their own test phase because the shards execute it;
  package loading, examples, documentation, and other checks remain enabled.
- Pushes to main/master and manual dispatch also run full Windows/macOS package
  checks and both executable installation modes. Coverage runs the complete suite
  with instrumentation, including subprocess tests.
- Obsolete PR runs are cancelled. Main validations remain independent.
- The known macOS dependency archive problem remains tracked in #182. Claude
  review behavior is unchanged.

This trades more concurrent Linux runners for shorter wall time. It does not
promise a two-minute cold dependency install or a two-minute post-merge coverage
run. The existing `ubuntu-latest (release)` status aggregates the package check and
all eight shards, failing on failed, cancelled, or skipped prerequisites.
Repository branch-protection settings are not changed by these workflow edits.

## Reproducing and measuring

Run `TESTTHAT_CPUS=4 Rscript .github/scripts/run-tests.R 1 8` from the repository
root, changing the first number for each shard. Use
`TESTTHAT_PARALLEL=false` for sequential debugging. GitHub uploads result and
wall-time artifacts from each shard. A reporter that buffers parallel events
(such as `summary`) cannot provide meaningful per-test elapsed values; the runner
uses the native parallel progress reporter instead.

Read job and step timestamps from `gh run view <run> --json jobs` and include
queue/setup time when reporting PR latency. A fast test step alone does not meet
the target. Record the slowest shard and total workflow duration; rebalance only
when measured skew justifies added scheduling complexity.

Tests that coordinate subprocesses must wait for readiness and observable effects,
not assume package startup finishes within a few seconds. The cancellation test
keeps its provider response behind a gate, proving that cancellation persists
while provider IO remains outstanding; it does not time a cold R subprocess.

Reference: [testthat parallel testing](https://testthat.r-lib.org/articles/parallel.html).
