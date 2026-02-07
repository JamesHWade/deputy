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

test_that("extract_tool_policy_settings parses aliases and list/csv values", {
  policy <- extract_tool_policy_settings(list(
    tools = list(allow = "read_file, run_bash"),
    disallowedTools = list("write_file"),
    permissions = list(permissionPromptTool = "AskUserQuestion")
  ))

  expect_true(policy$allowlist_present)
  expect_setequal(policy$allowlist, c("read_file", "run_bash"))
  expect_true(policy$denylist_present)
  expect_equal(policy$denylist, "write_file")
  expect_true(policy$prompt_tool_present)
  expect_equal(policy$permission_prompt_tool_name, "AskUserQuestion")
})

test_that("extract_tool_policy_settings handles empty prompt tool values", {
  policy <- extract_tool_policy_settings(list(
    permissionPromptToolName = character()
  ))

  expect_true(policy$prompt_tool_present)
  expect_null(policy$permission_prompt_tool_name)
})

test_that("claude_settings_apply injects tool policy into permissions", {
  chat <- create_mock_chat()
  initial_perms <- Permissions$new(
    mode = "default",
    file_read = TRUE,
    file_write = TRUE,
    bash = TRUE,
    r_code = TRUE,
    web = FALSE,
    install_packages = FALSE,
    tool_denylist = "install_package"
  )

  agent <- Agent$new(
    chat = chat,
    tools = list(),
    permissions = initial_perms
  )

  settings <- list(
    settings = list(
      allowedTools = c("read_file", "run_bash"),
      permissionPromptToolName = "AskUserQuestion"
    ),
    memory = character(),
    skills = list(),
    commands = list()
  )

  claude_settings_apply(agent, settings)

  expect_setequal(agent$permissions$tool_allowlist, c("read_file", "run_bash"))
  expect_equal(agent$permissions$tool_denylist, "install_package")
  expect_equal(agent$permissions$permission_prompt_tool_name, "AskUserQuestion")
  expect_true(agent$permissions$bash)
})
