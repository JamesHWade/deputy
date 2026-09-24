library(shiny)
library(bslib)
source("forecast.R", local = TRUE)
source("fixture.R", local = TRUE)

ui <- page_fluid(
  title = "Trusted forecast",
  tags$h1("Trusted forecast"),
  tags$p(
    "The model proposes inputs. You review them. Only the forecast tool fills the result panel."
  ),
  tags$p(
    "Local deterministic demonstration with a synthetic forecast table. No paid model calls.",
    class = "text-muted"
  ),
  tags$p(
    "Pattern from ",
    tags$a(
      href = "https://trustedminiagents.dev",
      tags$em("Trusted Mini-Agents")
    ),
    " by Will Landau and Sam Parmar.",
    class = "text-muted small"
  ),
  layout_columns(
    col_widths = c(4, 4, 4),
    card(
      card_header("1. Chat (model text, untrusted)"),
      shinychat::chat_ui("chat", height = "360px")
    ),
    card(
      card_header("2. Review the tool inputs"),
      deputy::approval_review_ui("review")
    ),
    card(
      card_header("3. Trusted result"),
      uiOutput("result")
    )
  )
)

server <- function(input, output, session) {
  fixture <- forecast_fixture()
  approval_dir <- tempfile("trusted-forecast-")
  dir.create(approval_dir)
  session$onSessionEnded(function() {
    fixture$close()
    unlink(approval_dir, recursive = TRUE)
  })

  # The only writer of this value is the trusted tool's on_result callback.
  result <- reactiveVal(NULL)
  agent <- forecast_agent(
    fixture$chat(),
    approval_dir,
    on_result = function(event) result(event)
  )

  say <- function(text) {
    if (is.character(text) && length(text) == 1L && nzchar(text)) {
      shinychat::chat_append("chat", text, session = session)
    }
  }

  # shinychat sends the message as text plus any attachment contents. This
  # example uses only the text.
  user_text <- function(value) {
    if (is.list(value) && !is.null(value$text)) {
      return(value$text)
    }
    paste(unlist(Filter(is.character, as.list(value))), collapse = "\n")
  }

  # Runs block this R process; see the README for running them elsewhere.
  observeEvent(input$chat_user_input, {
    run <- agent$run_sync(user_text(input$chat_user_input))
    if (!is.null(agent$pending_approval())) {
      say("I proposed a forecast request. Review its inputs to continue.")
    } else {
      say(run$response)
    }
  })

  review <- deputy::approval_review_server(
    "review",
    agent,
    decide = function(path, decision, tool_input) {
      continued <- agent$resume_approval(
        path,
        decision,
        tool_input = tool_input
      )
      say(continued$response)
      continued
    }
  )

  output$result <- renderUI({
    event <- result()
    if (is.null(event)) {
      return(tags$p(
        "No trusted result yet. Model text cannot fill this panel.",
        class = "text-muted"
      ))
    }
    forecast <- jsonlite::fromJSON(event$value)
    tagList(
      tags$h2(sprintf("%s, %d days", forecast$city, forecast$days)),
      tags$table(
        class = "table table-sm",
        tags$thead(tags$tr(
          tags$th(scope = "col", "Day"),
          tags$th(scope = "col", "High (°C)"),
          tags$th(scope = "col", "Low (°C)")
        )),
        tags$tbody(lapply(seq_len(nrow(forecast$daily)), function(i) {
          tags$tr(
            tags$td(forecast$daily$day[[i]]),
            tags$td(forecast$daily$high_c[[i]]),
            tags$td(forecast$daily$low_c[[i]])
          )
        }))
      ),
      tags$p(
        sprintf("Result %s from %s.", event$result_id, event$tool_name),
        class = "text-muted small"
      ),
      tags$p(forecast$source, class = "text-muted small")
    )
  })
}

shinyApp(ui, server)
