# How an agent run ended

An
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
carries a `RunEnding` in its `ending` property. It says how the run
ended and holds only what that ending has, so you can act on an ending
without reading the `stop_reason` string:

- `RunEndingAnswered`: the model finished its answer.

- `RunEndingStopped`: someone or something stopped the run. `by` says
  who, and `reason` is the reason they gave.

- `RunEndingLimit`: the run reached a limit. `reason` names it, and
  `field`, `actual` and `limit` give the
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  field, the figure reached and the figure allowed, when the limit has
  them.

- `RunEndingCutOff`: the provider cut the answer short. `finish_reason`
  says why. The result's `stop_reason` is still `"complete"`, since the
  run was not stopped.

- `RunEndingFailed`: an error ended the run. `error` is the condition,
  when there is one, and `phase` says where it came from.

`RunEnding` is the parent class; use it to test for any ending with
`S7::S7_inherits(x, RunEnding)`. Agents create these values. You only
need the constructors to build an
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
yourself, for example in a test.

Endings are read-only. Read a property with `$` (a missing one gives
`NULL`), `@` or
[`S7::prop()`](https://rconsortium.github.io/S7/reference/prop.html).

## Usage

``` r
RunEnding()

RunEndingAnswered()

RunEndingStopped(by, reason = NULL)

RunEndingLimit(reason, field = NULL, actual = NULL, limit = NULL)

RunEndingCutOff(finish_reason)

RunEndingFailed(reason = "error", error = NULL, phase = NULL)
```

## Arguments

- by:

  Who or what stopped the run: one of `"caller"`, `"hook"`,
  `"permission"`, `"approval"`, `"parent"`, `"delegation"` or
  `"abandoned"`.

- reason:

  For `RunEndingStopped()`, the reason the stopper gave, or `NULL`. For
  `RunEndingLimit()`, the limit's stop reason, such as
  `"request_limit"`. For `RunEndingFailed()`, the failure's stop reason,
  `"error"` by default.

- field:

  The
  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  field that was reached, such as `"max_requests"`, or `NULL`.

- actual:

  The figure the run reached, or `NULL`. `NA` when it is unknown, as the
  cost is for `"cost_unavailable"`.

- limit:

  The figure the limit allowed, or `NULL`.

- finish_reason:

  The provider's finish reason, as ellmer names it: one of
  `"max_tokens"`, `"context_window"` or `"content_filter"`.

- error:

  The condition that ended the run, or `NULL`.

- phase:

  Where the run failed, such as `"initialization"` or `"stream"`, or
  `NULL`.

## Value

A `RunEnding` object of the class named.

## Which ending a stop reason gives

- `"complete"`: answered, or cut off when the last response's finish
  reason is `"max_tokens"`, `"context_window"` or `"content_filter"`.

- `"request_limit"`, `"tool_call_limit"`, `"input_token_limit"`,
  `"output_token_limit"`, `"total_token_limit"`, `"cost_limit"`,
  `"cost_unavailable"`, `"tool_loop"`: a limit.

- `"error"`, `"provider_error"`, `"file_checkpoint_error"` and the
  reasons a failed delegation or batch gives: failed.

- Anything else: stopped. `by` is `"caller"` for `$interrupt()`,
  `"hook"` for a hook that stopped the run, `"permission"` for a denied
  call that asked to stop it, `"approval"` for a run waiting for an
  approval, `"parent"` for a subagent whose lead finished,
  `"delegation"` for a batch whose subagents were stopped, and
  `"abandoned"` for a stream nobody read to its end. A reason you pass
  to `$interrupt()` or return from a hook is kept in `reason`, and
  whoever gave it is credited in `by`, whatever the reason says.

## See also

[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)

## Examples

``` r
result <- AgentResult(response = "Done")
result$ending
#> <RunEndingAnswered>

stopped <- AgentResult(stop_reason = "interrupted")
S7::S7_inherits(stopped$ending, RunEndingStopped)
#> [1] TRUE
stopped$ending$by
#> [1] "caller"

RunEndingLimit("request_limit", field = "max_requests", actual = 5, limit = 5)
#> <RunEndingLimit>
#>   reason: request_limit
#>   field: max_requests
#>   actual: 5
#>   limit: 5
```
