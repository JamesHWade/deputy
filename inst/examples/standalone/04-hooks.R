# Run with Rscript after installing deputy and setting OPENAI_API_KEY.
library(deputy)
chat <- ellmer::chat_openai(
  model = Sys.getenv("DEPUTY_EXAMPLE_MODEL", "gpt-4o-mini")
)

workspace <- tempfile("deputy-hooks-")
dir.create(workspace)
writeLines(
  "Quarterly revenue increased by 12%.",
  file.path(workspace, "input.txt")
)
audit <- list()
agent <- Agent$new(
  chat = chat,
  tools = list(tool_read_file),
  permissions = permissions_readonly(),
  working_dir = workspace,
  usage_limits = UsageLimits(max_requests = 3, max_tool_calls = 2)
)
agent$add_hook(HookMatcher$new(
  event = "PostToolUse",
  timeout = 0,
  callback = function(tool_name, tool_result, tool_error, context) {
    audit[[length(audit) + 1L]] <<- list(
      tool = tool_name,
      run_id = context$run_id,
      error = tool_error
    )
    HookResultPostToolUse()
  }
))
result <- agent$run_sync("Use read_file to read input.txt, then summarize it.")
print(audit)
