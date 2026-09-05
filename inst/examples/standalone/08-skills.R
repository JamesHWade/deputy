# Run with Rscript after installing deputy and setting OPENAI_API_KEY.
library(deputy)
rlang::check_installed("yaml", reason = "to run this example")
chat <- ellmer::chat_openai(
  model = Sys.getenv("DEPUTY_EXAMPLE_MODEL", "gpt-5.6-luna")
)

skill_dir <- tempfile("deputy-skill-")
dir.create(skill_dir)
writeLines(
  c(
    "---",
    "name: concise-review",
    "description: Concise R reviews",
    "---",
    "Review code in two bullets: correctness, then readability."
  ),
  file.path(skill_dir, "SKILL.md")
)
agent <- Agent$new(
  chat = chat,
  tools = list(),
  usage_limits = UsageLimits(max_requests = 3)
)
agent$load_skill(skill_dir)
result <- agent$run_sync("Review mean(c(1, NA)).")
cli::cli_text("{result$response}")

unlink(skill_dir, recursive = TRUE)
