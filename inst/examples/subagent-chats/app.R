library(shiny)
library(bslib)
library(deputy)
source("fixture.R", local = TRUE)

ui <- page_fluid(
  title = "Deputy child conversations",
  theme = bs_theme(
    version = 5,
    primary = "#275d64",
    bg = "#f7f8f6",
    fg = "#203638"
  ),
  tags$h1("Subagent conversations"),
  tags$p("One lead conversation, with separately inspectable child histories."),
  layout_columns(
    col_widths = c(4, 8),
    card(
      fill = FALSE,
      card_header("Lead conversation"),
      card_body(
        fill = FALSE,
        actionButton("run", "Run two specialists", class = "btn-primary"),
        actionButton("repeat", "Repeat analyst"),
        checkboxInput("fail", "Fail auditor after its tool result", FALSE),
        checkboxInput("large", "Include a large answer", FALSE),
        tags$div(
          role = "status",
          `aria-live` = "polite",
          textOutput("run_status")
        ),
        shinychat::chat_ui(
          "lead",
          class = "deputy-readonly-chat",
          height = "420px",
          width = "100%",
          show_history = FALSE,
          enable_cancel = FALSE,
          drawer = FALSE,
          fill = FALSE
        ),
        tags$hr(),
        actionButton("restore", "Restore saved child history"),
        actionButton("lineage", "Show nested lineage fixture"),
        actionButton("live", "Return to live children"),
        actionButton("deny", "Deny child access"),
        actionButton("allow", "Allow child access"),
        tags$small(textOutput("metrics")),
        tags$p(
          "Local deterministic fixture · no paid model calls",
          class = "text-muted"
        )
      )
    ),
    subagent_chat_ui("children", height = "420px")
  )
)

server <- function(input, output, session) {
  fixture <- child_chat_fixture()
  session$onSessionEnded(fixture$close)
  owner <- new.env(parent = emptyenv())
  owner$allowed <- TRUE
  owner$effects <- 0L
  scope <- list(owner_id = "demo-owner", conversation_id = "demo-lead")
  disclosure <- DelegationDisclosure(authorize = function(requester, scope) {
    identical(requester, owner) && isTRUE(owner$allowed)
  })
  tool <- ellmer::tool(
    function() {
      owner$effects <- owner$effects + 1L
      path <- tempfile(fileext = ".png")
      grDevices::png(path, width = 500, height = 280)
      graphics::plot(
        c(1, 2, 3),
        c(4, 7, 6),
        type = "b",
        col = "#275d64",
        xlab = "Sample",
        ylab = "Observed value",
        main = "Fixture evidence"
      )
      grDevices::dev.off()
      on.exit(unlink(path), add = TRUE)
      ellmer::ContentToolResult(list(
        ellmer::ContentText(
          "Observed values: 4, 7, 6. Conditions need confirmation. <script>window.deputyInjected=true</script>"
        ),
        ellmer::content_image_file(path, resize = "none")
      ))
    },
    name = "inspect_evidence",
    description = "Read deterministic local evidence",
    arguments = list(),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE
    )
  )
  artifact_dir <- tempfile("demo-artifacts-")
  session$onSessionEnded(function() unlink(artifact_dir, recursive = TRUE))
  lead <- LeadAgent$new(
    fixture$chat(),
    sub_agents = list(
      agent_definition(
        "analyst",
        "Analyze evidence",
        "DEMO_ANALYST: Inspect evidence and report limits.",
        tools = list(tool),
        max_requests = 3L
      ),
      agent_definition(
        "auditor",
        "Audit the result",
        "DEMO_AUDITOR: Independently inspect evidence.",
        tools = list(tool),
        max_requests = 3L
      )
    ),
    permissions = permissions_full(),
    delegation_scope = scope,
    delegation_disclosure = disclosure,
    delegation_observation = DelegationObservation(max_events = 8L),
    context_policy = ContextPolicy(offload_dir = artifact_dir)
  )
  history <- reactiveVal(NULL)
  saved_scope <- reactiveVal(NULL)
  busy <- reactiveVal(FALSE)
  run_status <- reactiveVal("Ready to start a local fixture run.")
  current_signature <- NULL
  launch <- function(task) {
    if (busy()) {
      return()
    }
    history(NULL)
    busy(TRUE)
    fixture$scenario(isTRUE(input$fail), isTRUE(input$large))
    run_status("Specialists are running. Select a child to inspect its work.")
    promise <- lead$run_async(task)
    promises::then(
      promise,
      onFulfilled = function(result) {
        busy(FALSE)
        run_status(paste("Lead stopped:", result$stop_reason))
      },
      onRejected = function(error) {
        busy(FALSE)
        run_status(conditionMessage(error))
      }
    )
    invisible(NULL)
  }
  observeEvent(
    input$run,
    launch("Ask both specialists to inspect the evidence.")
  )
  observeEvent(
    input[["repeat"]],
    launch("Repeat analyst with a fresh child conversation.")
  )
  observeEvent(input$restore, {
    if (busy()) {
      run_status("Wait for settlement before exporting history.")
      return()
    }
    tryCatch(
      {
        snapshot <- lead$export_subagents(owner)
        path <- tempfile(fileext = ".rds")
        saveRDS(snapshot, path)
        saved_scope(c(
          scope,
          list(agent_id = lead$agent_id, session_id = lead$session_id())
        ))
        history(readRDS(path))
        unlink(path)
        run_status("Showing saved child history. No execution was restored.")
      },
      error = function(error) run_status(conditionMessage(error))
    )
  })
  observeEvent(input$lineage, {
    if (busy()) {
      return()
    }
    snapshot <- lead$export_subagents(owner)
    if (!length(snapshot$children)) {
      return()
    }
    child <- snapshot$children[[1L]]
    parent <- child$outcome$runtime
    child$task <- "Synthetic nested lineage; no grandchild execution"
    child$outcome$runtime$agent_name <- "nested reviewer (fixture)"
    child$outcome$runtime$parent_agent_id <- parent$agent_id
    child$outcome$runtime$parent_run_id <- parent$run_id
    child$outcome$runtime$parent_delegation_id <- parent$delegation_id
    child$outcome$runtime$delegation_id <- "fixture-grandchild"
    child$outcome$runtime$conversation_id <- "fixture-grandchild-conversation"
    child$outcome$runtime$agent_id <- "fixture-grandchild-agent"
    child$outcome$runtime$run_id <- "fixture-grandchild-run"
    child$manifest <- NULL
    child$outcome$references <- list()
    child$outcome$answer <- "Synthetic lineage only. Recursive execution remains unsupported."
    child$transcript <- lapply(
      list(
        ellmer::UserTurn(list(ellmer::ContentText(child$task))),
        ellmer::AssistantTurn(list(ellmer::ContentText(child$outcome$answer)))
      ),
      ellmer::contents_record
    )
    snapshot$children <- c(snapshot$children, list(child))
    saved_scope(c(
      scope,
      list(agent_id = lead$agent_id, session_id = lead$session_id())
    ))
    history(snapshot)
    run_status("Showing synthetic nested lineage. No grandchild was executed.")
  })
  observeEvent(input$live, history(NULL))
  observeEvent(input$deny, {
    owner$allowed <- FALSE
  })
  observeEvent(input$allow, {
    owner$allowed <- TRUE
  })
  subagent_chat_server(
    "children",
    lead,
    requester = function() owner,
    history = history,
    disclosure = disclosure,
    scope = saved_scope,
    on_cancel = function(id, requester) {
      if (!identical(requester, owner) || !isTRUE(owner$allowed)) {
        cli::cli_abort("Not authorized")
      }
      lead$interrupt_subagent(id, "user_cancelled")
    },
    poll_interval = 500L
  )
  observe({
    invalidateLater(500, session)
    turns <- lead$get_turns()
    signature <- child_chat_signature(turns)
    if (!identical(signature, current_signature)) {
      current_signature <<- signature
      shinychat::chat_clear("lead")
      # The lead remains host-owned; the public Chat conversion groups tool
      # requests and results into the same assistant message for native cards.
      display_chat <- fixture$chat()
      display_chat$set_turns(turns)
      for (message in shinychat::contents_shinychat(display_chat)) {
        shinychat::chat_append_message("lead", message, chunk = FALSE)
      }
    }
  })
  output$run_status <- renderText(run_status())
  output$metrics <- renderText({
    invalidateLater(500, session)
    paste(
      fixture$requests(),
      "model requests ·",
      owner$effects,
      "tool executions"
    )
  })
}
shinyApp(ui, server)
