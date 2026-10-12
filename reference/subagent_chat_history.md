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
subagent_chat_history(
  chat = NULL,
  lead,
  requester,
  max_bytes = 16 * 1024^2,
  conversation_id = NULL
)
```

## Arguments

- chat:

  The value returned by
  [`shinychat::chat_server()`](https://posit-dev.github.io/shinychat/r/reference/chat_app.html)
  for the lead's chat, or `NULL` (the default) when your app runs the
  lead's replies itself.

- lead:

  The [Agent](https://jameshwade.github.io/deputy/reference/Agent.md) or
  [LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
  given to `chat_server()` as its client, or whose replies your app
  streams into the chat.

- requester:

  A function returning the current user, as your
  [DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  expects it.

- max_bytes:

  Most bytes of records to save per conversation. Children that don't
  fit, here or in the `max_bytes` of the lead's `delegation_disclosure`,
  keep their outcome without their conversation, or are left out, and
  `status()` counts them. Defaults to 16 MiB.

- conversation_id:

  Only without `chat`: a function returning the ID of the conversation
  open in the chat, or `NULL` when none is. Defaults to reading
  `lead$conversation_id`.

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

- `conversation_id()`: the open conversation's ID, or `NULL`.

- Without `chat`, also `on_save(values)` and `on_restore(values)`, the
  callbacks for
  [`shinychat::chat_enable_history()`](https://posit-dev.github.io/shinychat/r/reference/chat_enable_history.html).
  `on_save` returns `values` with the conversation's records added.

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

## Apps that run the lead's replies themselves

If your app streams the lead's replies into the chat itself instead of
using
[`shinychat::chat_server()`](https://posit-dev.github.io/shinychat/r/reference/chat_app.html),
and keeps conversations with
[`shinychat::chat_enable_history()`](https://posit-dev.github.io/shinychat/r/reference/chat_enable_history.html),
leave out `chat`. The returned list then also holds `on_save` and
`on_restore`: pass them to `chat_enable_history()`. If you already have
your own `on_save`, call this one from inside it and return what it
returns; do the same with `on_restore`.

Records are kept under the ID of the conversation open in the chat,
which `chat_server()` otherwise looks after. Before each reply, set
`lead$conversation_id` to the ID of the conversation the reply belongs
to, as `chat_server()` does, so the subagents it starts are saved with
that conversation. shinychat's "new chat" empties the lead's
conversation, which sets `lead$conversation_id` back to `NULL`, so the
previous conversation's subagents stop showing until you set the next
ID. If you pass your own `conversation_id` function, make it return
`NULL` or the new ID after a new chat. shinychat also empties the lead
when the first message of a conversation is edited, and from the lead
the two look the same: the example below gives such an edit a new ID, so
the subagents from before the edit are no longer saved with that
conversation. When a conversation is reopened, its ID must be the open
one before `on_restore` runs: records saved under another ID are not
read. By default the open conversation's ID is read from
`lead$conversation_id`; pass `conversation_id` to read it from somewhere
else. For example, keeping the ID with the conversation itself:

    saved <- subagent_chat_history(lead = lead, requester = user)
    shinychat::chat_enable_history(
      "chat",
      lead,
      on_save = function(values) {
        values$conversation <- lead$conversation_id
        saved$on_save(values)
      },
      on_restore = function(values) {
        lead$conversation_id <- values$conversation
        saved$on_restore(values)
      }
    )
    shiny::observeEvent(input$chat_user_input, {
      if (length(lead$get_turns()) == 0) {
        lead$conversation_id <- new_conversation_id() # your own ID scheme
      }
      stream <- lead$stream_async(input$chat_user_input, stream = "content")
      shinychat::chat_append("chat", stream)
    })

## See also

[`subagent_chat_activity()`](https://jameshwade.github.io/deputy/reference/subagent_chat_activity.md)
to show subagent tool calls in the chat itself.
