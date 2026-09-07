test_that("object summaries print user braces literally and return invisibly", {
  literal <- "{stop('must stay text')}"
  objects <- list(
    AgentEvent("text", text = literal),
    AgentResult(response = literal),
    Permissions(tool_allowlist = literal),
    HookMatcher("Stop", function(reason, context) NULL, pattern = "a{1}"),
    Skill(name = literal, prompt = literal),
    agent_definition("print_probe", description = literal, prompt = "test"),
    Agent$new(chat = create_mock_chat(), agent_name = literal)
  )
  expected <- c(rep(literal, 3), "a{1}", rep(literal, 3))
  withr::local_options(cli.width = 120, cli.num_colors = 1L)
  for (i in seq_along(objects)) {
    output <- capture.output(result <- withVisible(print(objects[[i]])))
    expect_match(paste(output, collapse = "\n"), expected[[i]], fixed = TRUE)
    expect_identical(result$visible, FALSE)
    expect_identical(result$value, objects[[i]])
  }
})

test_that("Permissions summaries distinguish absent and empty tool gates", {
  withr::local_options(cli.width = 120, cli.num_colors = 1L)
  unrestricted <- Permissions(tool_allowlist = NULL, tool_denylist = NULL)
  empty <- Permissions(
    tool_allowlist = character(),
    tool_denylist = character()
  )
  for (gate in c("tool_allowlist", "tool_denylist")) {
    expect_match(
      paste(capture.output(print(unrestricted)), collapse = "\n"),
      paste0(gate, ": NULL"),
      fixed = TRUE
    )
    expect_match(
      paste(capture.output(print(empty)), collapse = "\n"),
      paste0(gate, ": character(0)"),
      fixed = TRUE
    )
  }
  expect_identical(
    permissions_check(
      unrestricted,
      "read_file",
      list(path = "test.txt")
    )$decision,
    "allow"
  )
  expect_identical(
    permissions_check(empty, "read_file", list(path = "test.txt"))$decision,
    "deny"
  )
})

test_that("cli summaries wrap at the configured width and close their containers", {
  withr::local_options(cli.width = 36, cli.num_colors = 1L)
  result <- AgentResult(response = paste(rep("word", 10), collapse = " "))
  output <- cli::cli_format_method({
    print(result)
    cli::cli_text("after")
  })
  expect_lte(max(nchar(output, type = "width")), 36L)
  expect_identical(tail(output, 1), "after")
})


test_that("other summaries keep stdout and invisible return contracts", {
  registry <- HookRegistry$new()
  objects <- list(
    UsageLimits(),
    AgentUsage(),
    ContextPolicy(),
    registry,
    DeputyCompaction("llm", FALSE, 1L, 1L, 10),
    LeadAgent$new(chat = create_mock_chat())
  )
  for (object in objects) {
    output <- capture.output(result <- withVisible(print(object)))
    expect_gt(length(output), 0L)
    expect_identical(result$visible, FALSE)
    expect_identical(result$value, object)
    if (inherits(object, "LeadAgent")) {
      expect_match(paste(output, collapse = "\n"), "\n  sub_agents: 0")
    }
  }
})
