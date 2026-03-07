# Tests for .claude/agents loading.

test_that("claude_settings_load returns custom agents from .claude/agents", {
  withr::local_tempdir(pattern = "deputy-agents") -> temp_dir
  dir.create(file.path(temp_dir, ".claude", "agents"), recursive = TRUE)

  writeLines(
    c(
      "---",
      "name: reviewer",
      "description: Reviews code changes",
      "tools:",
      "  - Read",
      "  - Grep",
      "---",
      "You are a precise code reviewer."
    ),
    file.path(temp_dir, ".claude", "agents", "reviewer.md")
  )

  settings <- claude_settings_load("project", working_dir = temp_dir)

  expect_true("reviewer" %in% names(settings$agents))
  expect_s3_class(settings$agents$reviewer, "AgentDefinition")
  tool_names <- vapply(settings$agents$reviewer$tools, function(x) x@name, character(1))
  expect_setequal(tool_names, c("Read", "Grep"))
})

test_that("LeadAgent applies custom agents from setting_sources", {
  withr::local_tempdir(pattern = "deputy-agents") -> temp_dir
  dir.create(file.path(temp_dir, ".claude", "agents"), recursive = TRUE)

  writeLines(
    c(
      "---",
      "name: reviewer",
      "description: Reviews code changes",
      "tools:",
      "  - Read",
      "---",
      "You are a precise code reviewer."
    ),
    file.path(temp_dir, ".claude", "agents", "reviewer.md")
  )

  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(),
    setting_sources = "project",
    working_dir = temp_dir
  )

  expect_true("reviewer" %in% lead$available_sub_agents())
})
