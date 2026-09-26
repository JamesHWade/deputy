# Subscription to subagent events

Reads an agent's subagent events; create one with
`Agent$observe_subagents()`. `$snapshot()` returns the current state and
`$poll()` the events since the last read. Reading never affects the
subagents, and every read checks access again with the agent's
[DelegationDisclosure](https://jameshwade.github.io/deputy/reference/DelegationDisclosure.md).
Event sequence numbers count across all of the agent's subagents. A
cursor marks a position; it doesn't grant access.

## Methods

### Public methods

- [`DelegationSubscription$new()`](#method-DelegationSubscription-initialize)

- [`DelegationSubscription$snapshot()`](#method-DelegationSubscription-snapshot)

- [`DelegationSubscription$poll()`](#method-DelegationSubscription-poll)

- [`DelegationSubscription$close()`](#method-DelegationSubscription-close)

------------------------------------------------------------------------

### `DelegationSubscription$new()`

Create a subscription, usually through `Agent$observe_subagents()`.

#### Usage

    DelegationSubscription$new(lead, requester, delegation_id = NULL, after = NULL)

#### Arguments

- `lead`:

  The `Agent` or
  [LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
  to follow.

- `requester`:

  Who is reading, passed to the disclosure functions. Authenticate it
  first.

- `delegation_id`:

  Optional delegation ID, to follow one subagent.

- `after`:

  A cursor from this agent to resume from, or `NULL` to start now. A
  cursor from another agent is an error.

------------------------------------------------------------------------

### `DelegationSubscription$snapshot()`

Get the subagents' current state and move the cursor to now, so the next
`$poll()` returns only later events.

#### Usage

    DelegationSubscription$snapshot(transcript = FALSE)

#### Arguments

- `transcript`:

  Whether to include transcripts. Defaults to `FALSE`.

#### Returns

A list with `children`, one redacted view per subagent, and `cursor`.

------------------------------------------------------------------------

### `DelegationSubscription$poll()`

Get the events since the last read and advance the cursor. Ranges of
events dropped before you read them are listed in `gaps`; call
`$snapshot()` to catch up. When following one subagent, a gap may only
cover other subagents' events.

#### Usage

    DelegationSubscription$poll()

#### Returns

A list with `events`, `gaps` and `cursor`. Each event goes through the
disclosure `redact` function as `list(kind = "event", event = event)`;
remove `event` to hide it. If `redact` errors, the cursor doesn't move.

------------------------------------------------------------------------

### `DelegationSubscription$close()`

Stop reading; the subagents keep running.

#### Usage

    DelegationSubscription$close()

#### Returns

`NULL`, invisibly. Later reads error.
