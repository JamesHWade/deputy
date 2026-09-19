recursive_example_directory <- function() {
  source <- test_path("..", "..", "inst", "examples", "recursive-agents")
  if (dir.exists(source)) {
    return(normalizePath(source))
  }
  system.file(
    "examples",
    "recursive-agents",
    package = "deputy",
    mustWork = TRUE
  )
}

recursive_example_environment <- function() {
  environment <- new.env(parent = as.environment("package:deputy"))
  directory <- recursive_example_directory()
  sys.source(file.path(directory, "fixture.R"), envir = environment)
  sys.source(file.path(directory, "workflow.R"), envir = environment)
  environment
}

test_that("the recursive example runs three real streaming levels", {
  skip_if_not_installed("callr")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("jsonlite")

  example <- recursive_example_environment()
  fixture <- example$recursive_local_fixture(delay = 0.01)
  withr::defer(fixture$close())
  graph <- example$recursive_agents(fixture)
  withr::defer(
    try(graph$root$release_agent_graph(), silent = TRUE)
  )

  result <- graph$root$run_sync(
    "Analyze the fixture evidence and ask the reviewer to check it."
  )

  expect_match(
    trimws(result$response),
    "^ROOT: the analyst and reviewer agree on the bounded evidence\\.$"
  )
  expect_identical(result$usage$requests, 6L)
  expect_identical(graph$effects$count, 1L)

  requests <- fixture$requests()
  expect_length(requests, 6L)
  expect_true(all(vapply(
    requests,
    function(request) identical(request$path, "/v1/chat/completions"),
    logical(1)
  )))
  expect_identical(
    vapply(requests, function(request) request$body$model, character(1)),
    c(
      "recursive-root",
      "recursive-analyst",
      "recursive-analyst",
      "recursive-reviewer",
      "recursive-analyst",
      "recursive-root"
    )
  )

  expect_identical(graph$root$delegation_graph_usage()$requests, 6L)
  expect_identical(graph$root$delegation_graph_usage()$tool_calls, 3L)

  rows <- graph$root$list_subagents()
  expect_identical(rows$agent_name, c("analyst", "reviewer"))
  expect_identical(rows$depth, c(1L, 2L))
  expect_identical(
    rows$parent_agent_id,
    c(
      graph$root$agent_id,
      graph$agents$analyst$agent_id
    )
  )
  expect_identical(rows$root_agent_id, rep(graph$root$agent_id, 2L))
  expect_identical(rows$parent_delegation_id[[2L]], rows$delegation_id[[1L]])
  expect_identical(rows$status, c("completed", "completed"))

  views <- graph$root$inspect_subagents(
    graph$requester,
    transcript = TRUE
  )
  expect_length(views, 2L)
  expect_true(all(vapply(
    views,
    function(view) {
      length(view$transcript) > 0L
    },
    logical(1)
  )))
  expect_identical(
    views[[1L]]$outcome$runtime$parent_delegation_id,
    NULL
  )
  expect_identical(
    views[[2L]]$outcome$runtime$parent_delegation_id,
    rows$delegation_id[[1L]]
  )
  expect_identical(views[[1L]]$outcome$runtime$depth, 1L)
  expect_identical(views[[2L]]$outcome$runtime$depth, 2L)

  graph$root$release_agent_graph()
  expect_error(
    graph$root$delegation_graph_usage(),
    class = "deputy_conversation"
  )
})

test_that("the recursive example keeps graph budgets across retained follow-ups", {
  skip_if_not_installed("callr")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("jsonlite")

  example <- recursive_example_environment()
  fixture <- example$recursive_local_fixture(delay = 0.01)
  withr::defer(fixture$close())
  graph <- example$recursive_agents(fixture)
  withr::defer(
    try(graph$root$release_agent_graph(), silent = TRUE)
  )

  graph$root$run_sync(
    "Analyze the fixture evidence and ask the reviewer to check it."
  )
  followup <- graph$root$continue_agent(
    graph$handles[["analyst"]],
    "Follow-up using the retained analyst and reviewer history.",
    UsageLimits(max_requests = 1L)
  )

  expect_match(
    trimws(followup$response),
    "^ANALYST: follow-up complete using the retained graph history\\.$"
  )
  expect_identical(followup$usage$requests, 1L)
  expect_identical(graph$effects$count, 1L)
  expect_identical(graph$root$delegation_graph_usage()$requests, 7L)
  expect_identical(graph$root$delegation_graph_usage()$tool_calls, 3L)
  expect_length(fixture$requests(), 7L)

  followup_rows <- graph$root$list_subagents()
  expect_identical(followup_rows$depth, c(1L, 2L, 1L))
  expect_identical(
    followup_rows$agent_name,
    c("analyst", "reviewer", "analyst")
  )
  expect_true(is.na(followup_rows$parent_delegation_id[[3L]]))
  expect_identical(followup_rows$status, rep("completed", 3L))

  graph$root$release_agent_graph()
  expect_error(
    graph$root$continue_agent(
      graph$handles[["analyst"]],
      "This graph has been released.",
      UsageLimits(max_requests = 1L)
    ),
    class = "deputy_conversation"
  )
})

test_that("the recursive example exposes host controls and read-only child selection", {
  skip_if_not_installed("bslib")
  skip_if_not_installed("commonmark")
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat")
  skip_if_not_installed("xml2")
  skip_if(
    utils::packageVersion("shinychat") < "0.5.0",
    "shinychat >= 0.5.0 is required"
  )

  directory <- recursive_example_directory()
  example <- new.env(parent = globalenv())
  withr::with_dir(
    directory,
    sys.source("app.R", envir = example)
  )
  html <- as.character(example$ui)
  expect_match(html, "Run root")
  expect_match(html, 'id="cancel"')
  expect_match(html, 'id="followup"')
  expect_match(html, "children-choice")
  expect_match(html, "Selected child")
})
