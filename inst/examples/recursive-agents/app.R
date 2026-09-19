library(shiny)
library(bslib)
library(shinychat)
library(deputy)

source("fixture.R", local = TRUE)
source("workflow.R", local = TRUE)

ui <- page_fluid(
  title = "Recursive retained agents",
  theme = bs_theme(
    version = 5,
    primary = "#275d64",
    bg = "#f7f8f6",
    fg = "#203638"
  ),
  tags$h1("Recursive retained agents"),
  tags$p(
    "One host routes an analyst to a reviewer. Each child keeps its own history, while the host owns budgets, inspection and cancellation."
  ),
  layout_columns(
    col_widths = c(5, 7),
    card(
      fill = FALSE,
      card_header("Host run"),
      actionButton(
        "run",
        "Run root → analyst → reviewer",
        class = "btn-primary"
      ),
      actionButton("followup", "Follow up with analyst"),
      actionButton("cancel", "Cancel active graph"),
      tags$div(
        role = "status",
        `aria-live` = "polite",
        textOutput("status")
      ),
      shinychat::chat_ui(
        "root_chat",
        class = "deputy-readonly-chat",
        height = "430px",
        width = "100%",
        show_history = FALSE,
        enable_cancel = FALSE,
        drawer = FALSE,
        fill = FALSE
      ),
      tags$p(
        "The graph budget is cumulative across retained follow-ups. The host can borrow each child only through its declared route.",
        class = "text-muted"
      )
    ),
    subagent_chat_ui("children", height = "430px")
  ),
  tags$p(
    "Local deterministic HTTP fixture · no credentials · no paid model calls",
    class = "text-muted"
  ),
  textOutput("metrics")
)

server <- function(input, output, session) {
  fixture <- recursive_local_fixture(delay = 0.5)
  graph <- recursive_agents(fixture)
  root <- graph$root
  requester <- graph$requester
  busy <- reactiveVal(FALSE)
  status <- reactiveVal(
    "Ready. Run the root to select a retained analyst or reviewer transcript."
  )

  finish <- function(message) {
    busy(FALSE)
    status(message)
    invisible(NULL)
  }
  run_promise <- function(promise, completed) {
    busy(TRUE)
    promises::then(
      promise,
      onFulfilled = function(result) finish(completed(result)),
      onRejected = function(error) finish(conditionMessage(error))
    )
    invisible(NULL)
  }
  append_root_stream <- function(stream) {
    shinychat::chat_append("root_chat", stream, session = session)
  }
  followup_stream <- function() {
    coro::async_generator(function() {
      result <- coro::await(root$continue_agent_async(
        graph$handles[["analyst"]],
        "Follow-up using the retained analyst and reviewer history.",
        UsageLimits(max_requests = 1L)
      ))
      if (!is.null(result$response)) {
        coro::yield(ellmer::ContentText(result$response))
      }
    })()
  }

  observeEvent(input$run, {
    if (busy()) {
      return()
    }
    status("The host is running the root → analyst → reviewer route.")
    run_promise(
      append_root_stream(root$stream_async(
        "Analyze the fixture evidence and ask the reviewer to check it.",
        stream = "content"
      )),
      function(result) paste("Graph stopped:", root$last_run()$stop_reason)
    )
  })
  observeEvent(input$followup, {
    if (busy()) {
      return()
    }
    status("The host is continuing the retained analyst conversation.")
    run_promise(
      append_root_stream(followup_stream()),
      function(result) {
        paste(
          "Follow-up stopped:",
          graph$agents$analyst$last_run()$stop_reason
        )
      }
    )
  })
  observeEvent(input$cancel, {
    if (busy()) {
      root$interrupt("user_cancelled")
      status("Cancellation requested for the active graph.")
    }
  })

  shinychat::chat_server("root_chat", root, history = FALSE)
  subagent_chat_server(
    "children",
    root,
    requester = function() requester,
    on_cancel = function(id, candidate) {
      if (!identical(candidate, requester)) {
        cli::cli_abort("Not authorized")
      }
      root$interrupt_subagent(id, "user_cancelled")
    },
    poll_interval = 250L
  )

  output$status <- renderText(status())
  output$metrics <- renderText({
    invalidateLater(250L, session)
    usage <- tryCatch(root$delegation_graph_usage(), error = function(e) NULL)
    requests <- if (is.null(usage)) NA_integer_ else usage$requests
    tools <- if (is.null(usage)) NA_integer_ else usage$tool_calls
    paste(
      length(fixture$requests()),
      "local model requests ·",
      requests,
      "graph requests ·",
      tools,
      "graph tool calls"
    )
  })
  session$onSessionEnded(function() {
    root$interrupt("session_ended")
    deadline <- Sys.time() + 5
    released <- FALSE
    while (Sys.time() < deadline && !released) {
      released <- isTRUE(tryCatch(
        {
          root$release_agent_graph()
          TRUE
        },
        error = function(error) FALSE
      ))
      if (released) {
        break
      }
      later::run_now(0.05)
    }
    if (!released) {
      try(root$release_agent_graph(), silent = TRUE)
    }
    fixture$close()
  })
}

shinyApp(ui, server)
