# Run explicitly after installing this branch of Deputy. No model calls occur
# unless both the live opt-in and an observed cost limit are supplied.
if (!identical(Sys.getenv("DEPUTY_HISTORY_LIVE"), "yes")) {
  cli::cli_abort(
    "Set DEPUTY_HISTORY_LIVE=yes to run the paid model pilot. See README.md."
  )
}
directory <- system.file("examples", "history-recovery", package = "deputy")
for (file in c("fixture.R", "history.R", "evaluation.R")) {
  source(file.path(directory, file), local = TRUE)
}
cost <- as.numeric(Sys.getenv("DEPUTY_HISTORY_MAX_COST_USD", "NA"))
if (is.na(cost) || !is.finite(cost) || cost <= 0) {
  cli::cli_abort(
    "Set a positive DEPUTY_HISTORY_MAX_COST_USD observed spending limit."
  )
}
helpers <- trimws(strsplit(
  Sys.getenv("DEPUTY_HISTORY_HELPERS", "gpt-5.6-luna"),
  ",",
  fixed = TRUE
)[[1L]])
task_model <- trimws(Sys.getenv("DEPUTY_HISTORY_TASK_MODEL", "gpt-5.6-luna"))
trials <- suppressWarnings(as.numeric(Sys.getenv("DEPUTY_HISTORY_TRIALS", "3")))
history_validate_configuration(trials, helpers, task_model)
fixture <- history_fixture(
  scenario = Sys.getenv("DEPUTY_HISTORY_SCENARIO", "original")
)
output <- Sys.getenv("DEPUTY_HISTORY_OUTPUT", "history-recovery-results")
if (dir.exists(output)) {
  cli::cli_abort(
    "Choose a new output directory to preserve prior trial evidence."
  )
}
if (!dir.create(output, recursive = TRUE)) {
  cli::cli_abort("Could not create the output directory.")
}
chat_factory <- function(model) {
  ellmer::chat_openai(
    model = model,
    params = ellmer::params(max_tokens = 1024L, reasoning_effort = "low"),
    echo = "none"
  )
}
evaluation <- history_evaluate(
  chat_factory,
  fixture = fixture,
  trials = trials,
  helper_models = helpers,
  task_model = task_model,
  max_cost_usd = cost
)
jsonlite::write_json(
  evaluation,
  file.path(output, "results.json"),
  auto_unbox = TRUE,
  pretty = TRUE,
  null = "null",
  na = "null"
)
writeLines(history_report(evaluation), file.path(output, "report.md"))
cli::cli_inform("Saved trial evidence to {.path {output}}.")
if (!is.null(evaluation$failure)) {
  cli::cli_abort(
    "The pilot stopped early: {evaluation$failure$class}. Partial evidence was saved."
  )
}
