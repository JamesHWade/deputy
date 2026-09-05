# Run with Rscript after installing deputy and setting OPENAI_API_KEY.
library(deputy)
chat <- ellmer::chat_openai(
  model = Sys.getenv("DEPUTY_EXAMPLE_MODEL", "gpt-5.6-luna")
)

agent <- Agent$new(
  chat = chat,
  tools = list(),
  usage_limits = UsageLimits(max_requests = 3)
)
result <- agent$run_sync(
  'Return a JSON object with status equal to "ok".',
  type = ellmer::type_object(status = ellmer::type_string()),
  validate = function(x) identical(x$status, "ok"),
  max_corrections = 1L
)
stopifnot(result$is_success())
print(result$structured_output)
