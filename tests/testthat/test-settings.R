# Tests for Claude-style settings loading

test_that("claude_settings_load loads memory, skills, and commands", {
  withr::local_tempdir(pattern = "deputy-settings") -> temp_dir

  # Project structure
  dir.create(file.path(temp_dir, ".claude", "skills"), recursive = TRUE)
  dir.create(file.path(temp_dir, ".claude", "commands"), recursive = TRUE)

  # Memory file
  writeLines("Project memory content", file.path(temp_dir, "CLAUDE.md"))

  # Skill (SKILL.md)
  skill_dir <- file.path(temp_dir, ".claude", "skills", "analysis")
  dir.create(skill_dir, recursive = TRUE)
  writeLines("You are a helpful analyst.", file.path(skill_dir, "SKILL.md"))

  # Command
  writeLines(
    "Summarize the latest changes.",
    file.path(temp_dir, ".claude", "commands", "summarize.md")
  )

  settings <- claude_settings_load("project", working_dir = temp_dir)

  expect_true(length(settings$memory) > 0)
  expect_true("analysis" %in% names(settings$skills))
  expect_true("summarize" %in% names(settings$commands))
})

test_that("Agent applies project setting_sources", {
  withr::local_tempdir(pattern = "deputy-settings") -> temp_dir

  dir.create(file.path(temp_dir, ".claude", "skills"), recursive = TRUE)
  dir.create(file.path(temp_dir, ".claude", "commands"), recursive = TRUE)

  writeLines("Memory block", file.path(temp_dir, "CLAUDE.md"))

  skill_dir <- file.path(temp_dir, ".claude", "skills", "analysis")
  dir.create(skill_dir, recursive = TRUE)
  writeLines("You are a helpful analyst.", file.path(skill_dir, "SKILL.md"))

  writeLines(
    "Summarize the latest changes.",
    file.path(temp_dir, ".claude", "commands", "summarize.md")
  )

  chat <- create_mock_chat()
  agent <- Agent$new(
    chat = chat,
    tools = list(),
    setting_sources = "project",
    working_dir = temp_dir
  )

  expect_true("analysis" %in% names(agent$skills()))
  expect_true("summarize" %in% names(agent$slash_commands()))
  expect_match(agent$chat$get_system_prompt(), "Memory block")
})

test_that("slash commands expand in run", {
  withr::local_tempdir(pattern = "deputy-settings") -> temp_dir
  dir.create(file.path(temp_dir, ".claude", "commands"), recursive = TRUE)
  writeLines(
    "Summarize changes.",
    file.path(temp_dir, ".claude", "commands", "summarize.md")
  )

  chat <- create_mock_chat(list("ok"))
  agent <- Agent$new(
    chat = chat,
    tools = list(),
    setting_sources = "project",
    working_dir = temp_dir
  )

  gen <- agent$run("/summarize recent work")
  event <- gen()
  expect_equal(event$type, "start")
  expect_match(event$task, "Slash command /summarize")
  expect_match(event$task, "recent work")
})
