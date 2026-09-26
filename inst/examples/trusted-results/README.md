# Trusted forecast: chat, review, result

A three-panel Shiny app using the trusted mini-agent pattern from
[*Trusted Mini-Agents*](https://trustedminiagents.dev) by Will Landau and Sam
Parmar. The layout and the forecast task come from their
[R template](https://trustedminiagents.dev/r-template.html) and
[weather example](https://trustedminiagents.dev/r-weather.html), which follow
the pattern's rules by hand in plain ellmer, shinychat and bslib. This version
uses Deputy's `TrustedResults()` and `approval_review_ui()` instead.

The chat panel shows model text, which is commentary, never a result. The
review panel uses `approval_review_ui()` to show the inputs the model proposed
for `get_forecast`, with their declared types; you can change the city or the
number of days, then approve or deny, and nothing runs until you decide. The
result panel is filled only by `get_forecast`, through the `on_result` callback
of `TrustedResults()`. The model gets a receipt, not the numbers.

Run from a development checkout:

```r
devtools::load_all()
shiny::runApp("inst/examples/trusted-results")
```

Or from an installed package:

```r
shiny::runApp(system.file("examples", "trusted-results", package = "deputy"))
```

It needs shiny, bslib, shinychat (0.5.0 or later) and httpuv. A local test
server stands in for the model, so there are no API keys or paid requests.
Type anything in the chat: the test server always proposes Oslo for 3 days,
then writes deliberately wrong commentary ("99 degrees") after the tool runs.
The result panel shows what the tool actually returned.

## How the rules are enforced

`get_forecast` is the only tool, and the result panel reads only the
`trusted_result` event that Deputy passes to `on_result`, so model text has no
way in. `TrustedResults(forecast = "get_forecast")` also makes the agent refuse
any tool that could produce a forecast another way: code execution, delegation,
or anything that may write or reach the open world.

The permission callback returns `PermissionResultPending()` for every call, so
each one pauses as a durable approval until the review panel resumes it with
your decision and edits. `forecast.R` checks edited inputs again before
computing.

The data is a small synthetic table bundled with the example, not a real
forecast. To keep the example simple, runs and approvals execute in the Shiny
process and block it. In a deployed app, pass `approval_review_server()` a
`decide` function that runs the continuation elsewhere and returns a promise,
for example with `mirai`, so one session doesn't block the others. The module
waits for that promise before refreshing.

## Tests

```r
devtools::test(filter = "trusted-results-example")
```

## Credit

The trusted mini-agent definition, the three-panel layout and the idea of
replacing "are these results correct?" with "is the agent solving the right
problem?" come from Will Landau and Sam Parmar's
[*Trusted Mini-Agents*](https://trustedminiagents.dev). Deputy adds the
enforcement. See also `vignette("trusted-mini-agents", package = "deputy")`.
