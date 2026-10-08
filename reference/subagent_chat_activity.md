# Show subagent tool calls in the main chat

Adds the tool calls the lead's subagents make, with their results, to
the lead's conversation in a shinychat chat, as they happen. Each call
shows as a tool card in the reply that delegated it, labelled with the
subagent's name; a second delegation to the same name is numbered, and a
subagent's own subagents say whom they ran for. A card looks as it did
in the subagent's own chat (a Commons table or plot, say), with scripts,
event handlers, forms and external resources removed from its HTML.

## Usage

``` r
subagent_chat_activity(chat, lead, requester, interval = 100L)
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
  expects it. Access is checked each time new calls are read.

- interval:

  How often to look for new calls while the lead waits on a subagent, in
  milliseconds. At least 50; defaults to 100.

## Value

Invisibly, a list with [`stop()`](https://rdrr.io/r/base/stop.html),
which stops adding calls. Ending the Shiny session also stops it. A lead
shows activity in one chat at a time: calling `subagent_chat_activity()`
again for the same lead before
[`stop()`](https://rdrr.io/r/base/stop.html) is an error. Called again
after [`stop()`](https://rdrr.io/r/base/stop.html) during a reply, it
shows calls from the next reply on.

## Details

The cards are part of the conversation shinychat saves, so a restored
conversation shows them again without running anything.
`$save_session()` and durable approvals keep them too; a call still
running when the conversation is saved shows as not completed once it is
loaded or resumed. The lead's model never sees them: it gets each
subagent's summary, as before. `$get_turns()` on the lead includes the
cards, while `$get_context_turns()` and requests to the provider don't,
and `$set_turns()` and `$add_turn()` separate them again.

Only tool calls made while the lead is answering in this chat appear,
and only when `requester` may see the subagents under the lead's
[DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md);
its `redact` function applies, as for `$inspect_subagents()`. A call cut
short by cancellation or a failed subagent shows as not completed. Up to
256 calls appear per reply. Showing a call never runs it again. Needs
shiny, shinychat (\>= 0.5.0), bslib, commonmark and xml2.

## See also

[`subagent_chat_ui()`](https://jameshwade.github.io/deputy/reference/subagent_chat_ui.md)
for a panel with each subagent's full conversation.
