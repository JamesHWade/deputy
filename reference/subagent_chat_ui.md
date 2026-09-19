# Inspect child conversations in an optional Shiny panel

Compose this panel beside the host's lead chat. Activity cards select
one separately retained child conversation. Public ellmer Content is
rendered through shinychat's public APIs, including native tool cards
and attachments. The panel has no prompt handler and cannot resume or
approve a child.

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
  poll_interval = 250L
)
```

## Arguments

- id:

  Shiny module ID.

- height:

  Height of the read-only child chat, default `"420px"`.

- lead:

  A host-owned Agent or LeadAgent, or a function returning it.

- requester:

  Function returning the authenticated host request context.

- history:

  Optional reactive/function returning saved settled child history;
  returning NULL selects the live lead. No active recovery occurs.

- disclosure, scope:

  For saved history, current
  [DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  and fixed trusted host scope (or functions returning them). They must
  come from host ownership records, independently of the snapshot or
  browser input.

- on_cancel:

  Optional host-authorized `function(delegation_id, requester)`. The
  callback owns action authorization and may call
  `interrupt_subagent()`. Omit it for a completely read-only panel. It
  is never invoked by selection, replay, observation or closing the
  panel.

- poll_interval:

  Poll interval in milliseconds, at least 100, default 250.

## Value

A bslib card. Requires optional shiny, shinychat \>= 0.5.0, bslib,
commonmark and xml2.

`subagent_chat_server()` returns reactive `selected`, `views`, `notice`
and `closed` values for host composition/testing. No runtime generator
is returned or consumed. Optional packages are checked only when
invoked.
