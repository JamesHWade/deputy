load_approval_recipes <- function() {
  env <- new.env(parent = globalenv())
  sys.source(
    system.file("examples", "approval-gates.R", package = "deputy"),
    env
  )
  env
}

test_that("approval recipe fails closed through Agent hooks", {
  recipes <- load_approval_recipes()
  for (answer in list("Approve", "Deny", NULL, "approve")) {
    seen <- NULL
    handler <- function(questions, context) {
      seen <<- list(questions = questions, context = context)
      setNames(list(answer), questions[[1]]$question)
    }
    mock <- create_shiny_tool_chat("write_file", list(path = "report.txt"))
    agent <- Agent$new(
      chat = mock$chat,
      tools = list(tool_write_file),
      permissions = permissions_full()
    )
    agent$add_hook(recipes$approval_gate(handler))
    agent$run_sync("Write a report")
    expect_identical(mock$state$executed, identical(answer, "Approve"))
    expect_match(seen$questions[[1]]$question, "report.txt", fixed = TRUE)
    expect_type(seen$context$run_id, "character")
  }
})

test_that("stateful recipe isolates runs and clears completed state", {
  recipes <- load_approval_recipes()
  asks <- 0L
  hooks <- recipes$approval_after_install(function(questions, context) {
    asks <<- asks + 1L
    setNames(list("Deny"), questions[[1]]$question)
  })
  run <- list(run_id = "one")
  other <- list(run_id = "two")
  before_push <- function(context) {
    hooks[[2]]$callback("push_changes", list(), context)
  }
  expect_identical(before_push(run)$permission, "allow")
  hooks[[1]]$callback(
    "install_dependency",
    list(installed = TRUE),
    "failed",
    run
  )
  expect_identical(before_push(run)$permission, "allow")
  hooks[[1]]$callback("install_dependency", list(installed = FALSE), NULL, run)
  expect_identical(before_push(run)$permission, "allow")
  hooks[[1]]$callback("install_dependency", list(installed = TRUE), NULL, run)
  expect_identical(before_push(run)$permission, "deny")
  expect_identical(before_push(other)$permission, "allow")
  expect_identical(asks, 1L)
  hooks[[3]]$callback("end_turn", run)
  expect_identical(before_push(run)$permission, "allow")
})
