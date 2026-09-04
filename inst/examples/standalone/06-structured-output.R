# Run with Rscript after installing deputy and setting OPENAI_API_KEY.
library(deputy)
chat <- ellmer::chat_openai(
  model = Sys.getenv("DEPUTY_EXAMPLE_MODEL", "gpt-4o-mini")
)

agent <- Agent$new(
  chat = chat,
  tools = list(),
  usage_limits = UsageLimits(max_requests = 3)
)
result <- agent$run_sync(
  'Return a JSON object with status equal to "ok".',
  output_format = list(type = "json_object")
)
# json_object parses JSON; it does not validate a JSON Schema.
stopifnot(isTRUE(result$structured_output$valid))
print(result$structured_output$parsed)
