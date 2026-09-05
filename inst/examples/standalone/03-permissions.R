# Run with Rscript after installing deputy and setting OPENAI_API_KEY.
library(deputy)
chat <- ellmer::chat_openai(
  model = Sys.getenv("DEPUTY_EXAMPLE_MODEL", "gpt-5.6-luna")
)

workspace <- tempfile("deputy-permissions-")
dir.create(workspace)
agent <- Agent$new(
  chat = chat,
  tools = list(tool_write_file),
  permissions = permissions_readonly(),
  working_dir = workspace,
  usage_limits = UsageLimits(max_requests = 3, max_tool_calls = 2)
)
# Registering a tool does not grant permission to execute it.
result <- agent$run_sync("Use write_file to write hello to blocked.txt.")
stopifnot(!file.exists(file.path(workspace, "blocked.txt")))
cli::cli_text("{result$response}")
# Switching modes may narrow authority, never widen it.
print(agent$permissions$check("write_file", list(path = "blocked.txt")))
