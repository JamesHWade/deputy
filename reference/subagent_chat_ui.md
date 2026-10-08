# Show subagent conversations in a Shiny panel

A read-only Shiny module to place next to your main chat. Cards list the
agent's subagents; selecting one shows its conversation, with tool calls
and attachments, and streams its current output. A tool's card looks as
it did in the subagent's own chat, with scripts, event handlers, forms
and external resources removed from its HTML and its content kept inside
the card. The panel has no input box and can't start, resume or approve
work. It needs shiny, bslib, commonmark, xml2 and shinychat (\>= 0.5.0).

## Usage

``` r
subagent_chat_ui(id, height = "420px")

subagent_chat_server(
  id,
  lead,
  requester,
  history = NULL,
  disclosure = NULL,
  scope = NULL,
  on_cancel = NULL,
  poll_interval = 250L,
  conversation = NULL
)
```

## Arguments

- id:

  Shiny module ID.

- height:

  Height of the conversation view. Defaults to `"420px"`.

- lead:

  The `Agent` or
  [LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
  whose subagents to show, or a function returning it.

- requester:

  A function returning the current user, as your
  [DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  expects it. Access is checked on every update.

- history:

  Optional reactive or function returning history saved with
  `$export_subagents()`, to show instead of the live agent. Return
  `NULL` to show the live agent.

- disclosure, scope:

  For saved history, the
  [DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  and scope for
  [`delegation_history()`](https://jameshwade.github.io/deputy/reference/delegation_history.md),
  or functions returning them. Take them from your own records, not from
  the history or browser input.

- on_cancel:

  Optional `function(delegation_id, requester)` called when the user
  cancels a running subagent. Check that the requester may, then call
  the agent's `$interrupt_subagent()`. Without it, there is no cancel
  button.

- poll_interval:

  How often to check for updates, in milliseconds. At least 100;
  defaults to 250.

- conversation:

  Optional value returned by
  [`subagent_chat_history()`](https://jameshwade.github.io/deputy/reference/subagent_chat_history.md)
  for the lead's chat. The panel then shows the subagents of the
  conversation open in that chat: those that ran in it, live, and those
  saved with it, read-only.

## Value

`subagent_chat_ui()` returns a bslib card.

`subagent_chat_server()` returns a list of reactives: `selected` (the
selected delegation ID), `views`, `notice` and `closed`.
