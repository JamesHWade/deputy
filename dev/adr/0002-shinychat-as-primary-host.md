# Design for shinychat as the primary host, keep headless first-class

Most deputy agents are expected to run inside a Shiny application using shinychat, not in a terminal or a script. Design decisions should presume that host: async by default, per-session agent lifecycle, and human-in-the-loop expressed as UI. Headless and CLI use remain fully supported — some agents will always run that way — so no capability may depend on Shiny being present.

## Why

deputy's users are R users, and the way R work reaches non-R colleagues is a Shiny app. An agent that only runs in a terminal reaches the person who wrote it. shinychat already supplies the chat UI, streaming, conversation history and per-user scoping, so building on it costs little and skips a large amount of undifferentiated work.

Presuming the host matters because the blocking-versus-async choice is not neutral. In a single-process Shiny app a blocking call freezes every connected session, not just the caller's. Decisions that look equivalent for a CLI tool are not equivalent here, and the difference is invisible until someone deploys.

## Consequences

- **Blocking calls in a shared path are defects, not limitations.** `LeadAgent` inherits `run_shiny()` while delegating through a blocking `run_sync()`; under this ADR that is a bug (issue #63), not a missing feature. `Agent$run_async()`, added in PR #64, is the primitive that fixes it.
- **Two persistence layers now overlap.** deputy has `save_session()` / `load_session()` / `session_id()`; shinychat has `ConversationStore` with its own ids and scoping. Ownership must be settled rather than left ambiguous. Conversation forking is where the overlap becomes unavoidable (issue #62).
- **Human-in-the-loop is a UI concern.** `tool_ask_user` was designed around a console prompt. Under a Shiny host, approval gating is a modal and an event, and pending state has to outlive a reactive flush (issue #43).
- **No hard dependency on Shiny.** shiny, shinychat and promises stay in `Suggests`. A capability that cannot work headless needs an explicit, documented reason.
- **"Most but not all" is the hard part.** The temptation is one API that works beautifully under Shiny and degrades silently elsewhere. Prefer an API that behaves identically in both, even where that costs more.
