# Example: Shiny Chat with shinychat

Deputy Agents implement the ellmer chat methods used by
[shinychat](https://posit-dev.github.io/shinychat/). Pass an Agent
directly to `chat_server()` to stream responses and tool activity while
Deputy checks permissions and tracks usage.

``` text
shinychat input -> Agent$stream_async() -> ellmer
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
    model = "gpt-5.6-luna",
    system_prompt = "You are a concise data assistant."
  )

  agent <- Agent$new(
    chat = chat,
    tools = tools_data(),
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
cancellation around Deputy’s stream.

Compaction and native conversation history can be enabled together.
Deputy’s `get_turns()` supplies the complete selected conversation to
shinychat, while `get_context_turns()` exposes only the compacted model
context. Later completed replies remain available when the user switches
conversations or restores a branch. Native history requires a shinychat
version exporting `history_options()` and `FileConversationStore`;
Deputy’s transcript contract also works without shinychat. Hosts that
previously rejected a non-NULL `ContextPolicy(max_tokens)` with native
history can remove that workaround when using this implementation.

## Showing compaction to users

The runnable `inst/examples/shiny-chat/` app includes a host-owned
compaction notice above the transcript. While summarization runs it says
“Summarizing earlier messages…”. After successful installation it says
“Earlier messages summarized for the assistant. Your full conversation
is still available.” An expandable “View summary” shows the accepted
summary as escaped text, alongside an explanation that the assistant
uses it with recent messages and that some earlier details may be
omitted.

The notice does not add, hide, or replace chat messages. `PreCompact`
and `PostCompact` hooks update its state; a `Stop` hook clears the busy
indication after an automatic run fails or is interrupted, while
retaining any previously accepted summary. Register custom
compaction-veto hooks before this notice so their early return prevents
the progress indication. Hosts that call `agent$compact()` directly must
also clear progress when that call ends, including errors or vetoes; a
manual call does not fire the run’s `Stop` hook. The example scopes the
notice to shinychat’s public conversation ID and clears it through
`history$on_restore()`, including branch navigation. Native history
restores the complete transcript rather than the compacted context, so
the notice stays hidden until compaction happens again. This
presentation belongs to the host; Deputy does not insert UI messages
into its conversation record.

## What the Agent Adds

Choose a method by the result your application needs:

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
checks the estimated complete context after run initialization and again
at model-request boundaries between tool rounds, compacting whenever it
crosses the token threshold. Summary streaming is asynchronous and
shares the run’s cancellation controller and usage limits. The default
fails closed if LLM summary generation fails. Set `fallback = "text"`
only when a deterministic degraded summary is acceptable.
`summary_fallback_chats` explicitly configures separate summary recovery
destinations. `agent$last_compaction()` reports the method, run ID,
attempt conditions, and compaction usage.

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

agent$add_hook(HookMatcher(
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
