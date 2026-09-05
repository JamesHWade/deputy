# Optional headless history adapter for shinychat

Deputy needs to retain original conversation evidence outside an Agent's compacted
context, then restore a selected conversation branch for a later governed run.
For hosts using shinychat, shinychat would own its conversation format and branch
semantics. Deputy owns permissions, run limits and execution state; the host
supplies authorized history as described in ADR-0003.

The concrete consumer is the [caller-owned recovery experiment](../inst/examples/history-recovery/README.md):
an evidence-review Agent reads source items, compacts repeatedly, and later recovers
an earlier correction through bounded search/read tools. Continue this work with
caller-owned records. Only the shinychat adapter waits for a public, released
contract; Deputy implementation and evaluation do not depend on that outcome.

## What already works

At shinychat development commit
[`eb024589`](https://github.com/posit-dev/shinychat/tree/eb024589465f5227405d567854b96cc87e5bb9ac/pkg-r),
`ConversationStore` and `FileConversationStore` are exported for framework-managed
history. The private partition constructor is intentional: custom store subclasses
receive framework-created partitions. That supported use case is valid.
The record's `values` field already holds application state from `on_save()`.
The managed conversation identity work in [#307](https://github.com/posit-dev/shinychat/issues/307)
also supplies stable identity before model work. We do not propose replacing it.

The extra use case is a worker without an active Shiny session. Direct record
construction and branch edits currently require knowledge of private helpers and
tree fields. Store methods also rely on the framework for schema validation.

## Minimal consumer sequence

The following is pseudocode for desired operations, not proposed export names:

```r
# Host resolves identity and admission; model arguments cannot select the owner.
history <- open_history(store, owner_scope = authenticated_owner, chat_id = "review")
conversation <- history$create()
history$append(conversation$id, turns = agent$get_turns())
history$set_values(conversation$id, deputy = list(run_id = result$run_id))

# In a later worker, with the same explicitly authorized owner/chat scope:
history$list()
saved <- history$load(conversation$id)
branch <- history$fork(saved$id, at = selected_item_id)
history$select_branch(saved$id, branch$id)
restored <- history$read_branch(saved$id, branch$id)
chat$set_turns(restored$turns)  # Supported ellmer turns, with settled tool pairs.
```

The smallest useful contract would document:

- Headless create/list/load/update with explicit owner and chat scope, using the
  same schema checks as framework-managed operations.
- Branch creation, selection and restoration without mutating `nodes`,
  `selected_child` or `current_leaf`. Stable source identity or a documented
  snapshot/revision boundary lets a bounded reader detect stale references.
- App metadata association through `values` or another supported surface,
  including replacement/merge behavior and whether it follows a conversation
  or a branch. Deputy can namespace/version its own payload; shinychat need not
  understand Deputy's run schema.

A higher-level headless controller is equally suitable; exporting a partition
constructor alone would not address branch operations and schema validation.
Native full-text search is not required: the host can search an authorized
branch snapshot and enforce its own Agent/branch restrictions and read budgets.
Conversation metadata and retrieved prose never restore execution permissions
or spend an approval. The host resolves those from its current execution state.

## Discussion and release gate

Checked existing headless/history/branch issues on 2026-09-05; discussions are
disabled. [#375](https://github.com/posit-dev/shinychat/issues/375) concerns attaching
context to managed submissions, which is useful but does not provide this worker
history boundary. The R development version is `0.4.0.9000`; the `r/v0.4.0` release
does not contain the store API. Python release tags do not change the R gate.

Await feedback on the existing upstream proposal and record the outcome in
Deputy #66. If accepted, link the supported R release when implementing the
adapter. Work on #62 and the hosted part of #43 should use the host-owned boundary
in ADR-0003 and assess their own requirements independently. Do not copy the
shinychat store or use private APIs while the discussion is pending.

Upstream proposal: [posit-dev/shinychat#391](https://github.com/posit-dev/shinychat/issues/391), opened 2026-09-05. The design outcome and public R release remain pending; Deputy #66 stays open.
