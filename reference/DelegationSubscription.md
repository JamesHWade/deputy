# Read bounded child activity without driving execution

Create through `Agent$observe_subagents()`. The runtime consumes each
child stream once; subscriptions only observe retained public events.
Authorization is rechecked on every read, including snapshot and
reconnect. Sequence numbers are monotonic across one lead's transient
stream, not per child. Cursors are locators and cannot authorize access.

## Methods

### Public methods

- [`DelegationSubscription$new()`](#method-DelegationSubscription-initialize)

- [`DelegationSubscription$snapshot()`](#method-DelegationSubscription-snapshot)

- [`DelegationSubscription$poll()`](#method-DelegationSubscription-poll)

- [`DelegationSubscription$close()`](#method-DelegationSubscription-close)

------------------------------------------------------------------------

### `DelegationSubscription$new()`

Create an authorized cursor. Normally use the lead method.

#### Usage

    DelegationSubscription$new(lead, requester, delegation_id = NULL, after = NULL)

#### Arguments

- `lead`:

  An Agent owning delegated conversations.

- `requester`:

  Host-authenticated request context.

- `delegation_id`:

  Optional child locator filter.

- `after`:

  A cursor previously returned by this lead, or NULL to start at its
  current sequence. Foreign/future cursors fail explicitly.

------------------------------------------------------------------------

### `DelegationSubscription$snapshot()`

Return an authorized snapshot and its matching event cursor. This resets
the subscription cursor. The snapshot is copied before host redaction;
subsequent polls contain only events after that boundary.

#### Usage

    DelegationSubscription$snapshot(transcript = FALSE)

#### Arguments

- `transcript`:

  Include public child transcripts. Defaults to FALSE.

#### Returns

List with `children` and `cursor`. Inspection never starts work.

------------------------------------------------------------------------

### `DelegationSubscription$poll()`

Read retained events since this cursor, advancing on success. No
generator is consumed. A slow reader gets explicit `gaps` for lost
sequence ranges; obtain a snapshot to recover retained public history.
Filtering children can make an evicted stream range irrelevant to the
selected child, but the gap is still reported conservatively.

#### Usage

    DelegationSubscription$poll()

#### Returns

List with `events`, `gaps`, and next `cursor`. Event redaction receives
`list(kind = "event", event = envelope)`; remove `event` to hide it.
Redaction errors do not advance the cursor or affect child execution.

------------------------------------------------------------------------

### `DelegationSubscription$close()`

Detach this reader. Does not cancel or resume a child.

#### Usage

    DelegationSubscription$close()

#### Returns

Invisibly NULL. Repeated closes are harmless; reads then fail.
