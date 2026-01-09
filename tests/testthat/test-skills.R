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
