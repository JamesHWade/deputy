library(shiny)
library(deputy)
library(shinychat)

ui <- bslib::page_fluid(
  chat_ui("chat", fill = TRUE)
)

server <- function(input, output, session) {
  chat <- ellmer::chat_openai(
    model = "gpt-4o-mini",
    system_prompt = "You are a helpful assistant that can read and analyse
      files. Be concise."
  )

  # Deputy adds permissions and hooks on top of the ellmer chat
  agent <- Agent$new(
    chat = chat,
    tools = c(tools_file(), tools_data()),
    permissions = Permissions$new(
      file_read = TRUE,
      file_write = FALSE,
      r_code = FALSE,
      bash = FALSE
    )
  )
  agent$add_hook(hook_log_tools(verbose = TRUE))

  # run_shiny() returns a content stream with deputy's permissions, hooks,

  # and tool call limits enforced
  observeEvent(input$chat_user_input, {
    stream <- agent$run_shiny(input$chat_user_input)
    chat_append("chat", stream)
  })
}

shinyApp(ui, server)
