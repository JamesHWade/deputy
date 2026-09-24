# Trusted forecast: chat, review, result

A three-area app implementing the trusted mini-agent pattern from
[*Trusted Mini-Agents*](https://trustedminiagents.dev) by Will Landau and Sam
Parmar. The layout and the forecast task are adapted from their
[R template](https://trustedminiagents.dev/r-template.html) and
[weather example](https://trustedminiagents.dev/r-weather.html). Their
versions enforce the rules by hand in plain ellmer, shinychat and bslib. This
one uses Deputy's `TrustedResults()` and `approval_review_ui()` for the same
guarantees.

1. **Chat.** Model text. It is commentary, never a result.
2. **Review.** `approval_review_ui()` shows the inputs the model proposed for
   `get_forecast`, with their declared types. You can change the city or the
   number of days, then approve or deny. Nothing runs until you decide.
3. **Result.** Filled only by `get_forecast`, through the `on_result` callback
   of `TrustedResults()`. The model receives a receipt, not the numbers.

Run from a development checkout:

```r
devtools::load_all()
shiny::runApp("inst/examples/trusted-results")
```

Or from an installed package:

```r
shiny::runApp(system.file("examples", "trusted-results", package = "deputy"))
```

It needs the suggested shiny, bslib, shinychat and httpuv packages. A local
HTTP fixture stands in for the model, so there are no API keys or paid calls.
Type anything in the chat: the fixture always proposes Oslo for 3 days, then
writes deliberately wrong commentary ("99 degrees") after the tool runs. The
result panel shows what the tool actually returned.

## How the rules are enforced

- **Trusted tools produce every result.** `get_forecast` is the only tool, and
  the results card reads only the `trusted_result` event that Deputy delivers
  to `on_result`. Model text has no path into it.
- **No bypass.** `TrustedResults(forecast = "get_forecast")` makes the Agent
  reject any tool that could produce a forecast another way: code execution,
  delegation, or anything that may write or reach the open world.
- **Human review of inputs.** The permission callback returns
  `PermissionResultPending()`, so every call is suspended as a durable
  approval. The review module resumes it with your decision and edits.
  `forecast.R` revalidates edited inputs before computing.

The data is a small synthetic table bundled with the example, not a real
forecast. Runs and approvals execute synchronously in the Shiny process for
simplicity. In a deployed app, pass a `decide` function to
`approval_review_server()` that runs the continuation elsewhere and returns a
promise, for example with `mirai`, so one session does not block others. The
module waits for that promise before refreshing.

## Verification

```r
devtools::test(filter = "trusted-results-example")
```

## Credit

The trusted mini-agent definition, the three-area layout and the idea of
replacing "are these results correct?" with "is the agent solving the right
problem?" come from Will Landau and Sam Parmar's
[*Trusted Mini-Agents*](https://trustedminiagents.dev). Deputy contributes
the runtime enforcement. See also ADR-0030.
