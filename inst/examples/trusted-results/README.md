# Trusted forecast: chat, review, result

A three-area app following Will Landau's
[trusted mini-agent template](https://trustedminiagents.dev/r-template.html):

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
`approval_review_server()` and run the continuation elsewhere, for example
with `shiny::ExtendedTask`, so one session does not block others.

## Verification

```r
devtools::test(filter = "trusted-results-example")
```

See ADR-0030 and <https://trustedminiagents.dev/definition.html>.
