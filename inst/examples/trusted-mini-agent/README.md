# Trusted mini-agent: reviewed plant-weight analysis

An application of the trusted mini-agent pattern from
[*Trusted Mini-Agents*](https://trustedminiagents.dev) by Will Landau and Sam
Parmar to a descriptive scientific computation.

Run from a development checkout:

```r
devtools::load_all()
shiny::runApp("inst/examples/trusted-mini-agent")
```

Or from an installed package:

```r
shiny::runApp(system.file("examples", "trusted-mini-agent", package = "deputy"))
```

The example needs the suggested shiny, bslib, shinychat, commonmark, xml2 and
httpuv packages. It uses a separate local HTTP fixture through real ellmer public
APIs. There are no paid model calls, credentials, patient data or external writes.
The host stores approvals and one JSON result receipt in a fresh temporary directory.
The Shiny session removes these demonstration files when it disconnects.
For deployment, configure an authenticated requester and host-owned private storage.
The example itself is an in-process, per-Shiny-session demonstration.

## What to try

1. Draft a proposal. The lead delegates to an analyst that can only propose typed
   analysis inputs. Inspect the child conversation if desired.
2. Prepare input review. A separate host-owned execution Agent requests the
   designated `compute_summary` tool and suspends through Deputy's existing
   durable approval protocol. No analysis has run yet.
3. Review the data revision, outcome, units, method, population and groups. Approve
   the proposed `trt2` comparison, or edit the treatment to `trt1` before approval.
   Denial and cancellation must leave the result panel empty.
4. Compare the computed panel with deliberately false model commentary. The model
   says 999 grams; the tool result is +2 grams for `trt2`, or -1 gram for `trt1`.
   Repeated approval cannot execute again or overwrite the receipt.

## The scientific computation

The fixed, clearly synthetic dataset has 12 plant weights in grams: four control
observations (4, 5, 6, 5), four `trt1` observations (3, 4, 5, 4), and four `trt2`
observations (6, 7, 8, 7). Subject identifiers are unique. The only supported method
is treatment mean minus control mean, using all complete observations. There is
no imputation, model fitting, statistical significance test or causal claim.

The dataset revision is SHA256 of the canonical JSON observations. Inputs must
name that exact revision and the supported method, outcome, units and population.
The designated tool validates again immediately before execution. A host edit
is validated before consuming the pending decision and recorded in the approval
journal and receipt. This example is a descriptive scientific workflow, not
clinical evidence or an evaluation of model quality.

## Trust and ownership

- The analyst's proposal and both model summaries are untrusted commentary.
- Only `compute_summary` can publish the authoritative result. The executor
  declares it with `TrustedResults(study_summary = "compute_summary")`, so
  Deputy rejects any code-execution, delegation, write or open-world tool
  registered beside it. The registry cannot be extended by model input. The
  result also appears as a `"trusted_result"` event on the executor's run.
- The host checks requester authorization for proposing, preparing, deciding,
  cancelling and reading. The child viewer applies its own disclosure checks.
- The receipt includes the canonical inputs and their revision, data revision,
  tool/version, proposing child delegation, execution identities and approval
  decision/effect association. The result is retained even if later model text
  fails. The journal separately records whether the tool completed or failed.
- Receipt storage is an example host responsibility, not a new Deputy database.
  It is append-once in this workflow and unavailable as a model write capability.
  It is not an OS sandbox or protection against a malicious host R process.
- Child durable approval continuation is not implemented. The host explicitly
  hands the child's proposal to a standalone governed executor, preserving the
  source delegation in provenance. It does not silently revive the child.
- Durable approval records are real, but this example does not reconstruct the
  complete host workflow after process restart. Production recovery needs the
  host's persisted receipt/ownership associations and effect reconciliation.

Trusted tools, correct data, appropriate analysis choices and effective human
review remain necessary. Approval does not establish scientific correctness.

Both tools use ellmer's `convert = FALSE`: functions receive raw JSON arguments
and validate their own complete schema and domain constraints. The declared tool
schema guides the model; it is not a substitute for `study_validate()`. Deputy's
durable approval API requires this raw-argument contract so edited inputs can be
revalidated and replayed without calling ellmer's private conversion machinery.
The same validated inputs bind the decision, tool effect and receipt.

## Verification

```r
devtools::test(filter = "^trusted-mini-agent$")
```

Tests use real public ellmer transport and Deputy approvals. They independently
check known arithmetic, edited inputs, invalid/missing evidence, denied and
unauthorized requests, duplicate decisions, cancellation, false model summaries,
an attempted unregistered file-writing tool,
partial failure after a completed effect, and observation without execution.

See issue #154, ADR-0023, ADR-0030, and Landau and Parmar's
[definition](https://trustedminiagents.dev/definition.html) for the intended
contract.
