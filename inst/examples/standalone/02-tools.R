# Run with Rscript after installing deputy and setting OPENAI_API_KEY.
library(deputy)
chat <- ellmer::chat_openai(
  model = Sys.getenv("DEPUTY_EXAMPLE_MODEL", "gpt-5.6-luna")
)

workspace <- tempfile("deputy-tools-")
dir.create(workspace)
writeLines(
  "Quarterly revenue increased by 12%.",
  file.path(workspace, "input.txt")
)
agent <- Agent$new(
  chat = chat,
  tools = list(tool_read_file),
  permissions = permissions_readonly(),
  working_dir = workspace,
  usage_limits = UsageLimits(max_requests = 3, max_tool_calls = 2)
)
result <- agent$run_sync("Use read_file to read input.txt, then summarize it.")
cli::cli_text("{result$response}")
print(result$tool_calls())
