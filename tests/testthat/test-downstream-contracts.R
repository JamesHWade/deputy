# Values that other packages read. suppose seals the R execution record into
# its analyses and records run receipts; crucible reads the executed code.
# Adding a field is compatible. Renaming or removing one needs a new
# schema_version and a note in NEWS.md.

test_that("the R execution record keeps its version 1 fields", {
  result <- r_session_result(
    code = "1 + 1",
    segments = list(list(type = "stdout", text = "[1] 2")),
    session_id = "session_contract",
    execution_id = "execution_contract",
    generation = 1L,
    fresh = FALSE,
    reset_reason = NULL,
    outcome = "complete"
  )
  record <- result@extra$deputy_r

  expect_identical(record$schema_version, 1L)
  expect_contains(
    names(record),
    c(
      "schema_version",
      "code",
      "session_id",
      "execution_id",
      "generation",
      "fresh",
      "reset_reason",
      "outcome",
      "segments"
    )
  )
  expect_identical(record$code, "1 + 1")
})

test_that("run results keep the fields hosts record as receipts", {
  agent <- Agent$new(create_mock_chat(list("done")))
  agent$run_sync("task")
  result <- agent$last_run()

  expect_s7_class(result, AgentResult)
  for (field in c("run_id", "agent_id", "session_id", "stop_reason")) {
    expect_true(is_nonempty_string(S7::prop(result, field)), label = field)
  }
  expect_true(is.numeric(result$duration))
  for (field in c(
    "requests",
    "tool_calls",
    "input_tokens",
    "output_tokens",
    "total_tokens"
  )) {
    expect_true(is.numeric(S7::prop(result$usage, field)), label = field)
  }
})
