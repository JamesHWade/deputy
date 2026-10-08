# Commons subagents in one conversation

A Shiny app where a root agent asks two Commons specialists, sales and
operations, at the same time, and sales asks an auditor in turn. Every
specialist is a real Commons chat. Their tool calls, with Commons' own tables
and charts, appear in the root's conversation, labelled with the subagent that
made them. Each trusted measure is listed once in a "Trusted results" panel,
and reopening a saved conversation shows the same cards and subagent records
without running anything again.

```r
shiny::runApp("inst/examples/commons-subagents")
# or, after installing deputy:
shiny::runApp(system.file("examples/commons-subagents", package = "deputy"))
```

It needs shiny, bslib, shinychat (0.5.0 or later), commons, callr, httpuv,
commonmark and xml2. A local OpenAI-compatible test server runs in a separate R
process and gives scripted replies, so there are no API keys or paid requests.
Conversations are saved in R's temporary directory and last until R restarts.

commons builds a chat only where it can sandbox its R tool: macOS, or Linux
with seccomp and either Landlock or unprivileged user namespaces. Elsewhere,
Windows included, commons stops with an error when the app starts, even though
the app's specialists don't keep that tool.

## What to try

* "Report revenue by region and on-time delivery." The root asks sales and
  operations at once. Sales runs two measures, a table and a bar chart, then
  asks the auditor, whose call is labelled "auditor (via sales)". Operations
  runs one measure and then fails, because the test server returns an error
  for its next request; its finished measure keeps its result, and the root's
  call to it shows the failure. The "Trusted results" panel lists four
  measures, each once, with the subagent that ran it.
* "Ask sales again." The second conversation with sales is labelled
  "sales #2".
* "Run a slow operations check." Operations works through five slow searches,
  about eight seconds in all. Choose it in the Subagents panel and press
  "Cancel selected child": it stops at its next step, the root's call reports
  it as stopped, and no measure is recorded.
* Reload the page and reopen the conversation from the chat's history list.
  The same cards come back, the Subagents panel lists the saved subagents
  read-only, and the counts under the panels (requests to the test server and
  measure runs) don't change.

## How it is set up

`workflow.R` builds the specialists with `commons::commons()` over two data
frames and a semantic layer of four measures, wraps each in an `Agent` with
read-only permissions, and connects them with `retain_agent_graph()`: the root
reaches sales and operations through `ask_sales` and `ask_ops`, and sales
reaches the auditor through `ask_auditor`.

The root's `TrustedResults(measure = tools$call_measure)` names the one tool
that may produce a measure. Commons as it ships also has `run_sql` and `run_r`,
which compute whatever the model asks for and could stand in for a measure, so
a root with trusted results refuses to retain a Commons chat that keeps them.
The example keeps only `search_pool` and `call_measure`, marks them as reading
nothing outside the data frames given to Commons, and gives every specialist
the same `call_measure` tool. Each measure result reaches the root's
`on_result` once, before any model sees it, together with the subagent, run
and tool call that produced it. If `on_result` fails, that call fails instead
of giving the model a result that wasn't recorded.

`subagent_chat_activity()` shows the specialists' tool calls in the root's
conversation, `subagent_chat_history()` saves the subagent records with each
conversation, and `subagent_chat_server(conversation = )` shows them in the
panel. Every call in the graph is also checked against the root's permissions,
so the root's allowlist names the specialists' tools as well as its own. One
reply from the root may use 30 requests and 30 tool calls across all the
subagents it asks; the graph allows 60 requests and 40 tool calls until the
Shiny session ends.

Each Shiny session builds its own agents. The `requester` value decides who
may see the subagents and cancel them, but it stands in for a signed-in user
and is not authentication. A shared deployment needs its own login and its own
checks on who may run or cancel work.

The chat has the Shiny id `chat`, the subagent panel `subagents` (its child
selector is `subagents-choice` and its cancel button `subagents-cancel`), the
trusted results table `trusted-results` and the counts `metrics`.

From a source checkout, `devtools::test(filter = "commons-subagents-example")`
runs the workflow against the same local server.
