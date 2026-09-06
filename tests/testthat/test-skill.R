test_that("Skill configuration is frozen and revised values retain defaults", {
  skill <- Skill(" Mixed Case ")
  expect_s7_class(skill, Skill)
  expect_identical(skill$name, " Mixed Case ")
  expect_identical(skill$version, "0.0.0")
  expect_identical(skill_create("short")$version, "1.0.0")
  expect_snapshot(error = TRUE, skill@name <- "changed")
  expect_snapshot(error = TRUE, skill@prompt <- "changed")
  expect_snapshot(error = TRUE, skill@path <- "elsewhere")
  expect_snapshot(error = TRUE, S7::props(skill) <- list(version = "2.0.0"))
  expect_snapshot(error = TRUE, skill$requires$providers <- "openai")

  fields <- S7::props(skill)
  fields$prompt <- "Use one sentence."
  fields$requires <- list(packages = list("base"), providers = character())
  revised <- do.call(Skill, fields)
  expect_identical(revised$prompt, "Use one sentence.")
  expect_identical(revised$requires, fields$requires)
  expect_null(skill$prompt)
  expect_identical(skill$requires, list())
  expect_identical(skill_check_requirements(revised, "deepseek")$ok, TRUE)
  metadata <- list(minimum = 2L, tags = list("local", "preview"))
  extended <- Skill("extension", requires = list(host = metadata))
  expect_identical(extended$requires$host, metadata)
  expect_identical(skill_check_requirements(extended)$ok, TRUE)
})

test_that("Skill validates declarative fields before use", {
  expect_snapshot(error = TRUE, Skill(""))
  expect_snapshot(error = TRUE, Skill("valid", version = NA_character_))
  expect_snapshot(error = TRUE, Skill("valid", description = c("one", "two")))
  expect_snapshot(error = TRUE, Skill("valid", prompt = function() "prompt"))
  expect_snapshot(error = TRUE, Skill("valid", tools = new.env()))
  expect_snapshot(error = TRUE, Skill("valid", requires = "base"))
  expect_snapshot(error = TRUE, Skill("valid", requires = list("base")))
  expect_snapshot(
    error = TRUE,
    Skill("valid", requires = list(packages = "base", packages = "stats"))
  )
  expect_snapshot(
    error = TRUE,
    Skill("valid", requires = list(providers = new.env()))
  )
  expect_snapshot(
    error = TRUE,
    Skill("valid", requires = list(providers = NA_character_))
  )
  expect_snapshot(
    error = TRUE,
    Skill("valid", requires = list(executable = function() NULL))
  )
  skill <- Skill("empty", description = "", prompt = "", path = "")
  expect_identical(skill$description, "")
  expect_identical(skill$prompt, "")
  expect_identical(skill$path, "")
})

test_that("Skill keeps executable state caller-owned across runtime consumers", {
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
  skill <- Skill("counter", prompt = "Count carefully.", tools = list(counter))
  expect_identical(skill$tools[[1L]], counter)
  expect_identical(state$count, 0L)
  expect_identical(skill_check_requirements(skill)$ok, TRUE)
  expect_identical(state$count, 0L)

  agent <- Agent$new(create_mock_chat())
  agent$load_skill(skill)
  loaded <- agent$skills()
  expect_identical(loaded$counter, skill)
  expect_snapshot(error = TRUE, loaded$counter@name <- "changed")
  expect_snapshot(error = TRUE, loaded$counter@prompt <- "changed")
  loaded$counter <- Skill("replacement")
  expect_identical(agent$skills()$counter$name, "counter")
  expect_identical(agent$skills()$counter$prompt, "Count carefully.")
  expect_identical(agent$skills()$counter$tools[[1L]](), 1L)
  expect_identical(counter(), 2L)
  expect_identical(state$count, 2L)

  cloned <- agent$clone()
  expect_identical(cloned$skills()$counter, skill)
  expect_identical(cloned$skills()$counter$tools[[1L]](), 3L)
  expect_identical(state$count, 3L)
})

test_that("Skill boundaries reject legacy lookalikes", {
  old <- structure(list(name = "legacy"), class = "Skill")
  expect_snapshot(error = TRUE, skill_check_requirements(old))
  agent <- Agent$new(create_mock_chat())
  expect_snapshot(error = TRUE, agent$load_skill(old))
  expect_snapshot(
    error = TRUE,
    validate_definition_registry(list(legacy = old), "skills")
  )
})

test_that("only exact reserved requirement names are evaluated", {
  skill <- Skill(
    "metadata",
    requires = list(
      packages_version = "nonexistent_package_12345",
      providers_note = "openai"
    )
  )
  expect_identical(
    skill_check_requirements(skill, "anthropic"),
    list(
      ok = TRUE,
      missing = character(),
      provider_mismatch = FALSE,
      current_provider = "anthropic",
      required_providers = NULL
    )
  )
  expect_null(skill_check_requirements(skill)$required_providers)
  agent <- Agent$new(create_mock_chat())
  expect_no_warning(agent$load_skill(skill))

  fields <- S7::props(skill)
  fields$requires$packages <- "base"
  fields$requires$providers <- "openai"
  declared <- do.call(Skill, fields)
  expect_identical(skill_check_requirements(declared, "OpenAI")$ok, TRUE)
  expect_identical(
    skill_check_requirements(declared, "anthropic")$provider_mismatch,
    TRUE
  )
})

test_that("Skill summaries tolerate unexpected tool entries without executing them", {
  withr::local_options(cli.width = 120, cli.num_colors = 1L)
  skill <- Skill(
    "mixed",
    tools = list(
      tool_read_file,
      function() stop("Do not execute while printing"),
      list(name = "unexpected"),
      NULL
    )
  )
  output <- capture.output(result <- withVisible(print(skill)))
  expect_match(paste(output, collapse = "\n"), "tools: 4", fixed = TRUE)
  expect_match(
    paste(output, collapse = "\n"),
    "read_file, <unnamed>, <unnamed>, <unnamed>",
    fixed = TRUE
  )
  expect_identical(result$visible, FALSE)
  expect_identical(result$value, skill)
})
