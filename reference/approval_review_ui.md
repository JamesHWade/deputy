# Review a pending tool call in Shiny

A Shiny module for human review of the inputs to a tool call suspended
by a durable approval (see `approval_dir` in
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) and
[PermissionResultPending](https://jameshwade.github.io/deputy/reference/PermissionResultPending.md)).
The call stays blocked until the reviewer acts. The module shows each
argument with its declared type, description, and proposed value, using
[`tool_input_review()`](https://jameshwade.github.io/deputy/reference/tool_input_review.md).
The reviewer can edit simple fields, then approve or deny.

A field is editable when its declared type is enum, string, number,
integer, or boolean and its editor can show the proposed value exactly.
Anything else, including a proposed value that does not fit its type (a
boolean `"yes"`, a number `"abc"`), is shown read-only as proposed; deny
the call if it is wrong. An absent optional field stays absent unless
the reviewer picks a value, or ticks "Provide a value" for text and
numbers. Approval with edits resumes with the edited input, which the
tool must validate. Approval without edits resumes with the original
input. Clearing a number removes the field. Deny executes nothing. Each
pending approval is submitted at most once.

This is the input review step of Will Landau and Sam Parmar's [trusted
mini-agent](https://trustedminiagents.dev/definition.html) pattern: a
person checks the model-generated inputs before a trusted tool runs.

The server registers a `Stop` hook on `agent`, so the review refreshes
when a run suspends. Call it once per Agent, while no run is active.

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
  decision. The default calls `agent$resume_approval()` synchronously,
  which runs the model continuation in this R process. Supply your own
  function to run it elsewhere and return a promise, for example from
  `mirai` or
  [`promises::future_promise()`](https://rstudio.github.io/promises/reference/future_promise.html).
  The module waits for a returned promise: on success it records the
  result and refreshes; on failure it records the error and allows a
  retry while the approval is still pending. The result is available
  from `outcome()`.

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

[`tool_input_review()`](https://jameshwade.github.io/deputy/reference/tool_input_review.md),
[TrustedResults](https://jameshwade.github.io/deputy/reference/TrustedResults.md),
[`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md)

## Examples

``` r
if (interactive() && rlang::is_installed("bslib")) {
  library(shiny)
  ui <- bslib::page_fluid(approval_review_ui("review"))
  server <- function(input, output, session) {
    agent <- Agent$new(
      ellmer::chat("openai/gpt-5.6-luna"),
      approval_dir = tempfile()
    )
    approval_review_server("review", agent)
  }
}
```
