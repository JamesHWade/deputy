# Replay saved subagent history

Turns a snapshot from `$export_subagents()` back into ellmer turns for
display, for example in
[`subagent_chat_server()`](https://jameshwade.github.io/deputy/reference/subagent_chat_ui.md).
Replaying never runs tools, calls a model or restores a chat. Access is
checked again with `disclosure`; the IDs and scope stored in `history`
grant nothing. Tool results get back the card they showed, after a check
that the saved card holds only the fields and sizes an export can
contain; a snapshot that fails the check is an error.

## Usage

``` r
delegation_history(history, requester, disclosure, scope)
```

## Arguments

- history:

  A snapshot from `$export_subagents()`.

- requester:

  Who is asking, passed to `disclosure`. Authenticate it first.

- disclosure:

  A
  [DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md)
  for this request.

- scope:

  The scope the history belongs to, from your own records rather than
  from `history`. It must match the saved scope exactly.

## Value

A list with one redacted view per subagent, each with ellmer `turns`.
Artifact references are marked `availability = "unresolved"`, since the
saved status may be stale.
