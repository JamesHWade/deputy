# Curated chats with retained conversations

Run `shiny::runApp(system.file("examples/curated-chats", package = "deputy"))`.
The local deterministic transport needs httpuv, callr, shiny, bslib and shinychat;
it makes no paid requests. Ask both specialists, select either invocation, then
follow up with the analyst. The new invocation has a new run/delegation ID and
the same conversation ID, including its earlier evidence. Cancellation is
cooperative and does not automatically restart a specialist.

`composition.R` also accepts your existing heterogeneous ellmer chats:

```r
setup <- curated_conversations(caller_chat, analyst_chat, auditor_chat, disclosure)
setup$owner$run_sync("Ask the specialists to assess this result.")
setup$owner$continue_agent(setup$handles$analyst,
  "Reconsider the result using the measurement caveat.",
  deputy::UsageLimits(max_requests = 2))
```

The example chooses read-only specialist policy. Adjust that host policy for your
own workflow. `adopt_chat()` makes an isolated copy, preserves configured provider,
prompt and tools, and explicitly replaces its callbacks with Deputy governance.
`history = "retain"` copies selected turns; `"fresh"` starts without turns.
Executable tool closures can still share external resources, which the host owns.
Use `retain_agent()` instead when transferring an already governed Agent.

The model can supply only a task brief. It cannot select another Chat, add tools,
change prompts, release handles or reset their cumulative budget. Inspect child
history through an authenticated `DelegationDisclosure`; inspection does not grant
control or advance execution. Export needed history before `release_agent()`.

This example is one caller and two retained specialists. Recursive children,
durable approval and restart recovery are separate work; successful fixture
execution makes no claim about model quality or output correctness.
