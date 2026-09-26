# Trusted mini-agent: reviewed plant-weight analysis

The trusted mini-agent pattern from
[*Trusted Mini-Agents*](https://trustedminiagents.dev) by Will Landau and Sam
Parmar, applied to a small descriptive analysis: a subagent proposes the
analysis inputs, a person reviews them, and only a designated R tool computes
the result.

Run from a development checkout:

```r
devtools::load_all()
shiny::runApp("inst/examples/trusted-mini-agent")
```

Or from an installed package:

```r
shiny::runApp(system.file("examples", "trusted-mini-agent", package = "deputy"))
```

It needs shiny, bslib, shinychat (0.5.0 or later), commonmark, xml2 and
httpuv. A local test server stands in for the model, so there are no API keys
or paid requests. Approvals and the result file go in a temporary directory
that is deleted when the Shiny session ends. The app runs everything inside
one Shiny session; a deployed version needs real sign-in and private storage.

## What to try

1. Click "Draft a proposal". The lead agent delegates to an analyst subagent
   whose only tool records proposed analysis inputs. You can read the
   analyst's conversation in the panel at the bottom.
2. Click "Prepare input review". A separate executor agent requests the
   `compute_summary` tool, and the call pauses as a durable approval. Nothing
   has been computed yet.
3. Check the dataset revision, outcome, units, method, population and groups.
   Approve the proposed `trt2` comparison, or switch the treatment to `trt1`
   first. Denying or cancelling leaves the result panel empty.
4. Compare the result with the model's commentary, which is deliberately
   wrong: it says 999 grams, while the tool reports +2 grams for `trt2` or
   -1 gram for `trt1`. Approving again can't rerun the tool or overwrite the
   result.

## The data and the computation

The synthetic dataset has 12 plant weights in grams: control 4, 5, 6, 5;
`trt1` 3, 4, 5, 4; `trt2` 6, 7, 8, 7. The only method is the treatment mean
minus the control mean, using all complete observations. There is no
imputation, model fitting, significance test or causal claim.

The dataset revision is the SHA-256 of the observations as JSON. The inputs
must name that revision and the one supported method, outcome, units and
population. `compute_summary` validates them again just before it runs, and
edits made during review are validated before the approval is used.

## How the result is protected

The analyst's proposal and both model summaries are commentary. Only
`compute_summary` can produce the result: the executor declares
`TrustedResults(study_summary = "compute_summary")`, so Deputy refuses any
code execution, delegation, writing or open-world tool registered beside it,
and the model can't add tools. The result also appears as a `"trusted_result"`
event on the executor's run.

The result file records the inputs and their revision, the data revision, the
tool version, which subagent proposed the inputs, and the approval decision.
It is written once, no model tool can write it, and it is kept even if the
model fails afterwards. The workflow checks the requester for every action,
and the subagent panel separately checks who may view the analyst.

Both tools use ellmer's `convert = FALSE`, so they receive raw JSON arguments
and validate them with `study_validate()`; the declared schema only guides the
model. Deputy's durable approvals require this so that edited inputs can be
validated again when the call resumes.

Subagents can't pause for durable approval yet, so the app hands the analyst's
proposal to a separate executor agent instead of resuming the subagent. The
approval records are real, but the app doesn't rebuild its workflow after an R
restart. And approval only means a person checked the inputs; it doesn't make
the analysis scientifically correct.

## Tests

```r
devtools::test(filter = "^trusted-mini-agent$")
```

The tests check the arithmetic, edited, invalid and missing inputs, denied and
unauthorized requests, repeated decisions, cancellation, false model
summaries, an unregistered file-writing tool, a failure after the result was
written, and viewing the subagent without running it.

See Landau and Parmar's
[definition](https://trustedminiagents.dev/definition.html) of a trusted
mini-agent and `vignette("trusted-mini-agents", package = "deputy")`.
