# Trusted mini-agents

A trusted mini-agent is an AI agent built so that model errors cannot
reach the results people rely on. The idea and the term come from
[*Trusted Mini-Agents*](https://trustedminiagents.dev) by Will Landau
and Sam Parmar. This article explains their pattern briefly and shows
how Deputy enforces it. For the reasoning behind the pattern, read their
guide.

## The pattern

Language models make mistakes. They misread what someone asked for, pick
the wrong inputs for a tool, or restate a tool’s output incorrectly.
Landau and Parmar’s [weather
example](https://trustedminiagents.dev/errors.html) shows two places
this happens: when the model writes the arguments for a tool call, and
when the model reports the tool’s result back to the person.

Their [definition](https://trustedminiagents.dev/definition.html) closes
both gaps with three rules:

1.  **Trusted tools produce every result.** No result comes from the
    model.
2.  **Each kind of result comes from exactly one trusted tool.** No
    other tool can produce it instead.
3.  **A person reviews the model-generated inputs to trusted tools**, in
    a form they can check quickly and without much fatigue.

In their framing, this changes what the user has to ask. Instead of “Are
these results correct?”, the user asks “Is the agent solving the right
problem?” The first question needs expertise and careful checking of
every output. The second can be answered by looking at the inputs.

The pattern suits narrow, well-defined tasks where a person can
realistically review each call. It is not a way to make a
general-purpose agent safe.

## How Deputy enforces the rules

Landau and Parmar’s R examples build this enforcement by hand in each
app, using ellmer, shinychat and bslib. Deputy moves it into the
runtime:

| Rule | Deputy | If violated |
|----|----|----|
| 1\. Tools produce results | [`TrustedResults()`](https://jameshwade.github.io/deputy/reference/TrustedResults.md) delivers the trusted tool’s return value to the host directly, as a `"trusted_result"` event and an `on_result` callback, before the model sees any output. | Model text never reaches the result channel. |
| 2\. One tool per result | The policy maps each result type to one tool. Every tool registration is checked against it. | Registering a tool that could bypass the trusted one fails. |
| 3\. Human review of inputs | [`PermissionResultPending()`](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md) suspends the call as a durable approval. [`tool_input_review()`](https://jameshwade.github.io/deputy/reference/tool_input_review.md) and [`approval_review_ui()`](https://jameshwade.github.io/deputy/reference/approval_review_ui.md) show the typed inputs for review and editing. | The trusted tool does not run until someone approves. |

## A forecast agent

The running example is a forecast. The model’s job is to work out which
city and how many days the person wants. The forecast itself comes only
from a tool. This follows Landau and Parmar’s weather example and their
[R template](https://trustedminiagents.dev/r-template.html).

### The trusted tool

The trusted tool is an ordinary ellmer tool that produces the result:

``` r

get_forecast <- ellmer::tool(
  function(city, days) {
    if (!city %in% c("Oslo", "Lima") || days < 1 || days > 5) {
      cli::cli_abort("Use a supported city and 1 to 5 days.")
    }
    jsonlite::toJSON(
      list(city = city, days = days, high_c = rep(12, days)),
      auto_unbox = TRUE
    )
  },
  name = "get_forecast",
  description = "Produce the forecast for one supported city.",
  arguments = list(
    city = ellmer::type_enum(c("Oslo", "Lima"), "City to forecast"),
    days = ellmer::type_integer("Number of days, 1 to 5")
  ),
  convert = FALSE,
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    open_world_hint = FALSE
  )
)
```

Two details matter. The tool validates its own inputs, because a
reviewer can edit them. And `convert = FALSE` gives the tool the raw
JSON arguments, which durable approvals need so edited inputs can be
revalidated.

### The policy and the agent

[`TrustedResults()`](https://jameshwade.github.io/deputy/reference/TrustedResults.md)
names the tool that produces each kind of result:

``` r

policy <- TrustedResults(
  forecast = "get_forecast",
  model_receipt = TRUE
)
policy
#> <TrustedResults>
#> • forecast from `get_forecast()`
#> Model receipt: TRUE
```

With `model_receipt = TRUE`, the model receives a short receipt naming
the result ID instead of the forecast itself. It cannot restate the
numbers wrongly later in the conversation, because it never has them.
Without a receipt, the model gets the same value as the host, as in
Landau and Parmar’s examples.

The agent combines the policy with a permission callback that pauses
every forecast for review:

``` r

approval_dir <- tempfile("approvals-")
dir.create(approval_dir)

agent <- Agent$new(
  chat = ellmer::chat_openai(
    model = "gpt-5.6-luna",
    credentials = function() "not used in this article"
  ),
  tools = list(get_forecast),
  approval_dir = approval_dir,
  working_dir = approval_dir,
  permissions = Permissions(
    can_use_tool = function(tool_name, tool_input, context) {
      PermissionResultPending("Check the city and days before forecasting.")
    }
  ),
  trusted_results = policy
)
```

### What the policy rejects

The policy is checked whenever tools are registered, so a tool that
could produce a forecast some other way is refused:

``` r

tryCatch(
  agent$register_tool(tool_run_r_code),
  deputy_tool_registration = function(e) cat(conditionMessage(e))
)
#> Tool "run_r_code" executes model-supplied code and could bypass a
#> trusted tool.
#> ℹ See `?deputy::TrustedResults()` for the no-bypass rule.
```

The rules for tools other than the trusted one:

- Tools that run model-written code (`run_r_code`, `run_bash`, R
  sessions) or delegate to another agent are always rejected. They could
  compute anything.
- Any other tool must be annotated read-only and closed-world.
  Unannotated tools get conservative defaults and are rejected.
- A local tool the host knows to be harmless can be listed in
  `TrustedResults(exempt_tools = )`. That is an explicit statement by
  the host, never something Deputy infers. MCP and provider-side tools
  cannot be exempted.

The trusted tool itself must be a local R function, and it only runs
through the agent’s own governed tool call. Another tool or host code
calling it directly cannot publish a result.

### Reviewing the inputs

When the model asks for a forecast, the run stops with a pending
approval instead of calling the tool:

``` r

agent$run_sync("What's the weather in Oslo this week?")
pending <- agent$pending_approval()
pending$request$tool_input
#> $city
#> [1] "Oslo"
#>
#> $days
#> [1] 5
```

[`tool_input_review()`](https://jameshwade.github.io/deputy/reference/tool_input_review.md)
turns those inputs into a table the reviewer can check at a glance,
pairing each value with its declared type and description:

``` r

tool_input_review(
  list(city = "Oslo", days = 5L),
  get_forecast@arguments
)
#>   argument             type required declared            description value
#> 1     city enum(Oslo, Lima)     TRUE     TRUE       City to forecast  Oslo
#> 2     days          integer     TRUE     TRUE Number of days, 1 to 5     5
```

Permission callbacks and hooks receive the same declared types as
`context$tool_arguments`, so a review can be built anywhere a call is
intercepted.

The host then approves, denies, or approves with edits. The trusted tool
runs only after approval, with the reviewed inputs:

``` r

result <- agent$resume_approval(
  pending$source$path,
  "approve",
  tool_input = list(city = "Oslo", days = 3L)
)
```

### Reading the result

The forecast comes back as a `"trusted_result"` event holding the tool’s
exact return value, the arguments it ran with, a result ID and the tool
call ID:

``` r

forecast <- result_trusted_results(result, "forecast")[[1]]
forecast$value
forecast$arguments
```

Hooks cannot change this value, and large-result offloading does not
affect it. For a live display, pass `on_result` to
[`TrustedResults()`](https://jameshwade.github.io/deputy/reference/TrustedResults.md).
Deputy calls it with the same event as soon as the tool returns, before
the model sees anything. If the callback fails, the model receives a
tool error rather than the value.

## In a Shiny app

Landau and Parmar’s template splits the app into three areas: the chat,
a review of the tool’s inputs, and the trusted results. Only the trusted
tool writes to the results area.

``` r

ui <- bslib::page_fluid(
  bslib::layout_columns(
    bslib::card(shinychat::chat_ui("chat")),
    bslib::card(approval_review_ui("review")),
    bslib::card(shiny::uiOutput("result"))
  )
)

server <- function(input, output, session) {
  latest <- shiny::reactiveVal(NULL)
  approval_dir <- tempfile("approvals-")
  dir.create(approval_dir)
  agent <- Agent$new(
    chat = ellmer::chat("openai/gpt-5.6-luna"),
    tools = list(get_forecast),
    approval_dir = approval_dir,
    permissions = Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        PermissionResultPending("Check the city and days.")
      }
    ),
    trusted_results = TrustedResults(
      forecast = "get_forecast",
      # The only writer of the result area.
      on_result = function(event) latest(event),
      model_receipt = TRUE
    )
  )
  approval_review_server("review", agent)
  output$result <- shiny::renderUI({
    shiny::req(latest())
    shiny::tags$pre(latest()$value)
  })
  # ... send chat input to agent$run_sync() and show replies in the chat.
}
```

[`approval_review_ui()`](https://jameshwade.github.io/deputy/reference/approval_review_ui.md)
shows each argument with its type and description, and lets the reviewer
edit simple fields before approving or denying. It shows exactly what
the model proposed. A value that doesn’t fit its declared type is shown
read-only, and leaving a field untouched never changes it.

By default the module resumes the approval synchronously, which blocks
the R process while the model continues. In a deployed app, pass a
`decide` function that runs the continuation elsewhere and returns a
promise. The module waits for it.

Two complete, runnable apps ship with Deputy. Both use a local fake
model, so they need no API key:

``` r

# Chat, review and result, following Landau and Parmar's template.
shiny::runApp(system.file("examples", "trusted-results", package = "deputy"))

# A descriptive scientific analysis with delegation and a result receipt.
shiny::runApp(system.file("examples", "trusted-mini-agent", package = "deputy"))
```

## Delegation

A `LeadAgent` can hold the policy for its whole delegation tree:

``` r

lead <- LeadAgent$new(
  chat = ellmer::chat("openai/gpt-5.6-luna"),
  sub_agents = list(agent_definition(
    "forecaster",
    "Produce forecasts",
    "Call get_forecast for the requested city.",
    tools = list(get_forecast)
  )),
  trusted_results = TrustedResults(
    forecast = "get_forecast",
    on_result = function(event) print(event$value)
  )
)
```

The lead’s own delegation tool is allowed only because every child
inherits the policy. Each child definition’s tools must pass the same
check. A trusted tool may live in the lead or in a child, but it must be
the same tool object everywhere, declared in the definition’s `tools` or
in a `Skill` value. A child’s trusted result reaches the lead’s
`on_result`, tagged with the child’s delegation ID. Children cannot
delegate further.

Delegated children cannot pause for durable approval. To review a
trusted tool’s inputs before it runs, let the lead or a child propose
the inputs, then run the trusted tool in a separate executor agent that
uses the review flow above. The `trusted-mini-agent` example does this.

## What this does not guarantee

The pattern moves trust from the model to the tools and the review. It
does not remove the need for either:

- **The trusted tool must be right.** Deputy guarantees that results
  come from it unchanged, not that its code or data are correct.
- **The review must be real.** A person clicking Approve without looking
  gets no protection. Keep the inputs few and easy to check.
- **The host is trusted.** The policy stops the model and other tools
  from producing results. It does not protect against code in the host R
  process, and it is not an OS sandbox.
- **The model still talks.** Its chat text is commentary. Present it
  that way, apart from the results, as the three-area layout does.

## Credit

The trusted mini-agent pattern, its three rules, the three-area app
layout and the weather example all come from [*Trusted
Mini-Agents*](https://trustedminiagents.dev) by Will Landau and Sam
Parmar. Deputy’s contribution is enforcing the rules in the runtime:

- the result channel and registry checks;
- the typed review module;
- the extension to delegation.

The design is recorded in
[ADR-0030](https://github.com/JamesHWade/deputy/blob/main/dev/adr/0030-trusted-result-channel.md).
