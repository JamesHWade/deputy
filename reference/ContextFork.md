# Capture conversation turns for a fork

Records turns from one of your conversations, and where they came from,
so
[`fork_agent()`](https://jameshwade.github.io/deputy/reference/fork_agent.md)
can start a new agent from them. Deputy doesn't check the owner,
conversation, branch or revision; your `authorize` function in
[`fork_agent()`](https://jameshwade.github.io/deputy/reference/fork_agent.md)
confirms them. The copy keeps text, tool calls and results, but not tool
functions, hidden thinking or provider-specific data. A tool call
without its result, or a result without its call, becomes plain text,
and provider file uploads are replaced by a note.

## Usage

``` r
ContextFork(
  owner_id = NULL,
  conversation_id = NULL,
  branch_id = NULL,
  revision = NULL,
  fork_point = NULL,
  view = c("transcript", "context"),
  turns = list(),
  max_bytes = 64 * 1024,
  max_turns = 256L,
  schema_version = 1L
)
```

## Arguments

- owner_id:

  ID of the user or account that owns the conversation.

- conversation_id:

  ID of the source conversation.

- branch_id:

  ID of the branch the turns come from.

- revision:

  Revision of the conversation the turns come from.

- fork_point:

  Where the fork starts: a turn number (0 or more) or a string of your
  own.

- view:

  `"transcript"` if `turns` come from the full conversation (as from
  `$get_turns()`), `"context"` if they come from the current model
  context (as from `$get_context_turns()`). It is only recorded; you
  choose the turns.

- turns:

  A list of ellmer user and assistant turns, or records of them from
  [`ellmer::contents_record()`](https://ellmer.tidyverse.org/reference/contents_record.html).

- max_bytes:

  Maximum size of the copied turns, in bytes. Defaults to 64 KiB.

- max_turns:

  Maximum number of turns. Defaults to 256.

- schema_version:

  Format version; must be `1L`.

## Value

A `ContextFork` object. It is read-only; read its fields with `$`.
