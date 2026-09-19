library(shiny)
library(bslib)
source("workflow.R", local = TRUE)
source("fixture.R", local = TRUE)

ui <- page_fluid(
  title = "Reviewed plant-weight analysis",
  theme = bs_theme(
    version = 5,
    bg = "#f5f6f2",
    fg = "#243c38",
    primary = "#28685c"
  ),
  tags$h1("Reviewed plant-weight analysis"),
  tags$p(
    "A specialist proposes the inputs. You review them. A designated R tool produces the result."
  ),
  tags$p(
    "Local deterministic demonstration using synthetic plant weights. No paid model calls or clinical inference.",
    class = "text-muted"
  ),
  layout_columns(
    col_widths = c(4, 4, 4),
    card(
      fill = FALSE,
      card_header("1. Proposed analysis"),
      actionButton("propose", "Draft a proposal", class = "btn-primary"),
      uiOutput("proposal"),
      actionButton("prepare", "Prepare input review")
    ),
    card(
      fill = FALSE,
      card_header("2. Review actual inputs"),
      uiOutput("review"),
      selectInput("treatment", "Treatment group", c("trt2", "trt1")),
      tags$p(
        "Control: ctrl · Outcome: dry plant weight · Units: grams. The computation reports group means and their difference using all complete observations."
      ),
      actionButton("approve", "Approve these inputs", class = "btn-primary"),
      actionButton("deny", "Deny computation"),
      actionButton("cancel", "Cancel workflow")
    ),
    card(
      fill = FALSE,
      card_header("3. Tool-owned result"),
      uiOutput("result"),
      tags$details(
        tags$summary("Result receipt"),
        verbatimTextOutput("receipt")
      )
    )
  ),
  tags$div(role = "status", `aria-live` = "polite", textOutput("status")),
  tags$p(textOutput("metrics"), class = "text-muted"),
  layout_columns(
    col_widths = c(4, 8),
    card(
      fill = FALSE,
      card_header("Model commentary — not a computed result"),
      textOutput("commentary")
    ),
    deputy::subagent_chat_ui("child", height = "400px")
  )
)

server <- function(input, output, session) {
  fixture <- study_fixture(study_plan())
  session$onSessionEnded(fixture$close)
  owner <- new.env(parent = emptyenv())
  workflow_directory <- tempfile("reviewed-study-")
  session$onSessionEnded(function() {
    unlink(workflow_directory, recursive = TRUE)
  })
  workflow <- study_workflow(fixture$chat, workflow_directory, owner)
  current <- reactiveVal(workflow$view(owner))
  status <- reactiveVal("Draft a proposal to begin. No computation has run.")
  refresh <- function(fun, message) {
    tryCatch(
      {
        current(fun())
        error <- current()$error
        status(if (is.null(error)) message else paste("Stopped:", error))
      },
      error = function(e) status(conditionMessage(e))
    )
  }
  observeEvent(
    input$propose,
    refresh(
      function() {
        workflow$propose(
          "Ask the analyst to propose a plant-weight comparison.",
          owner
        )
      },
      "Proposal retained. Review is still required; no computation has run."
    )
  )
  observeEvent(
    input$prepare,
    refresh(
      function() workflow$prepare(owner),
      "The actual tool request is paused. Review or edit the treatment group, then approve or deny."
    )
  )
  observeEvent(
    input$approve,
    refresh(
      function() {
        snapshot <- current()
        if (is.null(snapshot$pending) || snapshot$pending$status != "pending") {
          cli::cli_abort("Prepare a pending input review first.")
        }
        plan <- snapshot$pending$request$tool_input$plan
        plan$treatment <- input$treatment
        workflow$decide(owner, "approve", plan)
      },
      "The reviewed computation finished. The result comes directly from compute_summary."
    )
  )
  observeEvent(
    input$deny,
    refresh(
      function() workflow$decide(owner, "deny"),
      "Computation denied. No authoritative result was produced."
    )
  )
  observeEvent(
    input$cancel,
    refresh(
      function() workflow$cancel(owner),
      "Workflow cancelled. It cannot approve further computation."
    )
  )
  output$proposal <- renderUI({
    plan <- current()$proposal
    if (is.null(plan)) {
      return(tags$p("No proposal yet."))
    }
    tagList(
      tags$p(paste("Compare", plan$treatment, "with", plan$control)),
      tags$p("Descriptive difference in mean dry weight (g)."),
      tags$details(
        tags$summary("Dataset revision and proposed inputs"),
        tags$pre(study_json(plan))
      )
    )
  })
  output$review <- renderUI({
    pending <- current()$pending
    if (is.null(pending)) {
      return(tags$p("No pending tool request."))
    }
    tagList(
      tags$p(paste("Decision status:", pending$status)),
      tags$p(
        "Dataset: synthetic-plant-weights-v1 (12 observations; 4 per group)."
      ),
      tags$details(
        tags$summary("Exact original tool inputs"),
        tags$pre(study_json(pending$request$tool_input))
      )
    )
  })
  output$result <- renderUI({
    receipt <- current()$receipt
    if (is.null(receipt)) {
      return(tags$p(
        "No tool-owned result. Model text cannot populate this panel."
      ))
    }
    result <- receipt$result
    tagList(
      tags$h2(sprintf("%+.3f g", result$difference)),
      tags$p(paste(receipt$inputs$treatment, "minus", receipt$inputs$control)),
      tags$p(sprintf(
        "Treatment mean %.3f g (n=%d); control mean %.3f g (n=%d).",
        result$mean_treatment,
        result$n_treatment,
        result$mean_control,
        result$n_control
      )),
      tags$p(result$interpretation),
      tags$p("Produced by compute_summary v1 from reviewed inputs.")
    )
  })
  output$receipt <- renderText(
    if (!is.null(current()$receipt)) study_json(current()$receipt)
  )
  output$commentary <- renderText({
    x <- current()
    paste(
      if (!is.null(x$lead_result)) x$lead_result$response,
      if (!is.null(x$commentary)) x$commentary$response,
      collapse = "\n"
    )
  })
  output$status <- renderText(status())
  output$metrics <- renderText({
    current()
    paste(
      fixture$requests(),
      "model requests ·",
      as.integer(!is.null(current()$receipt)),
      "authoritative computation"
    )
  })
  deputy::subagent_chat_server(
    "child",
    lead = workflow$lead,
    requester = function() owner
  )
}

shinyApp(ui, server)
