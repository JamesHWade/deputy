# Run with Rscript after installing deputy and setting OPENAI_API_KEY.
# Two independent one-request perspectives, then one synthesis request.
library(deputy)
rlang::check_installed("yaml", reason = "to load the debate skill")
model <- Sys.getenv("DEPUTY_EXAMPLE_MODEL", "gpt-4o-mini")
question <- Sys.getenv(
  "DEPUTY_DEBATE_TOPIC",
  "Should a small R package adopt a mandatory code review for every change?"
)

lead <- LeadAgent$new(
  chat = ellmer::chat_openai(model = model),
  sub_agents = list(
    agent_definition(
      "support",
      "Makes the strongest case for the proposal",
      paste(
        "Make the strongest case FOR the supplied proposal in one paragraph.",
        "State the key assumption and one limitation. Do not invent evidence."
      )
    ),
    agent_definition(
      "challenge",
      "Makes the strongest case against the proposal",
      paste(
        "Make the strongest case AGAINST the supplied proposal in one paragraph.",
        "State the key assumption and one limitation. Do not invent evidence."
      )
    )
  ),
  permissions = permissions_readonly(),
  usage_limits = UsageLimits(max_requests = 2)
)
batch <- lead$parallel_delegate(
  c(support = question, challenge = question),
  max_active = 2,
  run_context = list(workflow = "two-headed-debate")
)

# Keep a useful comparison even if one head fails or is interrupted.
perspectives <- vapply(
  names(batch$status),
  function(name) {
    text <- batch$results[[name]]$response
    if (!identical(batch$status[[name]], "completed")) {
      text <- paste0("[", batch$status[[name]], "] ", text)
    }
    paste(text, collapse = "")
  },
  character(1)
)
markdown_cell <- function(text) {
  text <- gsub("&", "&amp;", text, fixed = TRUE)
  text <- gsub("<", "&lt;", text, fixed = TRUE)
  text <- gsub(">", "&gt;", text, fixed = TRUE)
  text <- gsub("|", "&#124;", text, fixed = TRUE)
  gsub("\r\n|\r|\n", "<br>", text)
}
comparison <- paste(
  "| Supporting perspective | Challenging perspective |",
  "| --- | --- |",
  paste0(
    "| ",
    markdown_cell(perspectives[["support"]]),
    " | ",
    markdown_cell(perspectives[["challenge"]]),
    " |"
  ),
  sep = "\n"
)
cli::cli_verbatim(comparison)
if (!all(batch$status == "completed") || !all(nzchar(trimws(perspectives)))) {
  cli::cli_abort(
    "Debate incomplete. Inspect {.code batch} before retrying or synthesizing."
  )
}

# Synthesis is a separate, tool-free run with its own one-request budget.
moderator <- Agent$new(
  chat = ellmer::chat_openai(model = model),
  tools = list(),
  permissions = permissions_readonly(),
  usage_limits = UsageLimits(max_requests = 1, max_tool_calls = 0)
)
moderator$load_skill(system.file("skills", "debate", package = "deputy"))
synthesis <- moderator$run_sync(paste(
  "Question:",
  question,
  "Supporting perspective:",
  perspectives[["support"]],
  "Challenging perspective:",
  perspectives[["challenge"]],
  sep = "\n\n"
))
if (!identical(synthesis$stop_reason, "complete")) {
  cli::cli_abort(
    "Synthesis stopped early. Inspect {.code synthesis} for partial output."
  )
}
cli::cli_verbatim(synthesis$response)
requests_used <- batch$run$usage$requests + synthesis$usage$requests
cli::cli_inform(
  "Model requests across perspectives and synthesis: {requests_used}"
)
