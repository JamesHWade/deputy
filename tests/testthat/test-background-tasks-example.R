background_example_directory <- function() {
  source <- test_path("..", "..", "inst", "examples", "background-tasks")
  if (dir.exists(source)) {
    return(normalizePath(source))
  }
  system.file(
    "examples",
    "background-tasks",
    package = "deputy",
    mustWork = TRUE
  )
}

background_example_environment <- function() {
  environment <- new.env(parent = as.environment("package:deputy"))
  directory <- background_example_directory()
  for (file in c("fixture.R", "workflow.R", "report.R")) {
    sys.source(file.path(directory, file), envir = environment)
  }
  environment
}

background_example_skip <- function() {
  skip_if_not_installed("callr")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("jsonlite")
}

test_that("the background tasks script runs and prints what a host sees", {
  background_example_skip()
  script <- new.env(parent = as.environment("package:deputy"))
  output <- capture.output(
    sys.source(
      file.path(background_example_directory(), "run.R"),
      envir = script
    )
  )

  expect_identical(script$result$stop_reason, "complete")
  expect_match(script$result$response, "^LEAD: batch 12 has a mean viscosity")
  expect_identical(script$tasks$agent, c("analyst", "reviewer", "analyst"))
  expect_identical(
    script$tasks$state,
    c("completed", "cancelled", "completed")
  )
  expect_identical(script$tasks$collected, c(TRUE, TRUE, TRUE))
  expect_identical(
    script$tasks$previous_task_id,
    c(NA, NA, script$tasks$task_id[[1L]])
  )

  section <- function(title) {
    start <- which(output == paste0("== ", title, " =="))
    expect_length(start, 1L)
    rest <- output[-seq_len(start)]
    end <- grep("^== ", rest)
    rest <- if (length(end)) rest[seq_len(end[[1L]] - 1L)] else rest
    rest[nzchar(rest)]
  }
  expect_identical(
    section("Tool activity from lead$observe_subagents()"),
    c(
      "analyst: load_measurements started",
      "reviewer: read_draft started",
      "analyst: load_measurements finished",
      "reviewer: read_draft finished"
    )
  )
  expect_identical(
    section("The analyst's conversation, from lead$inspect_subagents()"),
    c(
      "user: Summarize the viscosity measurements for batch 12.",
      "assistant: [calls load_measurements]",
      "user: [load_measurements returned] Viscosity (Pa.s): 4.1, 4.2, 4.3",
      "assistant: ANALYST: three measurements, mean 4.2 Pa.s, range 4.1 to 4.3.",
      "user: Is the mean within the specification of 4.0 to 4.5 Pa.s?",
      paste(
        "assistant: ANALYST: yes. The mean of 4.2 Pa.s from the measurements",
        "I loaded earlier is within 4.0 to 4.5 Pa.s."
      )
    )
  )
  outcomes <- section("Outcomes")
  expect_length(outcomes, 3L)
  expect_match(
    outcomes[[1L]],
    "^1 analyst \\(completed, 2 requests\\): ANALYST"
  )
  expect_identical(
    outcomes[[2L]],
    "2 reviewer (cancelled, 1 request): no answer"
  )
  expect_match(
    outcomes[[3L]],
    "^3 analyst \\(completed, 1 request\\): ANALYST: yes"
  )
  expect_identical(
    section("Usage of the lead's run"),
    "11 requests, 9 tool calls"
  )
})

test_that("the example's lead works while its tasks run", {
  background_example_skip()
  example <- background_example_environment()
  fixture <- example$background_local_fixture()
  withr::defer(fixture$close())
  setup <- example$background_example(fixture)
  withr::defer(example$background_example_release(setup))

  result <- setup$lead$run_sync("Report on batch 12.")

  # The lead's own tool ran while both tasks were running.
  expect_identical(setup$seen$while_working$agent, c("analyst", "reviewer"))
  expect_identical(setup$seen$while_working$state, c("running", "running"))
  # Each specialist's tool ran once: the follow-up used the analyst's retained
  # conversation, and the reviewer was cancelled during its only call.
  expect_identical(setup$gates$analyst$calls, 1L)
  expect_identical(setup$gates$reviewer$calls, 1L)

  models <- vapply(
    fixture$requests(),
    function(request) request$body$model,
    character(1)
  )
  expect_identical(
    as.list(table(models)),
    list(
      "background-analyst" = 3L,
      "background-lead" = 7L,
      "background-reviewer" = 1L
    )
  )
  # The lead made its second and third requests before the analyst's first
  # task could continue, and the cancelled reviewer made no further request.
  lead <- which(models == "background-lead")
  analyst <- which(models == "background-analyst")
  expect_lt(lead[[3L]], analyst[[2L]])
  expect_identical(result$usage$requests, 11L)

  subagents <- setup$lead$list_subagents()
  expect_identical(
    subagents$status,
    c("completed", "stopped", "completed")
  )
  tasks <- setup$lead$background_tasks()
  views <- setup$lead$inspect_subagents(
    setup$requester,
    tasks$delegation_id[[3L]],
    transcript = TRUE
  )
  expect_length(views[[1L]]$turns, 6L)
  expect_identical(
    views[[1L]]$outcome$runtime$previous_delegation_id,
    tasks$delegation_id[[1L]]
  )
  expect_error(
    setup$lead$inspect_subagents("someone else", tasks$delegation_id[[3L]])
  )
})
