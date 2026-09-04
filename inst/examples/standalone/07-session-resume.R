# Run with Rscript after installing deputy and setting OPENAI_API_KEY.
library(deputy)
chat <- ellmer::chat_openai(
  model = Sys.getenv("DEPUTY_EXAMPLE_MODEL", "gpt-4o-mini")
)

agent <- Agent$new(
  chat = chat,
  tools = list(),
  usage_limits = UsageLimits(max_requests = 3),
  run_context = list(project = "session-example")
)
first <- agent$run_sync("Remember that my example project is called Cedar.")
session_file <- tempfile(fileext = ".rds")
agent$save_session(session_file)
# A new Agent provides the backend and permission ceiling for the resumed chat.
resumed <- Agent$new(
  chat = ellmer::chat_openai(
    model = Sys.getenv("DEPUTY_EXAMPLE_MODEL", "gpt-4o-mini")
  ),
  tools = list(),
  usage_limits = UsageLimits(max_requests = 3)
)
resumed$load_session(session_file)
result <- resumed$run_sync("What is my example project called?")
cli::cli_text("{result$response}")
unlink(session_file)
