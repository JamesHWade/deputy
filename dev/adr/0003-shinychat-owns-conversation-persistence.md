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
- **The record schema is shinychat's to change**, and deputy tracks it. This is not a reluctant cost. deputy and shinychat are meant to work well together and stay in sync, which means following upstream rather than insulating against it. Insulation would mean a translation layer, and a translation layer is how two packages drift apart while appearing to cooperate.

## Timing

The store is **unreleased**. `ConversationStore`, `FileConversationStore`, `chat_enable_history()` and `history_options()` are all in shinychat's development version (upstream #264, #266); CRAN has 0.4.0, which has none of it.

That is fortunate rather than a problem. An API that has not shipped can still change shape, so the export request in issue #66 arrives while it is cheap to act on — and better still as a pull request than an issue. After a release the same request competes against backward compatibility.

It does mean two things must be true before deputy can depend on this:

- CI has to test against shinychat's development version. Today it installs from CRAN, where the store does not exist, so nothing deputy writes against it would be exercised.
- deputy needs actual shinychat integration tests. There are currently none, despite ADR-0002 naming it the primary host.
