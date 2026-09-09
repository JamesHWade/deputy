library(shiny)
library(deputy)
library(shinychat)

source("compaction-notice.R", local = TRUE)

ui <- bslib::page_fluid(
  compaction_notice_ui("compaction"),
  chat_ui("chat", fill = TRUE)
)

server <- function(input, output, session) {
  chat <- ellmer::chat_openai(
    model = "gpt-5.6-luna",
    system_prompt = "You are a helpful assistant that can read and analyse
      files. Be concise."
  )

  # Deputy adds permissions and hooks on top of the ellmer chat
  agent <- Agent$new(
    chat = chat,
    tools = c(tools_file(), list(tool_read_csv)),
    permissions = Permissions(
      file_read = TRUE,
      file_write = FALSE,
      r_code = FALSE,
      bash = FALSE
    )
  )
  agent$add_hook(hook_log_tools(verbose = TRUE))

  # Agent is a drop-in ellmer chat. shinychat owns input, attachments,
  # cancellation, and history while Deputy governs every run.
  chat_module <- chat_server("chat", agent)
  compaction_notice_server("compaction", agent, chat_module, session)
}

shinyApp(ui, server)
