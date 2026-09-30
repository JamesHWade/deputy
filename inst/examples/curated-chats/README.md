# Curated chats as retained specialists

A Shiny app that turns two configured ellmer chats, an analyst and an auditor,
into specialists an agent can consult. Each keeps its own conversation across
follow-ups.

```r
shiny::runApp(system.file("examples/curated-chats", package = "deputy"))
```

It needs shiny, bslib, shinychat (0.5.0 or later), httpuv, commonmark and
xml2. A local test server stands in for the model, so there are no API keys or
paid requests.

Ask both specialists, select either one to read its conversation, then follow
up with the analyst. The follow-up gets new run and delegation IDs but keeps
the conversation ID and earlier evidence. Cancelling a specialist doesn't
restart it.

`composition.R` also works with your own chats:

```r
setup <- curated_conversations(caller_chat, analyst_chat, auditor_chat, disclosure)
setup$owner$run_sync("Ask the specialists to assess this result.")
setup$owner$continue_agent(setup$handles$analyst,
  "Reconsider the result using the measurement caveat.",
  deputy::UsageLimits(max_requests = 2))
```

`adopt_chat()` copies a chat with its provider, system prompt and tools, and
replaces its callbacks so the owning agent's permissions and hooks apply.
`history = "retain"` copies its turns; `"fresh"` starts without them. The copy
shares the original's tool functions and whatever they touch. The example
makes the specialists readonly; adjust that for your own use. Use
`retain_agent()` to hand over an existing `Agent` instead.

Each specialist reaches the model as a `delegation_tool()` (`ask_analyst`,
`ask_auditor`) that takes only a task: the model can't pick another chat, add
tools, change prompts, release the specialist or reset its budget.
`disclosure` (a `DelegationDisclosure()`) decides who may read the
conversations. Export any history you need before `release_agent()`.
