# Recursive retained agents

A Shiny app with three levels of agents: a root agent asks a retained
analyst, and the analyst asks a retained reviewer. Each keeps its own
conversation, and the whole graph shares one budget.

```r
shiny::runApp("inst/examples/recursive-agents")
# or, after installing deputy:
shiny::runApp(system.file("examples/recursive-agents", package = "deputy"))
```

It needs shiny, bslib, shinychat (0.5.0 or later), httpuv, commonmark and
xml2. A local OpenAI-compatible test server runs in a separate R process, so
there are no API keys or paid requests.

## What to try

Click "Run root → analyst → reviewer". The root calls the analyst, the
analyst reads the evidence and calls the reviewer, and the root receives both
reports in the chat on the left. Select the analyst or reviewer card on the
right to read its conversation and status; that panel is read-only. "Follow
up with analyst" continues the analyst's conversation from the same graph
budget. "Cancel active graph" cancels the root's run and everything beneath
it.

## How the graph is set up

`workflow.R` calls `retain_agent_graph()` with two routes: the root reaches
`analyst` through a tool named `analyze`, and `analyst` reaches `reviewer`
through `review`. Each route fixes its target, description and per-call
budget. The graph allows a depth of two, eight delegations, two running at
once and 32 retained runs, with eight requests and four tool calls in total
across every run, follow-ups included. The app calls `release_agent_graph()`
when the Shiny session ends.

Each Shiny session builds its own graph. The `requester` object decides who may
view the specialists' conversations, but it stands in for a signed-in user and
is not authentication. A shared deployment needs its own login and its own
checks on who may run or cancel work.

The buttons have the Shiny ids `run`, `followup` and `cancel`. The child
selector is `children-choice`, and the "Selected child" heading above the
transcript is `children-heading`.

From a source checkout, `devtools::test(filter = "recursive-example")` runs
the app's tests against the same local server.
