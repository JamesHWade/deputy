# Review a pending tool call in Shiny

A Shiny module for reviewing the inputs of a tool call that is waiting
for approval (see `approval_dir` in
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) and
[PermissionResultPending](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md)).
The call stays paused until the reviewer acts. The module shows each
argument with its declared type, description and proposed value, using
[`tool_input_review()`](https://jameshwade.github.io/deputy/reference/tool_input_review.md).
The reviewer can edit simple fields, then approve or deny.

A field is editable when its declared type is enum, string, number,
integer or boolean and its editor can show the proposed value exactly.
Anything else, including a proposed value that doesn't fit its type (a
boolean `"yes"`, a number `"abc"`), is shown read-only as proposed; deny
the call if it is wrong. An absent optional field stays absent unless
the reviewer picks a value, or ticks "Provide a value" for text and
numbers. Clearing a number removes the field. Approving with edits
resumes with the edited input, which the tool must validate; approving
without edits resumes with the original input. Denying runs nothing.
Each approval is submitted at most once.

This is the input review step of Will Landau and Sam Parmar's [trusted
mini-agent](https://trustedminiagents.dev/definition.html) pattern: a
person checks the model-generated inputs before a trusted tool runs.

The server adds a `Stop` hook to `agent` so the review refreshes when a
run pauses. Call it once per agent, while no run is active.

## Usage

``` r
approval_review_ui(id)

approval_review_server(
  id,
  agent,
  decide = NULL,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- id:

  Shiny module ID.

- agent:

  An [Agent](https://jameshwade.github.io/deputy/reference/Agent.md)
  configured with `approval_dir`.

- decide:

  Optional function `(path, decision, tool_input)` that carries out the
  decision. The default calls `agent$resume_approval()`, which runs the
  rest of the agent's run in this R process and blocks the app until it
  finishes. To run it elsewhere, supply your own function that returns a
  promise, for example from `mirai` or
  [`promises::future_promise()`](https://rstudio.github.io/promises/reference/future_promise.html).
  The module waits for the promise: on success it records the result and
  refreshes; on failure it records the error and allows a retry while
  the approval is still pending. The result is available from
  `outcome()`.

- session:

  Shiny session.

## Value

`approval_review_ui()` returns a UI tag list. `approval_review_server()`
returns a list of reactives: `pending()` (the current
[ApprovalContinuation](https://jameshwade.github.io/deputy/reference/ApprovalContinuation.md)
or `NULL`), `outcome()` (a list with `decision`, `tool_input`, and
`result` or `error` after the last decision), and a `refresh()`
function.

## See also

[`vignette("trusted-mini-agents")`](https://jameshwade.github.io/deputy/articles/trusted-mini-agents.md),
[`tool_input_review()`](https://jameshwade.github.io/deputy/reference/tool_input_review.md),
[TrustedResults](https://jameshwade.github.io/deputy/reference/TrustedResults.md),
[`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md)

## Examples

``` r
if (interactive() && rlang::is_installed("bslib")) {
  library(shiny)
  ui <- bslib::page_fluid(approval_review_ui("review"))
  server <- function(input, output, session) {
    approval_dir <- tempfile("approvals-")
    dir.create(approval_dir)
    agent <- Agent$new(
      ellmer::chat("openai/gpt-6-luna"),
      approval_dir = approval_dir
    )
    approval_review_server("review", agent)
  }
}
```
