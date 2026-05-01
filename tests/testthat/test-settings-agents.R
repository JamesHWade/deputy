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
  tool_names <- vapply(
    settings$agents$reviewer$tools,
    function(x) x@name,
    character(1)
  )
  expect_setequal(tool_names, c("Read", "Grep"))
})

test_that("custom agent files load supported fields including model and skills", {
  withr::local_tempdir(pattern = "deputy-agents") -> temp_dir
  dir.create(file.path(temp_dir, ".claude", "agents"), recursive = TRUE)
  dir.create(
    file.path(temp_dir, ".claude", "skills", "analysis"),
    recursive = TRUE
  )
  writeLines(
    "You are a helpful analyst.",
    file.path(temp_dir, ".claude", "skills", "analysis", "SKILL.md")
  )

  writeLines(
    c(
      "---",
      "name: reviewer",
      "description: Reviews code changes",
      "model: anthropic/claude-sonnet-4-5-20250929",
      "tools:",
      "  - Read",
      "skills:",
      "  - analysis",
      "---",
      "You are a precise code reviewer."
    ),
    file.path(temp_dir, ".claude", "agents", "reviewer.md")
  )

  settings <- claude_settings_load("project", working_dir = temp_dir)
  definition <- settings$agents$reviewer

  expect_s3_class(definition, "AgentDefinition")
  expect_equal(definition$model, "anthropic/claude-sonnet-4-5-20250929")
  expect_match(definition$prompt, "precise code reviewer")
  expect_equal(length(definition$skills), 1)
  expect_equal(definition$skills[[1]]$name, "analysis")
})

test_that("custom agent files load newer SDK metadata fields", {
  withr::local_tempdir(pattern = "deputy-agents") -> temp_dir
  dir.create(file.path(temp_dir, ".claude", "agents"), recursive = TRUE)

  writeLines(
    c(
      "---",
      "name: reviewer",
      "description: Reviews code changes",
      "permissionMode: plan",
      "disallowedTools:",
      "  - Write",
      "mcpServers:",
      "  - github",
      "initialPrompt: Start with risks.",
      "maxTurns: 2",
      "effort: medium",
      "tools:",
      "  - Read",
      "---",
      "You are a precise code reviewer."
    ),
    file.path(temp_dir, ".claude", "agents", "reviewer.md")
  )

  settings <- claude_settings_load("project", working_dir = temp_dir)

  expect_true("reviewer" %in% names(settings$agents))
  definition <- settings$agents$reviewer
  expect_equal(definition$description, "Reviews code changes")
  expect_equal(definition$permission_mode, "plan")
  expect_equal(definition$disallowed_tools, "Write")
  expect_equal(definition$mcp_servers, "github")
  expect_equal(definition$initial_prompt, "Start with risks.")
  expect_equal(definition$max_turns, 2L)
  expect_equal(definition$effort, "medium")
})

test_that("invalid custom agent files warn without blocking valid ones", {
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
  writeLines(
    c(
      "---",
      "name: broken",
      "description: Broken agent",
      "tools:",
      "  - UnknownTool",
      "---",
      "This agent should fail to load."
    ),
    file.path(temp_dir, ".claude", "agents", "broken.md")
  )

  expect_warning(
    settings <- claude_settings_load("project", working_dir = temp_dir),
    "Failed to load custom agent"
  )

  expect_true("reviewer" %in% names(settings$agents))
  expect_false("broken" %in% names(settings$agents))
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
