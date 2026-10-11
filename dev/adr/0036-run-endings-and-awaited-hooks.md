# A run's ending is a value, and hooks may wait

Status: Accepted

## Decision

A run's result says how the run ended as a value, and any hook may answer with
a promise. Both serve a host that drives an Agent through `stream_async()` and
must act on how a run ended, or check an answer before the run is over,
without parsing a reason string or composing a second run.

### Endings

`AgentResult` carries `ending`, one of five Deputy-owned, read-only S7 values
under the abstract `RunEnding`: `RunEndingAnswered`, `RunEndingStopped`,
`RunEndingLimit`, `RunEndingCutOff` and `RunEndingFailed`. Each holds only
what that ending has: who stopped the run and the reason they gave; which
limit and its figures; the provider's finish reason; the error and the phase
it came from.

`stop_reason` remains an open string, and `result_is_success()` remains
`stop_reason == "complete"`. Every reason Deputy sets maps to exactly one
ending in one internal function. A reason Deputy does not know, which can only
have come from `interrupt(reason)` or a hook's `stop_reason`, is a stopped
run. A run records who asked for a stop when the stop is requested, so a
made-up reason is still placed with its asker; the asker is credited only when
the run's final reason is the one they gave.

A cut-off answer is read from ellmer's normalised `finish_reason` on the last
assistant turn (`max_tokens`, `context_window`, `content_filter`). Its
`stop_reason` stays `"complete"`, since Deputy did not stop the run.

### Hooks may return a promise

A callback may return a promise of what it would have returned.
`HookRegistry$fire()` returns the first non-`NULL` result as before, or a
promise of it when a callback returned a promise; later hooks wait for an
earlier hook's promise. Callers follow one rule: a value is used at once, a
promise is waited for. Nothing becomes asynchronous unless a callback returns
a promise, so every existing hook, and every test that calls the tool
callbacks directly, behaves as before.

`HookMatcher(promise_timeout = 60)` bounds the wait. A promise that rejects or
does not settle in time is recorded as a hook error and counts as no answer;
for `PreToolUse` it denies the call, as any `PreToolUse` failure does. The
promise `fire()` returns never rejects.

Where each event waits:

| Event | Waits |
|---|---|
| `PreToolUse`, `PermissionRequest` | before the tool runs: ellmer awaits the request callback |
| `PostToolUse`, `PostToolUseFailure` | before the next model request, and at the end of a pass: ellmer does not await the result callback, so Deputy holds the promise |
| `PostModelRequest` | before the run goes on: ellmer awaits the request-end callback |
| `SessionStart`, `UserPromptSubmit` | before the first model request |
| `SubagentStart`, `SubagentStop` | around the delegated run |
| `PreCompact`, `PostCompact` | in automatic compaction; `$compact()` does not wait |
| `Stop`, `SessionEnd` | when the run ends in its own course |
| `Notification`, `ConfigChange` | never |

An `interrupt()` that arrives while a hook's promise is pending takes effect
when the promise settles: a pending tool does not start, and a pending `Stop`
does not send the run on.

### Stop and SessionEnd fire from the run's body

`finish_callback_run()` is split into settling the run (reason, usage, limit),
firing the two hooks, and the terminal accounting. A run that ends in its body
settles and fires both hooks there, where a coroutine can wait. A run that
ends outside its body (an error signalled from the stream, an abandoned
stream) and a delegate batch fire them from `finish_callback_run()` and do not
wait, as before.

### Stop may send the run on

A `Stop` hook may return `HookResultStop(message)`. An answered run is then
asked again with that message in the same run: the same run id, limits, usage
and stream. `Stop` fires at every stop, with `context$stop_hook_active` set
once a hook has sent the run on, which is how a hook avoids doing so for ever;
Deputy adds no cap of its own beyond the run's limits. `SessionEnd` fires
once. The result's `response` is the last pass's text and its `turns` hold
every pass. A run that was stopped, hit a limit or failed is never sent on.

### Limits, cost and the result beside the stream

- `stream()` and `stream_async()` take `usage_limits` for one run.
- `UsageLimits(on_unknown_cost = "continue")` lets a run with a cost limit go
  on when a response has no cost. The limit is then enforced against
  `AgentUsage@known_cost_usd`, the cost of the responses whose cost is known:
  equal to `cost_usd` when that is known, a lower bound when it is `NA`.
- `PostModelRequest` fires after each model request with the run's usage.
- `stream_result(stream)` gives a promise of the run's `AgentResult`. It
  resolves however the run ended.
- An `interrupt()` between `stream_async()` and the stream's first pull stops
  the run when it starts.

## Alternatives considered

- **A separate `fire_async()` that always returns a promise.** Every tool call
  would then cross the event loop even for a plain-value hook, changing the
  order in which concurrent tool calls start and breaking direct callers of
  the tool callbacks.
- **Making the tool callbacks coroutines.** The same cost, for the same reason.
- **Having ellmer await the tool-result callback.** A change in ellmer; holding
  the promise in Deputy needs none.
- **A second run for a follow-up.** It is what hosts did: two run ids, two
  charges, a result held back by hand, and a window between the runs in which
  the host looked idle.
- **Rejecting the result promise for a failed run.** A host would then need two
  code paths for one question. A failed run has a result, with a failed
  ending; the stream still rejects for whoever reads it.
- **Making `result_is_success()` false for a cut-off answer.** It would change
  the meaning of an existing function for existing callers. `ending` is the
  precise account.
- **A cap on how often `Stop` may send a run on.** The run's limits already
  bound it, and `stop_hook_active` gives a hook what it needs to stop itself.

## Consequences

- A slow `Stop` hook holds the Agent as running: a second run, a session load
  and a manual compaction are refused until its promise settles or times out.
  A stream abandoned while a `Stop` hook is pending finishes then too.
- With tools run concurrently, other tool calls of the same response may start
  or finish while one call's hook waits.
- A run near a limit that is sent on ends at the limit, not with the fix.
- Records made with `S7::props()` gain a property each for limits and usage.
  A durable job's manifest holds such records and is compared with a live one
  by identity, so the version is raised with this change: a job saved by an
  earlier version is refused at the runtime-version check, as a job from any
  other version is, and is never compared field by field.
- `Stop` now fires before a run's descendants are told the parent completed,
  on the path where the run ends in its body.
- Deputy's approval review module refreshes on `SessionEnd`, since `Stop` may
  now fire more than once in a run.
