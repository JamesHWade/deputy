# Save subagent records with a shinychat conversation

Keeps the subagents of each conversation in a shinychat chat with that
conversation, so reopening it, after a reload or in a new session,
brings back what each subagent did: its task, outcome, conversation with
tool results and their cards, usage, and where it sat among the other
subagents. The records come back read-only. Nothing is run again, no
subagent is resumed, and the lead's model doesn't see them; it keeps the
short summary each subagent returned. Show them in the subagent panel by
passing the returned value to
[`subagent_chat_server()`](https://jameshwade.github.io/deputy/reference/subagent_chat_ui.md)
as `conversation`, or read them with `restored()`.

## Usage

``` r
subagent_chat_history(chat, lead, requester, max_bytes = 16 * 1024^2)
```

## Arguments

- chat:

  The value returned by
  [`shinychat::chat_server()`](https://posit-dev.github.io/shinychat/r/reference/chat_app.html)
  for the lead's chat.

- lead:

  The [Agent](https://jameshwade.github.io/deputy/reference/Agent.md) or
  [LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
  given to `chat_server()` as its client.

- requester:

  A function returning the current user, as your
  [DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  expects it.

- max_bytes:

  Most bytes of records to save per conversation. Children that don't
  fit, here or in the `max_bytes` of the lead's `delegation_disclosure`,
  keep their outcome without their conversation, or are left out, and
  `status()` counts them. Defaults to 16 MiB.

## Value

Invisibly, a list of functions:

- `restored(transcript = TRUE, delegation_id = NULL)`: the subagents
  saved with the open conversation, as
  [`delegation_history()`](https://jameshwade.github.io/deputy/reference/delegation_history.md)
  returns them, or `NULL`. With `transcript = FALSE`, without their
  conversations, each marked `retention$transcript = "not_requested"`
  (or `"omitted"` when it wasn't saved). With `delegation_id`, only that
  saved subagent, whose conversation is kept if it fits the disclosure's
  `max_bytes` on its own.

- `status()`: the open conversation's ID, how many subagents its saved
  record holds, how many were still running, saved without their
  conversation (too large, or removed by the disclosure's `redact`) or
  left out at the last save (including subagents left out earlier that
  can't be found again, such as an earlier session's or those released
  since), and any problem saving or reading it. A user the lead's
  `delegation_disclosure` doesn't let see them gets no counts, and a
  note saying so.

## Details

Records are saved through the chat's history callbacks each time
shinychat saves the conversation, as one JSON text, so any history store
can hold them. A subagent still running at that point is saved the next
time. Access is checked with the lead's
[DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
when records are saved and every time they are read. A save adds the
lead's subagents only when `requester` may also inspect them on the
lead; otherwise it keeps the ones saved before. When reading them back,
`authorize` gets a `scope` holding the lead's `delegation_scope` and the
conversation's ID as `chat_conversation_id`; records saved under another
scope are not read. Large results that subagents saved to disk are kept
as references, which may no longer resolve. Needs shiny and shinychat
(\>= 0.5.0) with history enabled.

## See also

[`subagent_chat_activity()`](https://jameshwade.github.io/deputy/reference/subagent_chat_activity.md)
to show subagent tool calls in the chat itself.
