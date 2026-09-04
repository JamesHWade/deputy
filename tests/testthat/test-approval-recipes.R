load_approval_recipes <- function() {
  env <- new.env(parent = as.environment("package:deputy"))
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
  expect_null(before_push(run))
  hooks[[1]]$callback(
    "install_dependency",
    list(installed = TRUE),
    "failed",
    run
  )
  expect_null(before_push(run))
  hooks[[1]]$callback("install_dependency", list(installed = FALSE), NULL, run)
  expect_null(before_push(run))
  hooks[[1]]$callback("install_dependency", list(installed = TRUE), NULL, run)
  expect_identical(before_push(run)$permission, "deny")
  expect_null(before_push(other))
  expect_identical(asks, 1L)
  hooks[[3]]$callback("end_turn", run)
  expect_null(before_push(run))
})


test_that("approval hooks preserve later denials and audit hooks", {
  recipes <- load_approval_recipes()
  for (armed in c(FALSE, TRUE)) {
    agent <- Agent$new(chat = create_mock_chat())
    hooks <- recipes$approval_after_install(function(questions, context) {
      setNames(list("Approve"), questions[[1]]$question)
    })
    for (hook in hooks) {
      agent$add_hook(hook)
    }
    audited <- 0L
    agent$add_hook(HookMatcher$new(
      event = "PostToolUse",
      callback = function(tool_name, tool_result, tool_error, context) {
        audited <<- audited + 1L
        NULL
      }
    ))
    agent$add_hook(HookMatcher$new(
      event = "PreToolUse",
      callback = function(tool_name, tool_input, context) {
        HookResultPreToolUse(permission = "deny", reason = "Later policy")
      }
    ))
    run <- list(run_id = "compose")
    for (receipt in list("installed", NULL, list(installed = armed))) {
      agent$hooks$fire(
        "PostToolUse",
        tool_name = "install_dependency",
        tool_result = receipt,
        tool_error = NULL,
        context = run
      )
    }
    expect_identical(audited, 3L)
    expect_length(agent$hooks$last_errors(), 0L)
    decision <- agent$hooks$fire(
      "PreToolUse",
      tool_name = "push_changes",
      tool_input = list(),
      context = run
    )
    expect_identical(decision$reason, "Later policy")
  }
})
