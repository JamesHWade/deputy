# shinychat owns conversation persistence

deputy and shinychat both persist conversations: deputy through `Agent$save_session()` / `load_session()` / `session_id()`, shinychat through `ConversationStore` with its own ids, partitions and scoping. shinychat's store is authoritative. deputy's job is to produce and consume conversation state, not to own where it lives.

## Why

shinychat's model is strictly richer. A stored record is a **tree** — `nodes` with `selected_child` links, a `current_leaf` pointer, and helpers that walk a path from root to leaf — because branching is what edit, retry and regenerate need in the UI. deputy's snapshot is a flat serialization of one conversation. Anything deputy built on top of its own format would have to grow into that tree eventually, and would then be a second, worse implementation of a structure that already exists.

The store also works headless. `FileConversationStore$new(dir)` instantiates and round-trips outside a Shiny session, so deferring to it does not make persistence Shiny-only and stays consistent with ADR-0002.

## Consequences

- **Conversation forking is largely already built.** `current_leaf` plus `nodes` is a branching model; a fork is selecting a different leaf, not copying a record. See issue #62, whose scope shrinks accordingly.
- **deputy needs API from shinychat that is currently internal.** `conversation_partition()` is unexported, so a partition — required by every `put()`, `get()` and `list()` call — cannot be constructed by another package without `:::`, which is not acceptable in a released package. The branching helpers (`record_set_current_leaf()`, `record_path_node_ids()`, `record_subtree_leaf()`) are likewise internal. **This decision is blocked on an upstream export request.**
- **`save_session()` / `load_session()` become the headless fallback**, not the primary mechanism, and should not grow features that duplicate the store.
- **Correlation is still deputy's problem.** `Agent$session_id()` and a shinychat conversation id are different identifiers, and runs, delegations and checkpoints key off deputy's. The mapping between them has to be explicit.
- **The record schema is shinychat's to change.** deputy inherits a compatibility dependency on `schema_version`. This is the cost of the decision and is accepted deliberately.
