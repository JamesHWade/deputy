# Browser checks

`commons-subagents.js` drives `inst/examples/commons-subagents/app.R` in
Chromium with Playwright and checks, in three Shiny sessions:

1. A first question shows the delegations and the four Commons measure cards
   labelled by subagent (`sales`, `ops`, `sales`, `auditor (via sales)`), the
   table and chart render with no scripts, each card sits in its
   `.deputy-display` box, and the trusted results panel lists each measure once
   with its producer. A second question labels the new delegation `sales #2`.
2. A new session reopens that conversation from shinychat's history: the same
   cards, labels, table and chart come back, the subagent panel lists the saved
   subagents and opens one read-only, and the request and measure counts don't
   move.
3. Cancelling a slow subagent from the panel ends the root's call with a
   `stopped`/`user_cancelled` outcome and runs no measure.

Run it from the package root against a running app:

```sh
R_LIBS=/path/to/library/with/this/deputy \
  Rscript -e 'shiny::runApp("inst/examples/commons-subagents", port = 7801)' &
NODE_PATH="$(npm root -g)" node dev/browser/commons-subagents.js
```

`APP_URL`, `CHROMIUM_PATH` and `SHOTS` override the app address, the Chromium
binary and the screenshot directory. It needs Node and the `playwright` package;
it isn't part of `devtools::test()`, whose `commons-subagents-example` tests cover
the same workflow without a browser.
