study_recipe <- function() {
  environment <- new.env(parent = baseenv())
  sys.source(
    system.file(
      "examples",
      "trusted-mini-agent",
      "workflow.R",
      package = "deputy"
    ),
    environment
  )
  environment
}

study_test_workflow <- function(
  treatment = "trt2",
  failure = FALSE,
  bypass = FALSE,
  .local_envir = parent.frame()
) {
  recipe <- study_recipe()
  plan <- recipe$study_plan(treatment)
  proposer <- local_runtime_server(
    list(
      runtime_reply(
        tool = "delegate_to_agent",
        arguments = list(agent_name = "analyst", task = "Propose the study")
      ),
      runtime_reply(tool = "propose_analysis", arguments = list(plan = plan)),
      runtime_reply("Proposal drafted"),
      runtime_reply("FORGED RESULT: the difference is 999 grams")
    ),
    .local_envir = .local_envir
  )
  executor <- local_runtime_server(
    list(
      runtime_reply(tool = "compute_summary", arguments = list(plan = plan)),
      if (failure) {
        runtime_failure(403L)
      } else if (bypass) {
        runtime_reply(
          tool = "write_file",
          arguments = list(path = "result.json", content = "999 grams")
        )
      } else {
        runtime_reply("FORGED RESULT: the difference is 999 grams")
      },
      runtime_reply("FORGED RESULT: the difference is 999 grams")
    ),
    .local_envir = .local_envir
  )
  directory <- withr::local_tempdir(.local_envir = .local_envir)
  owner <- new.env(parent = emptyenv())
  workflow <- recipe$study_workflow(
    function(role) {
      runtime_chat(if (role == "executor") executor else proposer)
    },
    directory,
    owner
  )
  list(
    recipe = recipe,
    workflow = workflow,
    owner = owner,
    directory = directory,
    plan = plan,
    proposer = proposer,
    executor = executor
  )
}

test_that("trusted study computes only after review and keeps model prose separate", {
  x <- study_test_workflow()
  proposal <- x$workflow$propose(
    "Compare treated and control plant weights",
    x$owner
  )
  expect_identical(proposal$proposal, x$plan)
  expect_null(proposal$receipt)
  expect_match(proposal$proposal_context$delegation_id, "^delegation_")
  review <- x$workflow$prepare(x$owner)
  expect_identical(review$pending$status, "pending")
  expect_null(review$receipt)
  result <- x$workflow$decide(x$owner, "approve")
  expect_null(result$error)
  expect_equal(result$receipt$result$mean_control, 5)
  expect_equal(result$receipt$result$mean_treatment, 7)
  expect_equal(result$receipt$result$difference, 2)
  expect_identical(result$receipt$inputs, x$plan)
  expect_identical(result$receipt$approval$id, review$pending$id)
  expect_match(result$commentary$response, "999")
  expect_identical(file.exists(result$result_path), TRUE)
  before <- readLines(result$result_path)
  duplicate <- x$workflow$decide(x$owner, "approve")
  expect_type(duplicate$error, "character")
  expect_identical(readLines(result$result_path), before)
})

test_that("host edits are validated and bound to the executed receipt", {
  x <- study_test_workflow()
  x$workflow$propose("study", x$owner)
  x$workflow$prepare(x$owner)
  invalid <- x$plan
  invalid$units <- "kg"
  expect_snapshot(error = TRUE, x$workflow$decide(x$owner, "approve", invalid))
  expect_identical(x$workflow$view(x$owner)$pending$status, "pending")
  expect_null(x$workflow$view(x$owner)$receipt)
  edited <- x$plan
  edited$treatment <- "trt1"
  result <- x$workflow$decide(x$owner, "approve", edited)
  expect_null(result$error)
  expect_equal(result$receipt$result$difference, -1)
  expect_identical(result$receipt$inputs, edited)
  expect_identical(result$pending$decision$tool_input$plan, edited)
  expect_identical(result$receipt$approval$decision$tool_input$plan, edited)
  expect_identical(result$receipt$data$revision, edited$dataset_revision)
  expect_type(result$receipt$execution$run_id, "character")
  expect_type(result$receipt$execution$tool_call_id, "character")
})

test_that("denied computation and unauthorized callers produce no result", {
  x <- study_test_workflow()
  x$workflow$propose("study", x$owner)
  x$workflow$prepare(x$owner)
  stranger <- new.env(parent = emptyenv())
  expect_snapshot(error = TRUE, x$workflow$view(stranger))
  expect_snapshot(error = TRUE, x$workflow$decide(stranger, "approve"))
  denied <- x$workflow$decide(x$owner, "deny")
  expect_null(denied$receipt)
  expect_identical(file.exists(file.path(x$directory, "result.json")), FALSE)
  expect_identical(denied$pending$decision$decision, "deny")
  duplicate <- x$workflow$decide(x$owner, "approve")
  expect_type(duplicate$error, "character")
  expect_null(duplicate$receipt)
})

test_that("cancelled and unsupported proposals cannot reach computation", {
  x <- study_test_workflow()
  x$workflow$propose("study", x$owner)
  x$workflow$prepare(x$owner)
  x$workflow$cancel(x$owner)
  expect_snapshot(error = TRUE, x$workflow$decide(x$owner, "approve"))
  expect_null(x$workflow$view(x$owner)$receipt)
  expect_length(x$executor$requests(), 1L)

  invalid <- study_test_workflow(treatment = "unavailable")
  expect_snapshot(proposal <- invalid$workflow$propose("study", invalid$owner))
  expect_null(proposal$proposal)
  expect_snapshot(error = TRUE, invalid$workflow$prepare(invalid$owner))
  expect_length(invalid$executor$requests(), 0L)
})

test_that("missing data revisions and malformed raw inputs fail before execution", {
  recipe <- study_recipe()
  plan <- recipe$study_plan()
  changed <- recipe$study_data()
  changed$weight[[1L]] <- 0
  expect_snapshot(error = TRUE, recipe$study_validate(plan, changed))
  plan$outcome <- list("weight")
  expect_snapshot(error = TRUE, recipe$study_validate(plan))
  plan <- recipe$study_plan()
  plan$execute <- "write_file('forged')"
  expect_snapshot(error = TRUE, recipe$study_validate(plan))
})

test_that("a provider failure after execution preserves the authoritative receipt", {
  x <- study_test_workflow(failure = TRUE)
  x$workflow$propose("study", x$owner)
  x$workflow$prepare(x$owner)
  result <- x$workflow$decide(x$owner, "approve")
  expect_type(result$error, "character")
  expect_equal(result$receipt$result$difference, 2)
  expect_identical(result$pending$status, "stopped")
  expect_identical(result$pending$effects[[1L]]$status, "completed")
  expect_identical(file.exists(result$result_path), TRUE)
  tools <- x$executor$requests()[[1L]]$body$tools
  expect_identical(
    vapply(tools, function(tool) tool$`function`$name, character(1)),
    "compute_summary"
  )
})

test_that("the runnable fixture uses real public transport and tool-owned outputs", {
  recipe <- study_recipe()
  sys.source(
    system.file(
      "examples",
      "trusted-mini-agent",
      "fixture.R",
      package = "deputy"
    ),
    recipe
  )
  fixture <- recipe$study_fixture(recipe$study_plan())
  withr::defer(fixture$close())
  owner <- new.env(parent = emptyenv())
  workflow <- recipe$study_workflow(fixture$chat, withr::local_tempdir(), owner)
  workflow$propose("study", owner)
  workflow$prepare(owner)
  result <- workflow$decide(owner, "approve")
  expect_null(result$error)
  expect_equal(result$receipt$result$difference, 2)
  expect_identical(fixture$requests(), 6L)
  before <- fixture$requests()
  workflow$view(owner)
  workflow$lead$inspect_subagents(owner)
  expect_identical(fixture$requests(), before)
})

test_that("rejected repeat proposals cannot relabel accepted provenance", {
  recipe <- study_recipe()
  first <- runtime_reply(
    tool = "propose_analysis",
    arguments = list(plan = recipe$study_plan())
  )
  first$body <- gsub("call_fixture", "proposal_first", first$body, fixed = TRUE)
  repeated <- runtime_reply(
    tool = "propose_analysis",
    arguments = list(plan = recipe$study_plan("trt1"))
  )
  repeated$body <- gsub(
    "call_fixture",
    "proposal_rejected",
    repeated$body,
    fixed = TRUE
  )
  proposer <- local_runtime_server(list(
    runtime_reply(
      tool = "delegate_to_agent",
      arguments = list(agent_name = "analyst", task = "study")
    ),
    first,
    repeated,
    runtime_reply("done"),
    runtime_reply("done")
  ))
  executor <- local_runtime_server(list(
    runtime_reply(
      tool = "compute_summary",
      arguments = list(plan = recipe$study_plan())
    ),
    runtime_reply("done")
  ))
  owner <- new.env(parent = emptyenv())
  workflow <- recipe$study_workflow(
    function(role) {
      runtime_chat(if (role == "executor") executor else proposer)
    },
    withr::local_tempdir(),
    owner
  )
  expect_snapshot(proposed <- workflow$propose("study", owner))
  expect_identical(proposed$proposal_context$tool_call_id, "proposal_first")
  expect_identical(proposed$proposal, recipe$study_plan())
  workflow$prepare(owner)
  result <- workflow$decide(owner, "approve")
  expect_identical(result$receipt$proposal$tool_call_id, "proposal_first")
  expect_equal(result$receipt$result$difference, 2)
})


test_that("an alternate writer cannot replace the designated tool result", {
  x <- study_test_workflow(bypass = TRUE)
  x$workflow$propose("study", x$owner)
  x$workflow$prepare(x$owner)
  result <- x$workflow$decide(x$owner, "approve")
  expect_type(result$error, "character")
  expect_equal(result$receipt$result$difference, 2)
  saved <- jsonlite::read_json(result$result_path, simplifyVector = TRUE)
  expect_equal(saved$result$difference, 2)
  expect_identical(saved$tool$name, "compute_summary")
  expect_length(result$pending$effects, 1L)
})
