test_that("Skill serialization preserves values and explicit host rebinding", {
  skip_if_not_installed("yaml")
  root <- withr::local_tempdir()
  rds_path <- file.path(root, "skill.rds")
  yaml_path <- file.path(root, "helper.yaml")
  state <- new.env(parent = emptyenv())
  state$count <- 0L
  counter <- ellmer::tool(
    function() {
      state$count <- state$count + 1L
      state$count
    },
    name = "counter",
    description = "Count calls"
  )
  skill <- Skill(
    "Counter Skill",
    version = "2.1.0",
    description = "Counts invocations",
    tools = list(counter),
    requires = list(packages = "base", providers = "anthropic"),
    path = "not-loaded-by-construction"
  )
  definition <- agent_definition(
    "helper",
    "Helps",
    "Help",
    skills = list(skill)
  )
  agent_definition_write(
    definition,
    yaml_path,
    skills = list(counter_skill = skill)
  )
  saveRDS(list(skill = skill, tool = counter), rds_path)

  restored <- callr::r(
    function(rds_path, yaml_path, package_path) {
      if (file.exists(file.path(package_path, "R", "agent.R"))) {
        pkgload::load_all(package_path, quiet = TRUE)
      } else {
        library(deputy, lib.loc = dirname(package_path))
      }
      values <- readRDS(rds_path)
      skill <- values$skill
      from_yaml <- agent_definition_read(
        yaml_path,
        skills = list(counter_skill = skill)
      )
      replacement_tool <- ellmer::tool(
        function() 42L,
        name = "replacement",
        description = "Host replacement"
      )
      replacement <- Skill("replacement", tools = list(replacement_tool))
      rebound <- agent_definition_read(
        yaml_path,
        skills = list(counter_skill = replacement)
      )
      frozen <- tryCatch(
        {
          skill@prompt <- "changed"
          FALSE
        },
        error = function(error) grepl("read-only", conditionMessage(error))
      )
      list(
        class = S7::S7_inherits(skill, Skill),
        name = skill$name,
        version = skill$version,
        description = skill$description,
        prompt = skill$prompt,
        path = skill$path,
        requires = skill$requires,
        matching = skill_check_requirements(skill, "claude")$ok,
        mismatch = skill_check_requirements(skill, "openai")$provider_mismatch,
        frozen = frozen,
        tool_identity = identical(skill$tools[[1L]], values$tool),
        yaml_identity = identical(from_yaml$skills[[1L]], skill),
        first_count = skill$tools[[1L]](),
        second_count = values$tool(),
        rebound_identity = identical(rebound$skills[[1L]], replacement),
        rebound_value = rebound$skills[[1L]]$tools[[1L]](),
        printed = capture.output(print(skill))
      )
    },
    args = list(
      rds_path = rds_path,
      yaml_path = yaml_path,
      package_path = getNamespaceInfo(asNamespace("deputy"), "path")
    )
  )
  expect_identical(restored$class, TRUE)
  expect_identical(restored$name, "Counter Skill")
  expect_identical(restored$version, "2.1.0")
  expect_identical(restored$description, "Counts invocations")
  expect_null(restored$prompt)
  expect_identical(restored$path, "not-loaded-by-construction")
  expect_identical(restored$requires, skill$requires)
  expect_identical(restored$matching, TRUE)
  expect_identical(restored$mismatch, TRUE)
  expect_identical(restored$frozen, TRUE)
  expect_identical(restored$tool_identity, TRUE)
  expect_identical(restored$yaml_identity, TRUE)
  expect_identical(restored$first_count, 1L)
  expect_identical(restored$second_count, 2L)
  expect_identical(restored$rebound_identity, TRUE)
  expect_identical(restored$rebound_value, 42L)
  expect_match(
    paste(restored$printed, collapse = "\n"),
    "<Skill: Counter Skill >",
    fixed = TRUE
  )
  expect_identical(state$count, 0L)
})
