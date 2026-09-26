# Control who can inspect subagents

Decides who may read subagent results and history, through the
inspection methods of
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) and
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
or
[`delegation_history()`](https://jameshwade.github.io/deputy/reference/delegation_history.md).
Pass it as `delegation_disclosure`. `authorize` is where your
application checks access; `redact` removes what the requester shouldn't
see. By default every request is denied. Authenticate the requester
first: a delegation ID alone never grants access.

## Usage

``` r
DelegationDisclosure(
  authorize = function(requester, scope) FALSE,
  redact = function(view, requester) view,
  max_bytes = 16 * 1024^2
)
```

## Arguments

- authorize:

  A `function(requester, scope)`. Only an exact `TRUE` allows access;
  anything else, including an error, denies it. `scope` holds the
  agent's `delegation_scope`, `agent_id` and `session_id`, or the
  `scope` given to
  [`delegation_history()`](https://jameshwade.github.io/deputy/reference/delegation_history.md).

- redact:

  A `function(view, requester)` that returns `view`, as a list, without
  anything the requester shouldn't see. The default returns it
  unchanged.

- max_bytes:

  Maximum size, in bytes, of one disclosed result; defaults to 16 MiB.
  Larger results are an error, so ask for fewer subagents or no
  transcripts. Separately, data frames in tool results are replaced by a
  placeholder above an estimated 16 MiB.

## Value

A `DelegationDisclosure` object.
