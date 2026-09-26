# Subagent conversations

A Shiny app that shows a lead agent's conversation next to a panel of its
subagents' conversations, built with `subagent_chat_ui()` and
`subagent_chat_server()`. From a source checkout with the development
dependencies installed:

```r
pkgload::load_all()
shiny::runApp("inst/examples/subagent-chats")
```

It needs shiny, bslib, shinychat (0.5.0 or later), httpuv, commonmark and
xml2. A local OpenAI-compatible test server runs in a separate R process, so
there are no API keys or paid requests. Ending the session stops the server
and deletes its temporary files.

## What to try

- "Run two specialists" delegates to an analyst and an auditor. Each subagent
  reply takes five seconds, so you can select a running subagent and cancel it.
- Select an activity card and expand its tool card to see the evidence plot.
- "Repeat analyst" starts a new analyst conversation under the same name.
- "Fail auditor after its tool result" makes the auditor's next request fail,
  keeping the evidence it had. "Include a large answer" shows a long answer
  being shortened and saved to a file.
- "Restore saved child history" saves the finished subagents to disk and shows
  the saved copy. Selecting and replaying run nothing: the request and tool
  counts under the lead chat don't change.
- "Show nested lineage fixture" adds a made-up grandchild record to show how
  nesting looks. No grandchild runs.
- "Deny child access" and "Allow child access" toggle a flag in this app that
  hides or shows the subagents.

The panel keeps only the last eight events, so you can see how it reports gaps
and recovers from the saved history. The tool and model text contains hostile
HTML on purpose; the panel renders it as inert text, keeps literal characters
in code, and still shows images. The subagent selector works with the
keyboard, and selecting a card moves focus to the subagent's heading. Closing
the panel stops watching without cancelling anything.

When replaying saved history, the app passes `disclosure` and `scope` from its
own records, not from the saved file. A "completed" subagent means its run
finished, not that its answer is right.
