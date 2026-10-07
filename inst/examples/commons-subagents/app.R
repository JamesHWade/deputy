library(shiny)
library(bslib)
library(shinychat)
library(deputy)

source("fixture.R", local = TRUE)
source("workflow.R", local = TRUE)

# One local model server and one history store for the whole app, so a
# reloaded page reopens its conversation and the counts below cover every
# session.
fixture <- commons_local_fixture(delay = 0.2, slow = 6)
history_dir <- file.path(tempdir(), "deputy-commons-subagents-history")
store <- shinychat::FileConversationStore$new(history_dir)
effects <- commons_example_effects()
onStop(function() fixture$close())

greeting <- paste(
  "Ask about sales and operations. The specialists' tool calls appear in",
  "this conversation, and every trusted measure is listed on the right.",
  "\n\n",
  "* <span class=\"suggestion\">Report revenue by region and on-time",
  "delivery.</span>\n",
  "* <span class=\"suggestion\">Ask sales again.</span>\n",
  "* <span class=\"suggestion\">Run a slow operations check.</span>"
)

ui <- page_fillable(
  title = "Commons subagents",
  theme = bs_theme(
    version = 5,
    primary = "#2f6f73",
    bg = "#f8f8f6",
    fg = "#1f3133"
  ),
  layout_columns(
    col_widths = c(7, 5),
    card(
      card_header("Conversation"),
      chat_ui("chat", height = "640px", fill = TRUE)
    ),
    tags$div(
      card(
        card_header("Trusted results this session"),
        uiOutput("trusted"),
        fill = FALSE
      ),
      card(
        card_header("Subagents"),
        subagent_chat_ui("subagents", height = "360px"),
        fill = FALSE
      ),
      tags$p(
        class = "text-muted small",
        role = "status",
        textOutput("metrics", inline = TRUE)
      )
    )
  )
)

server <- function(input, output, session) {
  requester <- "demo-user"
  user <- function() requester
  trusted <- reactiveVal(list())
  workflow <- commons_example_workflow(
    fixture,
    effects,
    on_result = function(event) trusted(c(trusted(), list(event))),
    requester = requester
  )
  root <- workflow$root

  chat <- chat_server(
    "chat",
    root,
    greeting = greeting,
    history = history_options(store = store, scope = "demo", title = NULL)
  )
  subagent_chat_activity(chat, root, user)
  saved <- subagent_chat_history(chat, root, user)
  subagent_chat_server(
    "subagents",
    root,
    user,
    conversation = saved,
    on_cancel = function(delegation_id, who) {
      if (identical(who, requester)) {
        root$interrupt_subagent(delegation_id, "user_cancelled")
      }
    }
  )

  output$trusted <- renderUI({
    events <- trusted()
    if (!length(events)) {
      return(tags$p(
        class = "text-muted",
        "No trusted measure has run in this session."
      ))
    }
    rows <- lapply(events, function(event) {
      value <- event$value
      if (inherits(value, "ellmer::ContentToolResult")) {
        value <- value@value
      }
      tags$tr(
        tags$td(event$arguments$name %||% event$tool_name),
        tags$td(event$agent_name %||% "root"),
        tags$td(substr(paste(format(value), collapse = " "), 1L, 80L))
      )
    })
    tags$table(
      class = "table table-sm",
      id = "trusted-results",
      tags$thead(tags$tr(
        tags$th("Measure"),
        tags$th("From"),
        tags$th("Value")
      )),
      tags$tbody(rows)
    )
  })
  output$metrics <- renderText({
    invalidateLater(500L, session)
    paste(
      length(fixture$requests()),
      "local model requests ·",
      effects$runs,
      "measure runs in this app"
    )
  })

  session$onSessionEnded(function() commons_example_release(workflow))
}

shinyApp(ui, server)
