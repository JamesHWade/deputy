# Child conversation inspection

From a source checkout with development dependencies installed:

```r
pkgload::load_all()
shiny::runApp("inst/examples/subagent-chats")
```

Requires Shiny, bslib, shinychat >= 0.5.0, ellmer >= 0.5.0, callr, httpuv, commonmark and xml2.
The demo starts a local OpenAI-compatible fixture in a child process. It needs
no model credentials and makes no paid provider calls. Ending the session stops
the fixture and removes its temporary data.

Run two specialists, select their activity cards, and expand a native tool card
to inspect the retained evidence plot. Both definitions have explicit request
budgets. Child responses pause for five seconds so running work can be inspected
and cancelled by hand. Repeat the analyst to see a distinct conversation for the same name.
Enable the auditor failure to retain partial evidence after a provider error;
the large-answer option exercises compact outcomes and artifact offloading.

The child selector also supports keyboard navigation. Selecting a card moves
focus to the child heading. Closing the view detaches observation without
cancelling children. An explicit cancellation button appears during a running
child; its host callback has separate action authorization.

Restore saved history to replay a serialized, settled snapshot. Model-request
and tool-execution counters must remain unchanged during selection and replay.
The nested-lineage button adds a clearly marked synthetic grandchild record;
it does not start recursive execution. The host binds the trusted replay scope
independently of the snapshot.

The access buttons modify only this disposable demo's in-memory display flag.
Denied access clears child disclosure; it does not alter any external account,
file permission, credentials, network access or persistent security setting.
Tool and model text deliberately contain hostile HTML. The adapter renders Markdown then rebuilds inert HTML, preserving literal
characters in code examples; typed images remain visible.

The ring deliberately retains only eight events so snapshot recovery and gap
notices are observable. Retained history is separate from the transient ring.
A completed child indicates execution status, not task success or verified
scientific evidence. Active-run recovery and recursive execution remain outside
this example; general widget persistence remains a separate contract.
