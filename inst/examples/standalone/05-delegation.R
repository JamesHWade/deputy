# Run with Rscript after installing deputy and setting OPENAI_API_KEY.
library(deputy)
chat <- ellmer::chat_openai(
  model = Sys.getenv("DEPUTY_EXAMPLE_MODEL", "gpt-4o-mini")
)

reviewer <- agent_definition(
  name = "reviewer",
  description = "Reviews a short R expression",
  prompt = "Explain correctness concerns in the supplied R code.",
  tools = list(),
  permission_mode = "readonly",
  max_requests = 2
)
lead <- LeadAgent$new(
  chat = chat,
  sub_agents = list(reviewer),
  permissions = Permissions$new(
    mode = "standard",
    bash = FALSE,
    r_code = FALSE,
    file_write = FALSE,
    web = FALSE,
    install_packages = FALSE
  ),
  usage_limits = UsageLimits(max_requests = 6, max_tool_calls = 2)
)
result <- lead$run_sync(paste(
  "Delegate a review of mean(c(1, NA)) to reviewer using delegate_to_agent.",
  "Summarize the review."
))
cli::cli_text("{result$response}")
print(lead$list_subagents())
