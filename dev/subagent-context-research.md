# Subagent context and lifecycle research

Research date: 2026-09-17. This is a source-based design proposal and backlog,
not implementation or runtime verification. No paid model experiments were run.

## Recommendation

Make delegation an inspectable contract: a bounded input, an effective authority
and budget, an owned lifecycle, and a result whose provenance survives synthesis.
Keep fresh conversations as the default. Support selected evidence first; evaluate
full conversation forks as an explicit host-provided option. Continue to distinguish
reusable AgentDefinition values, task input, host `run_context`, retained transcript,
and the working context governed by ContextPolicy.

Use one implementation behind host methods and model-facing delegation tools.
Mutable lifecycle owners fit the existing R6 convention; immutable input, inspection,
and outcome values fit S7. Exact public names remain design decisions. Do not expose
private Chat state or add a second conversation database.

## Source currency and evidence

| Source | Version or date | Evidence type |
| --- | --- | --- |
| [Deputy](https://github.com/JamesHWade/deputy/commit/12c60de84fe811fd784f9ffa6f9c64db143eb165) | Main, 2026-09-09 | Inspected source and current issues |
| [btw](https://github.com/posit-dev/btw/commit/473d1d8e3114ed9136692ff3fb6b88ed0474ba66) | v1.5.0, released 2026-09-09 | Inspected source and tests |
| [Trusted Mini-Agents](https://trustedminiagents.dev/) | Will Landau and Sam Parmar, published 2026-08-28 | Author guidance |
| [Mini-agent R examples](https://github.com/wlandau/trustedminiagents/commit/0261d650d2bce9122d20fa0618b78a0e98aff80d) | 2026-09-11 | Inspected example code |
| [Claude Code subagents](https://code.claude.com/docs/en/sub-agents) | Living documentation read 2026-09-17 | Documented product behavior; version-sensitive |
| [Anthropic Managed Agents](https://www.anthropic.com/engineering/managed-agents) | 2026-04-08 | First-party architecture report |
| [Intelligent AI Delegation](https://arxiv.org/html/2602.11865v1) | 2026-02-12, v1 | Research proposal, not a standard |
| [Google agent scaling research](https://research.google/blog/towards-a-science-of-scaling-agent-systems-when-and-why-agent-systems-work/) | 2026-01-28 | First-party empirical report |
| [Anthropic agent evaluations](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) | 2026-01-09 | Evaluation guidance |
| [shinychat R](https://github.com/posit-dev/shinychat/releases/tag/r/v0.5.0) | Released 2026-09-13 | Release plus source inspection |

Dates above are publication, release, or commit dates, not search crawl dates.
The older [context-engineering article](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
(2025-09-29) and [multi-agent research account](https://www.anthropic.com/engineering/multi-agent-research-system)
(2025-06-13) are background: bounded high-signal context, retrievable evidence, and
independent subtasks remain useful ideas, but should not determine current defaults
without newer evidence and Deputy-specific evaluation.

## What btw actually does

The generic tool accepts a task prompt, tool selection, and optional `session_id`.
A new call constructs a Chat; later calls can reuse it. The lead is returned the
last response wrapped with the session identifier. A separate display includes the
prompt, provider/model, tools, token information, and expandable conversation and
tool results. This is a useful precedent for compact model output plus detailed
host inspection. See the pinned [implementation](https://github.com/posit-dev/btw/blob/473d1d8e3114ed9136692ff3fb6b88ed0474ba66/R/tool-agent-subagent.R).

The same implementation reveals important limits:

- Sessions live in a package-level R environment. This is in-process continuation,
  not durable job recovery or an owner-authorized session service.
- A resume retrieves the existing Chat without rerunning its creation function;
  creation-time tools/configuration are not a fresh authorization decision.
- Tool defaults can resolve broadly; an optional allowlist narrows them. Explicit
  disallowed requests error, while defaults are filtered. The generic subagent
  tool is filtered to discourage recursion; this is not a transitive resource policy.
- No parent transcript is automatically passed by this tool. However, configured
  Chat objects are cloned without an explicit history clear in these constructors;
  fresh-context guarantees require testing populated Chat templates too.

Custom agents use markdown definitions and the same session machinery. Deputy
should retain its explicit YAML registries and inert loading under ADR-0006,
rather than copy automatic discovery or process-global configuration. See the
[custom-agent implementation](https://github.com/posit-dev/btw/blob/473d1d8e3114ed9136692ff3fb6b88ed0474ba66/R/tool-agent-custom.R).

The [subagent prompt](https://github.com/posit-dev/btw/blob/473d1d8e3114ed9136692ff3fb6b88ed0474ba66/inst/prompts/btw-subagent.md)
encourages focused work and useful partial answers when inputs or capabilities
are missing. Its [tests](https://github.com/posit-dev/btw/blob/473d1d8e3114ed9136692ff3fb6b88ed0474ba66/tests/testthat/test-tool-agent-subagent.R)
cover tool filtering, session reuse, and escaping untrusted report markup.
These were read, not executed. Deputy should similarly test report serialization
and safe rendering, not just successful model replies.

## Lessons from Trusted Mini-Agents

Landau and Parmar describe a trusted execution pattern rather than a subagent
orchestration library. Trusted tools directly produce final results through
designated paths, with human oversight of inputs. The claimed assurance depends
on correct inputs and trustworthy tools; it does not validate arbitrary model prose.
See the [formal definition](https://trustedminiagents.dev/definition.html).

The [R weather example](https://github.com/wlandau/trustedminiagents/blob/0261d650d2bce9122d20fa0618b78a0e98aff80d/r-weather.qmd)
executes the weather tool immediately and displays coordinates for inspection
beside results sourced directly from the tool. It does not implement a blocking
approve-before-execution gate. The [template](https://github.com/wlandau/trustedminiagents/blob/0261d650d2bce9122d20fa0618b78a0e98aff80d/r-template.qmd)
separates conversation, input inspection, and trusted output.

For Deputy, build a bounded scientific recipe with validated proposed inputs,
an explicit approval gate where required, one designated result writer, and a
host-owned immutable result receipt. Preserve tool identity, input revision,
units, data provenance, and approval/effect references through delegation and
synthesis. A lead summary remains commentary; it cannot replace the authoritative
result or claim verification from a successful stop reason. This is our adaptation,
and it should compose existing approvals rather than create a second approval engine.

## Recent guidance and its limits

Current [Claude Code documentation](https://code.claude.com/docs/en/sub-agents#manage-subagent-context)
distinguishes fresh context, forks, retained conversations, partial returns,
cancellation, and resumption. Agent messages do not grant permission. Borrow those
explicit distinctions, not product-specific defaults. Context isolation does not
imply filesystem, process, or tool-state isolation.

The [Managed Agents architecture](https://www.anthropic.com/engineering/managed-agents)
separates durable session events, the calling harness, and execution environments.
Its model-dependent context workaround illustrates why context policies should
remain replaceable. For Deputy, durable event ordering and effect reconciliation
belong with #42; a saved Chat is not a live continuation.

[Intelligent AI Delegation](https://arxiv.org/html/2602.11865v1) proposes explicit
responsibility, authority, monitoring, and verifiable completion. Translate these
into a small task brief and measurable outcome contract, without treating the
paper as an implemented universal protocol.

[Google's January 2026 study](https://research.google/blog/towards-a-science-of-scaling-agent-systems-when-and-why-agent-systems-work/)
compares 180 configurations and finds task-dependent gains and losses. Independent
subtasks can benefit; sequential dependencies and coordination overhead can erase
the benefit. Its benchmark figures are not predictions for Deputy. Keep delegation
opt-in and compare against a single-Agent baseline at comparable total budgets.

[January 2026 evaluation guidance](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
supports outcome checks alongside transcript inspection, deterministic and human
assessment, and latency/token/cost measurement. Define the protocol early; do not
infer model quality from mocked lifecycle tests or a single successful demo.

## Current Deputy baseline and gaps

At the pinned main revision, [LeadAgent](https://github.com/JamesHWade/deputy/blob/12c60de84fe811fd784f9ffa6f9c64db143eb165/R/agents-multi.R)
creates fresh Agents, clears inherited Chat turns/tools, derives permission and
usage ceilings, and retains settled results. Ordinary resolved results are recorded
as completed regardless of their stop reason; [parallel responders](https://github.com/JamesHWade/deputy/blob/12c60de84fe811fd784f9ffa6f9c64db143eb165/R/parallel-delegate.R)
distinguish other stops. The inspection list is populated at settlement, not admission.
The two paths need common lifecycle semantics and live records.

Child construction does not explicitly bind lead hooks or `approval_dir`. The
definition selects tools, which may themselves capture mutable state. Therefore
static permission inheritance alone does not define host approval routing,
interactive input, scoped R workers, or cleanup ownership. Host policy must explicitly
bind or reject these cases before delegation; blindly copying every hook or closure
would introduce different bugs.

Already implemented and to be reused:

- S7 AgentDefinition values, explicit YAML registries, permission ceilings,
  budget accounting, compaction, and one-request stateless fan-out.
- [ADR-0017](adr/0017-conversation-and-model-context.md): `get_turns()` retains
  the selected transcript; `get_context_turns()` exposes working model context;
  schema-3 snapshots retain both. This supersedes the older audit's history assumptions.
- [ADR-0016](adr/0016-durable-approval-continuations.md) and closed #43: durable
  approval control records and effect-aware resume. Whole delegation trees are
  outside that completed contract and remain #42 work.
- [ADR-0003](adr/0003-shinychat-owns-conversation-persistence.md): hosts own durable
  history, identity, and branches. Metadata is not an authorization credential.

shinychat R 0.5.0 is now released. Its [exports](https://github.com/posit-dev/shinychat/blob/r/v0.5.0/pkg-r/NAMESPACE)
include store classes; [partition](https://github.com/posit-dev/shinychat/blob/r/v0.5.0/pkg-r/R/chat_history_store.R)
and [branch helpers](https://github.com/posit-dev/shinychat/blob/r/v0.5.0/pkg-r/R/chat_history_types.R)
remain private. The upstream [headless proposal](https://github.com/posit-dev/shinychat/issues/391)
was still open with no comments when checked. Refresh #62/#66's release wording,
but keep the public-contract gate for that optional adapter. Core selected context
and host-supplied forks need not wait for it.

## Delivery order

The linked GitHub backlog is the execution source of truth. The first tranche
defines bounded context and correct lifecycle outcomes, then binds host authority
and execution resources explicitly. In-process continuation and host inspection
build on those contracts. The trusted mini-agent recipe proves them in a useful
workflow. Evaluation fixtures and the protocol can begin immediately; comparative
live trials wait for executable variants and explicit paid-run authorization.

Existing #42 remains the durable background/transitive-budget work. Existing #62
owns host-supplied forks and the optional shinychat integration. No new worker pool,
conversation store, automatic delegation default, or blanket correctness guarantee
is proposed. Implementation tickets include independent verification, missing
evidence, refusal, partial results, cancellation, and authority isolation.

Roadmap: [#148](https://github.com/JamesHWade/deputy/issues/148).

| Ticket | Deliverable | Implementation prerequisites |
| --- | --- | --- |
| [#149](https://github.com/JamesHWade/deputy/issues/149) | Bounded input and resolved-context manifest | Contract design first |
| [#150](https://github.com/JamesHWade/deputy/issues/150) | Live records and correct stop outcomes | Independently ready |
| [#151](https://github.com/JamesHWade/deputy/issues/151) | Host policy and execution-resource binding | #149 |
| [#152](https://github.com/JamesHWade/deputy/issues/152) | Owned handles and in-process continuation | #149, #150, #151 |
| [#153](https://github.com/JamesHWade/deputy/issues/153) | Compact outcomes and detailed host inspection | #149, #150 |
| [#154](https://github.com/JamesHWade/deputy/issues/154) | Trusted mini-agent scientific recipe | #151, #153 |
| [#155](https://github.com/JamesHWade/deputy/issues/155) | Paired evaluation and default-policy decision | Protocol now; executable variants later |
| [#42](https://github.com/JamesHWade/deputy/issues/42) | Existing durable job and transitive-budget work | #152 |
| [#62](https://github.com/JamesHWade/deputy/issues/62) | Existing fork work, with host-first scope | #149, #151; optional adapter also needs #66 |

GitHub sub-issues and native dependency edges express this ordering. The evaluation
ticket remains unblocked for fixture/protocol design; its body identifies the
implementation dependencies for later comparisons. Only #150 is marked ready for
autonomous implementation; the new public contracts require design triage. The
existing #42 remains marked for human implementation. The research PR does not
close the implementation roadmap.
