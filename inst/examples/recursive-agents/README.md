# Recursive retained agents

Run the example from a source checkout with:

```r
shiny::runApp("inst/examples/recursive-agents")
# or, after installing deputy:
shiny::runApp(system.file("examples/recursive-agents", package = "deputy"))
```

The app starts a local OpenAI-compatible HTTP fixture in a separate R process.
It makes no paid model calls and does not require credentials. The `Run root →
analyst → reviewer` button drives one real streaming path through the graph:
the root calls the retained analyst, the analyst reads deterministic evidence
and calls the retained reviewer, and the root receives both reports. `Cancel
active graph` requests cooperative cancellation through the root, which owns
the child lifecycle.

The child panel is read-only. Select the analyst or reviewer card, then inspect
the retained transcript and live status. The host owns disclosure, observation,
cancellation, and the graph budget. The `Follow up with analyst` button spends
the same cumulative graph allocation; it does not create a second budget or
silently reset the analyst's conversation.

Each Shiny session creates and owns its own graph. The local host controls act
only on that session's graph; the child panel exposes observation without a
cancellation callback. The requester token demonstrates disclosure scoping,
not end-user authentication. A shared deployment must supply its own identity
and action authorization, independently of permission to view child transcripts.

The route declarations demonstrate borrowing. The root may borrow `analyst`
through `analyze`, and `analyst` may borrow `reviewer` through `review`. Each
route fixes its target, description, and per-invocation allocation. Depth is
bounded at two edges, total delegations at eight, concurrent children at two,
and retained invocations at 32. The graph-wide eight-request and four-tool-call
ceilings remain in force across follow-ups. `release_agent_graph()` is called
when the session closes after the graph is idle.

The visible controls have stable Shiny ids `run`, `followup`, and `cancel`. The
child selector is `children-choice`; transcript selection is accompanied by the
`Selected child` heading (`children-heading`). Headless coverage is in
`tests/testthat/test-recursive-example.R`; it uses the same local HTTP fixture
and checks the real three-level requests, effects, parent identities, depth,
transcripts, cumulative accounting, and cleanup.
