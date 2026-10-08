# Shiny chat

An agent works anywhere
[shinychat](https://posit-dev.github.io/shinychat/) expects an ellmer
chat. Pass it to
[`chat_server()`](https://posit-dev.github.io/shinychat/r/reference/chat_app.html)
and the app streams the model’s replies and tool calls, while Deputy
applies the agent’s permissions, hooks and limits to every message.

## A minimal app

``` r

library(shiny)
library(shinychat)
library(deputy)

workspace <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)

ui <- bslib::page_fluid(
  chat_ui("chat", fill = TRUE, allow_attachments = TRUE)
)

server <- function(input, output, session) {
  agent <- Agent$new(
    chat = ellmer::chat(
      "openai/gpt-6-luna",
      system_prompt = "You are a concise data assistant."
    ),
    tools = tools_data(),
    permissions = permissions_readonly(),
    usage_limits = UsageLimits(max_requests = 10, max_tool_calls = 12),
    working_dir = workspace
  )

  chat_server("chat", agent)
}

shinyApp(ui, server)
```

Create the agent inside `server()`, so that each browser session gets
its own conversation, usage and hooks. shinychat calls the agent’s
`stream_async()` method, passing text and attachments through unchanged,
and handles the input box, cancellation and conversation history. After
each reply, `agent$last_run()` returns the run’s `AgentResult`.

The limits apply to each message the user sends. The agent also keeps
its [context
policy](https://jameshwade.github.io/deputy/articles/conversations.md):
long conversations are compacted automatically, and large tool results
are stored outside the model’s context.

## Tell users when older messages are summarised

When compaction runs, the model sees a summary instead of the oldest
messages, but the chat still shows the whole conversation. The example
app in `inst/examples/shiny-chat/` shows a small notice above the chat
while that happens (“Summarizing earlier messages…”) and afterwards
(“Earlier messages summarized for the assistant. Your full conversation
is still available.”), with a “View summary” link that shows the summary
text.

The notice is driven by hooks: `PreCompact` sets it to busy,
`PostCompact` records the summary, and `Stop` clears the busy state if a
run fails or is cancelled. If you call `agent$compact()` yourself, clear
the notice when that call returns, because a manual compaction doesn’t
fire `Stop`. The notice belongs to the page, not the conversation:
Deputy never adds messages to the chat to report compaction.

shinychat’s conversation history, where available, stores the whole
conversation (`agent$get_turns()`), so restoring a conversation brings
back every message while the model continues from the summary.

## Hooks in an app

Hooks are added to the agent as usual, inside `server()`:

``` r

agent$add_hook(hook_log_tools())

agent$add_hook(HookMatcher(
  event = "PostCompact",
  callback = function(result, context) {
    showNotification("Earlier messages were summarised.")
    NULL
  }
))
```

When the user cancels a reply, the run stops at the next point where
ellmer can stop it, and Deputy still fires the `Stop` and `SessionEnd`
hooks and saves any file checkpoints.

To ask the user questions from a tool, give each session its own handler
with
[`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md);
see [Human input and
approvals](https://jameshwade.github.io/deputy/articles/approvals.md).

## Long-running tools

Delegating to a subagent doesn’t block the app: `LeadAgent` runs
subagents with `run_async()`, so other sessions keep working while the
lead waits. Your own tools can do the same by returning a promise:

``` r

ask_scout <- ellmer::tool(
  coro::async(function(prompt) {
    result <- coro::await(scout$run_async(prompt))
    result$response
  }),
  name = "ask_scout",
  description = "Ask the literature scout to search for papers.",
  arguments = list(prompt = ellmer::type_string("A self-contained task"))
)
agent$register_tool(ask_scout)
```

Here `scout` is another `Agent`. A tool that calls another agent like
this should also have annotations, like any other tool; see
[Tools](https://jameshwade.github.io/deputy/articles/tools.md).

## Run the example

The package includes the app with the compaction notice:

``` r

shiny::runApp(system.file("examples", "shiny-chat", package = "deputy"))
```

To show the tool calls a lead’s subagents make in the main chat, as they
happen, see [Subagent tool calls in the main
chat](https://jameshwade.github.io/deputy/articles/delegation.html#subagent-tool-calls-in-the-main-chat),
and to keep each conversation’s subagents with it, so they come back
when it is reopened, see [Saving subagents with the
conversation](https://jameshwade.github.io/deputy/articles/delegation.html#saving-subagents-with-the-conversation).
For a panel of subagent conversations beside the chat, see [A subagent
panel for
Shiny](https://jameshwade.github.io/deputy/articles/delegation.html#a-subagent-panel-for-shiny).
