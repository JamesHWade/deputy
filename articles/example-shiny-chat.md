# Example: Shiny Chat with shinychat

Deputy Agents implement the ellmer chat methods used by
[shinychat](https://posit-dev.github.io/shinychat/). Pass an Agent
directly to `chat_server()`; there is no separate Shiny bridge and no
path that bypasses Deputy’s governance.

``` text
shinychat input -> Agent$stream_async() -> one governed run kernel -> ellmer
                                      \-> AgentResult + hooks + usage
```

The stream keeps ellmer’s native chunks, so shinychat can render
incremental text, tool activity, and attachment-enabled input. After it
finishes, `agent$last_run()` exposes the corresponding `AgentResult`.

## Basic Setup

``` r

library(shiny)
library(deputy)
library(shinychat)

workspace <- normalizePath(getwd(), mustWork = TRUE, winslash = "/")

ui <- bslib::page_fluid(
  chat_ui("chat", fill = TRUE, allow_attachments = TRUE)
)

server <- function(input, output, session) {
  chat <- ellmer::chat_openai(
    model = "gpt-4o-mini",
    system_prompt = "You are a concise data assistant."
  )

  agent <- Agent$new(
    chat = chat,
    tools = c(tools_file(), tools_data()),
    permissions = permissions_readonly(),
    usage_limits = UsageLimits(
      max_requests = 10,
      max_tool_calls = 12,
      max_cost_usd = 0.50
    ),
    context_policy = ContextPolicy(
      max_tokens = 32000,
      fallback = "error"
    ),
    working_dir = workspace
  )

  chat_server("chat", agent)
}

shinyApp(ui, server)
```

`chat_server()` passes both plain text and attachment-enabled ellmer
content to the Agent unchanged. It also supplies shinychat history and
cancellation around Deputy’s governed stream.

## What the Agent Adds

Every public chat and run method uses the same kernel:

| Method | Native return | Typical host |
|----|----|----|
| `chat()` | final text | scripts and consoles |
| `chat_async()` | promise of final text | async applications |
| `chat_structured()` / `chat_structured_async()` | typed data | structured-output hosts |
| `stream()` | synchronous ellmer stream | terminal hosts |
| `stream_async()` | asynchronous ellmer stream | shinychat |
| `run_sync()` | `AgentResult` | inspected workflows |
| `run_async()` | promise of `AgentResult` | subagents |

All interfaces enforce the Agent’s permissions, hooks, `UsageLimits`,
workspace path resolution, file checkpoints, automatic context
compaction, large-result offloading, and run accounting. Native relative
file paths resolve against the Agent’s immutable `working_dir`; Deputy
never changes the process working directory. Custom hosts can pass
`run_context` to any chat, stream, or run method to correlate a request
with product-owned session and stage identities.

[`ContextPolicy()`](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
checks the estimated complete context before a run and again between
provider tool turns, compacting whenever it crosses the token threshold.
The default fails closed if LLM summary generation fails. Set
`fallback = "text"` only when a deterministic degraded summary is
acceptable. `agent$last_compaction()` reports which method was used and
the compaction usage.

Large tool results are stored as integrity-checked envelopes and
replaced in model context with a preview and `deputy://tool-result/...`
reference. The Agent registers `deputy_read_tool_result()` so the model
can page through the stored result in bounded chunks. Applications can
retrieve the original R value with
`agent$resolve_tool_result(reference)`.

## Hooks and Cancellation

Hooks attach to the Agent as usual:

``` r

agent$add_hook(hook_log_tools(verbose = TRUE))

agent$add_hook(HookMatcher$new(
  event = "PostCompact",
  callback = function(result, context) {
    cli::cli_inform("Compacted with: {result$method}")
  }
))
```

[`chat_append()`](https://posit-dev.github.io/shinychat/r/reference/chat_append.html)
owns the completion promise and surfaces stream errors in the chat UI.
shinychat cancellation propagates through ellmer’s stream controller;
Deputy still finalizes checkpoints and fires `Stop` and `SessionEnd`.

## Subagents

`LeadAgent` delegation uses `run_async()` internally, so a subagent does
not block the Shiny R process while the parent chat is streaming. A
custom async tool can use the same contract:

``` r

tool_scout <- ellmer::tool(
  fun = coro::async(function(prompt) {
    result <- coro::await(scout$run_async(prompt))
    result$response
  }),
  name = "agent_scout",
  description = "Delegate a literature search.",
  arguments = list(prompt = ellmer::type_string("Self-contained task"))
)
agent$register_tool(tool_scout)
```

## Running the Example

``` r

shiny::runApp(system.file("examples/shiny-chat", package = "deputy"))
```
