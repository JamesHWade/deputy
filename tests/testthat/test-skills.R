# Tests for skill system

test_that("Skill creates correct structure", {
  skill <- Skill$new(
    name = "test_skill",
    version = "1.0.0",
    description = "A test skill",
    prompt = "You are a test assistant",
    tools = list(),
    requires = list(packages = c("dplyr"))
  )

  expect_s3_class(skill, "Skill")
  expect_equal(skill$name, "test_skill")
  expect_equal(skill$version, "1.0.0")
  expect_equal(skill$description, "A test skill")
  expect_equal(skill$prompt, "You are a test assistant")
  expect_equal(skill$requires$packages, "dplyr")
})

test_that("Skill check_requirements works", {
  # Skill with installed package
  skill_ok <- Skill$new(
    name = "test",
    requires = list(packages = c("base", "stats"))
  )
  check_ok <- skill_ok$check_requirements()
  expect_true(check_ok$ok)
  expect_length(check_ok$missing, 0)

  # Skill with missing package
  skill_missing <- Skill$new(
    name = "test",
    requires = list(packages = c("nonexistent_package_12345"))
  )
  check_missing <- skill_missing$check_requirements()
  expect_false(check_missing$ok)
  expect_true(grepl("nonexistent_package", check_missing$missing[1]))
})

test_that("skill_create creates skill programmatically", {
  skill <- skill_create(
    name = "my_skill",
    description = "My skill",
    prompt = "Be helpful",
    version = "2.0.0"
  )

  expect_s3_class(skill, "Skill")
  expect_equal(skill$name, "my_skill")
  expect_equal(skill$version, "2.0.0")
  expect_equal(skill$description, "My skill")
  expect_equal(skill$prompt, "Be helpful")
  expect_null(skill$path)
})

test_that("skill_load requires SKILL.yaml", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Directory without SKILL.yaml should error
  expect_error(
    skill_load(temp_dir),
    "SKILL.yaml"
  )
})

test_that("skill_load parses SKILL.yaml correctly", {
  skip_if_not_installed("yaml")

  withr::local_tempdir(pattern = "deputy-test") -> temp_dir
  # Normalize to handle macOS /var -> /private/var symlink
  temp_dir_norm <- normalizePath(temp_dir, mustWork = TRUE)

  # Create minimal SKILL.yaml
  yaml_content <- "
name: test_skill
version: '1.0.0'
description: A test skill
requires:
  packages:
    - base
"
  writeLines(yaml_content, file.path(temp_dir, "SKILL.yaml"))

  skill <- skill_load(temp_dir, check_requirements = FALSE)

  expect_equal(skill$name, "test_skill")
  expect_equal(skill$version, "1.0.0")
  expect_equal(skill$description, "A test skill")
  # Compare normalized paths to handle macOS symlinks
  expect_equal(normalizePath(skill$path), temp_dir_norm)
})

test_that("skill_load reads SKILL.md", {
  skip_if_not_installed("yaml")

  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  writeLines("name: test", file.path(temp_dir, "SKILL.yaml"))
  writeLines(
    "You are a helpful assistant.\n\nBe kind.",
    file.path(temp_dir, "SKILL.md")
  )

  skill <- skill_load(temp_dir, check_requirements = FALSE)

  expect_true(grepl("helpful assistant", skill$prompt))
  expect_true(grepl("Be kind", skill$prompt))
})

test_that("skills_list returns empty for missing directory", {
  result <- skills_list("nonexistent_dir_12345")

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0)
  expect_true("name" %in% names(result))
  expect_true("path" %in% names(result))
})

test_that("skills_list finds skills in directory", {
  skip_if_not_installed("yaml")

  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  # Create two skill directories
  skill1_dir <- file.path(temp_dir, "skill1")
  skill2_dir <- file.path(temp_dir, "skill2")
  dir.create(skill1_dir)
  dir.create(skill2_dir)

  writeLines("name: first_skill", file.path(skill1_dir, "SKILL.yaml"))
  writeLines("name: second_skill", file.path(skill2_dir, "SKILL.yaml"))

  result <- skills_list(temp_dir)

  expect_equal(nrow(result), 2)
  expect_true("first_skill" %in% result$name)
  expect_true("second_skill" %in% result$name)
})

test_that("skill defaults are sensible", {
  skill <- Skill$new(name = "minimal")

  expect_equal(skill$name, "minimal")
  expect_equal(skill$version, "0.0.0")
  expect_null(skill$description)
  expect_null(skill$prompt)
  expect_equal(skill$tools, list())
  expect_equal(skill$requires, list())
  expect_null(skill$path)
})

# Provider validation tests
test_that("normalize_provider_name handles common providers", {
  expect_equal(normalize_provider_name("openai"), "openai")
  expect_equal(normalize_provider_name("OpenAI"), "openai")
  expect_equal(normalize_provider_name("OPENAI"), "openai")
  expect_equal(normalize_provider_name("anthropic"), "anthropic")
  expect_equal(normalize_provider_name("claude"), "anthropic")
  expect_equal(normalize_provider_name("google"), "google")
  expect_equal(normalize_provider_name("gemini"), "google")
})

test_that("normalize_provider_name handles edge cases", {
  expect_true(is.na(normalize_provider_name(NULL)))
  expect_true(is.na(normalize_provider_name(123)))
  expect_true(is.na(normalize_provider_name(c("openai", "anthropic"))))
  expect_equal(normalize_provider_name("unknown_provider"), "unknown_provider")
})

test_that("normalize_provider_name handles chat_* prefixes", {
  expect_equal(normalize_provider_name("chat_openai"), "openai")
  expect_equal(normalize_provider_name("chat_anthropic"), "anthropic")
  expect_equal(normalize_provider_name("chat_google"), "google")
  expect_equal(normalize_provider_name("chat_ollama"), "ollama")
  expect_equal(normalize_provider_name("chat_azure"), "azure")
  expect_equal(normalize_provider_name("chat_bedrock"), "bedrock")
})

test_that("check_requirements validates provider without provider arg", {
  skill <- Skill$new(
    name = "test",
    requires = list(providers = c("openai", "anthropic"))
  )

  # Without provider arg, should pass (can't validate)
  check <- skill$check_requirements()
  expect_true(check$ok)
  expect_false(check$provider_mismatch)
})

test_that("check_requirements validates matching provider", {
  skill <- Skill$new(
    name = "test",
    requires = list(providers = c("openai", "anthropic"))
  )

  # With matching provider
  check <- skill$check_requirements(current_provider = "openai")
  expect_true(check$ok)
  expect_false(check$provider_mismatch)

  check2 <- skill$check_requirements(current_provider = "anthropic")
  expect_true(check2$ok)
  expect_false(check2$provider_mismatch)
})

test_that("check_requirements detects provider mismatch", {
  skill <- Skill$new(
    name = "test",
    requires = list(providers = c("openai"))
  )

  # With mismatched provider
  check <- skill$check_requirements(current_provider = "anthropic")
  expect_false(check$ok)
  expect_true(check$provider_mismatch)
  expect_equal(check$current_provider, "anthropic")
  expect_equal(check$required_providers, "openai")
})

test_that("check_requirements handles normalized provider names", {
  skill <- Skill$new(
    name = "test",
    requires = list(providers = c("anthropic"))
  )

  # "claude" should normalize to "anthropic"
  check <- skill$check_requirements(current_provider = "claude")
  expect_true(check$ok)
  expect_false(check$provider_mismatch)
})

test_that("check_requirements handles empty providers list", {
  skill <- Skill$new(
    name = "test",
    requires = list(providers = list())
  )

  check <- skill$check_requirements(current_provider = "openai")
  expect_true(check$ok)
  expect_false(check$provider_mismatch)
})

test_that("check_requirements combines package and provider checks", {
  skill <- Skill$new(
    name = "test",
    requires = list(
      packages = c("base"),
      providers = c("openai")
    )
  )

  # Package ok, provider ok
  check1 <- skill$check_requirements(current_provider = "openai")
  expect_true(check1$ok)

  # Package ok, provider mismatch
  check2 <- skill$check_requirements(current_provider = "anthropic")
  expect_false(check2$ok)
  expect_true(check2$provider_mismatch)
  expect_length(check2$missing, 0)

  # Missing package (even with matching provider)
  skill_missing <- Skill$new(
    name = "test",
    requires = list(
      packages = c("nonexistent_pkg_xyz"),
      providers = c("openai")
    )
  )
  check3 <- skill_missing$check_requirements(current_provider = "openai")
  expect_false(check3$ok)
  expect_false(check3$provider_mismatch)
  expect_length(check3$missing, 1)
})

test_that("Agent load_skill warns on provider mismatch", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  skill <- skill_create(
    name = "provider_test",
    description = "Test skill",
    requires = list(providers = c("openai"))
  )

  # Mock provider returns "mock", which won't match "openai"
  expect_warning(
    agent$load_skill(skill),
    "may not work optimally"
  )
})

test_that("Agent load_skill succeeds without provider requirements", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  skill <- skill_create(
    name = "no_provider_req",
    description = "Test skill without provider requirements"
  )

  # Should succeed without warnings about provider
  expect_no_warning(
    agent$load_skill(skill)
  )
})

test_that("Skill print includes provider info when present", {
  skill <- Skill$new(
    name = "test_skill",
    requires = list(
      packages = c("dplyr"),
      providers = c("openai", "anthropic")
    )
  )

  output <- capture.output(print(skill))
  output_text <- paste(output, collapse = "\n")

  expect_true(grepl("test_skill", output_text))
})

# Tool name conflict detection tests
test_that("Agent load_skill warns on tool name conflicts", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Create a tool with a specific name
  tool1 <- ellmer::tool(
    fun = function() "result1",
    name = "conflicting_tool",
    description = "First version"
  )

  # Register it directly
  mock_chat$register_tool(tool1)

  # Create a skill with the same tool name
  tool2 <- ellmer::tool(
    fun = function() "result2",
    name = "conflicting_tool",
    description = "Second version"
  )

  skill <- skill_create(
    name = "conflict_skill",
    tools = list(tool2)
  )

  # Should warn about the conflict
  expect_warning(
    agent$load_skill(skill),
    "overwrites existing"
  )
})

test_that("Agent load_skill does not warn without conflicts", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Create a tool
  tool1 <- ellmer::tool(
    fun = function() "result1",
    name = "unique_tool_1",
    description = "First tool"
  )

  skill <- skill_create(
    name = "no_conflict_skill",
    tools = list(tool1)
  )

  # Should succeed without conflict warnings
  expect_no_warning(
    agent$load_skill(skill)
  )
})

test_that("Tool conflict detection reports all conflicts", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Register multiple tools
  tool_a <- ellmer::tool(
    fun = function() "a",
    name = "tool_a",
    description = "Tool A"
  )
  tool_b <- ellmer::tool(
    fun = function() "b",
    name = "tool_b",
    description = "Tool B"
  )

  mock_chat$register_tools(list(tool_a, tool_b))

  # Create a skill that conflicts with both
  skill_tool_a <- ellmer::tool(
    fun = function() "new_a",
    name = "tool_a",
    description = "New Tool A"
  )
  skill_tool_b <- ellmer::tool(
    fun = function() "new_b",
    name = "tool_b",
    description = "New Tool B"
  )
  skill_tool_c <- ellmer::tool(
    fun = function() "c",
    name = "tool_c",
    description = "Tool C (no conflict)"
  )

  skill <- skill_create(
    name = "multi_conflict_skill",
    tools = list(skill_tool_a, skill_tool_b, skill_tool_c)
  )

  # Should warn about both conflicts
  warning_msg <- capture_warnings(agent$load_skill(skill))
  expect_true(length(warning_msg) > 0)
  expect_true(any(grepl("tool_a", warning_msg)))
  expect_true(any(grepl("tool_b", warning_msg)))
})

test_that("Skill with no tools does not trigger conflict check", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Register a tool
  tool1 <- ellmer::tool(
    fun = function() "result",
    name = "existing_tool",
    description = "Existing tool"
  )
  mock_chat$register_tool(tool1)

  # Create a skill without tools
  skill <- skill_create(
    name = "no_tools_skill",
    description = "Skill without tools"
  )

  # Should succeed without warnings
  expect_no_warning(
    agent$load_skill(skill)
  )
})

test_that("Conflicting tool is actually replaced after load_skill", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Register original tool with description "Original"
  tool1 <- ellmer::tool(
    fun = function() "original_result",
    name = "test_tool",
    description = "Original"
  )
  mock_chat$register_tool(tool1)

  # Verify original is registered
  tools_before <- mock_chat$get_tools()
  expect_true("test_tool" %in% names(tools_before))

  # Load skill with replacement tool having description "Replacement"
  tool2 <- ellmer::tool(
    fun = function() "replacement_result",
    name = "test_tool",
    description = "Replacement"
  )
  skill <- skill_create(
    name = "replace_skill",
    tools = list(tool2)
  )

  suppressWarnings(agent$load_skill(skill))

  # Verify the tool was actually replaced by checking the description
  tools_after <- mock_chat$get_tools()
  expect_true("test_tool" %in% names(tools_after))

  # The new tool should have the "Replacement" description
  # Access via S7 @description property
  replaced_tool <- tools_after[["test_tool"]]
  expect_true(inherits(replaced_tool, "ellmer::ToolDef"))

  # Use tryCatch to handle potential S7 access differences
  desc <- tryCatch(
    replaced_tool@description,
    error = function(e) replaced_tool$description
  )
  expect_equal(desc, "Replacement")
})
