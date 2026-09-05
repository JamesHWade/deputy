# A small external runner: replace these cases and the scoring rule with your
# application's dataset. Deputy supplies governed results, not a scoring DSL.
library(deputy)
cases <- data.frame(
  id = c("addition", "capital"),
  prompt = c(
    "What is 2 + 2? Reply with the number only.",
    "What is the capital of France? Reply with the city only."
  ),
  expected = c("4", "Paris")
)

rows <- lapply(seq_len(nrow(cases)), function(i) {
  agent <- Agent$new(
    ellmer::chat_openai(
      model = Sys.getenv("DEPUTY_EXAMPLE_MODEL", "gpt-5.6-luna")
    ),
    permissions = permissions_readonly(),
    usage_limits = UsageLimits(max_requests = 2),
    run_context = list(evaluation = list(case_id = cases$id[[i]]))
  )
  failure <- NULL
  result <- tryCatch(agent$run_sync(cases$prompt[[i]]), error = function(e) {
    failure <<- class(e)[[1L]]
    agent$last_run()
  })
  data.frame(
    case_id = cases$id[[i]],
    run_id = result$run_id,
    session_id = result$session_id,
    stop_reason = result$stop_reason,
    passed = is.null(failure) &&
      result$is_success() &&
      identical(trimws(result$response), cases$expected[[i]]),
    requests = result$usage$requests,
    reported_tokens = result$usage$total_tokens,
    cost_usd = result$usage$cost_usd,
    duration_seconds = result$duration,
    error_class = if (is.null(failure)) NA_character_ else failure
  )
})
evaluation <- do.call(rbind, rows)
print(evaluation)
# run_id matches the deputy.run span's deputy.run.id attribute when an otel
# tracer is configured before ellmer is loaded. No message capture is required.
