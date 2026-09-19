library(shiny)
library(bslib)
library(deputy)
source("../subagent-chats/fixture.R", local = TRUE)
source("composition.R", local = TRUE)

ui <- page_fluid(
  title = "Curated specialist conversations",
  theme = bs_theme(version = 5),
  tags$h1("Curated specialist conversations"),
  tags$p(
    "Two configured specialists retain their own conversations across follow-ups."
  ),
  actionButton("run", "Ask both specialists"),
  actionButton("followup", "Follow up with analyst"),
  tags$div(role = "status", textOutput("status")),
  subagent_chat_ui("children"),
  tags$p("Local deterministic example. No paid model calls.")
)

server <- function(input, output, session) {
  fixture <- child_chat_fixture(curated = TRUE)
  session$onSessionEnded(fixture$close)
  analyst <- fixture$chat()
  analyst$set_system_prompt(
    "DEMO_ANALYST: inspect evidence and retain the conversation."
  )
  auditor <- fixture$chat()
  auditor$set_system_prompt("DEMO_AUDITOR: inspect limitations independently.")
  evidence <- ellmer::tool(
    function() "Observed values: 4, 7, 6; conditions unconfirmed.",
    name = "inspect_evidence",
    description = "Read local evidence",
    arguments = list(),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE
    )
  )
  analyst$register_tool(evidence)
  auditor$register_tool(evidence)
  requester <- new.env(parent = emptyenv())
  setup <- curated_conversations(
    fixture$chat(),
    analyst,
    auditor,
    DelegationDisclosure(authorize = function(who, scope) {
      identical(who, requester)
    })
  )
  owner <- setup$owner
  busy <- reactiveVal(FALSE)
  status <- reactiveVal(
    "Ready. Select a specialist invocation to inspect its conversation."
  )
  launch <- function(task) {
    if (busy()) {
      return()
    }
    busy(TRUE)
    status(
      "Specialists are working; their conversations can be inspected below."
    )
    promises::then(
      owner$run_async(task),
      onFulfilled = function(result) {
        busy(FALSE)
        status(paste("Caller stopped:", result$stop_reason))
      },
      onRejected = function(error) {
        busy(FALSE)
        status(conditionMessage(error))
      }
    )
  }
  observeEvent(input$run, launch("Ask both specialists to inspect evidence."))
  observeEvent(
    input$followup,
    launch("Repeat analyst with a follow-up using retained evidence.")
  )
  subagent_chat_server(
    "children",
    owner,
    requester = function() requester,
    on_cancel = function(id, who) {
      if (!identical(who, requester)) {
        cli::cli_abort("Not authorized")
      }
      owner$interrupt_subagent(id, "user_cancelled")
    }
  )
  output$status <- renderText(status())
}
shinyApp(ui, server)
