test_that("definition values preserve RDS identity and explicit YAML rebinding in a fresh process", {
  skip_if_not_installed("yaml")
  root <- withr::local_tempdir()
  rds_path <- file.path(root, "definition.rds")
  yaml_path <- file.path(root, "definition.yaml")
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
  skill <- Skill$new("concise", "Be concise", "Keep it short")
  tools <- list(count = counter)
  skills <- list(concise = skill)
  definition <- agent_definition(
    " Reviewer ",
    "Reviews text",
    "Read carefully",
    tools = unname(tools),
    skills = unname(skills),
    max_requests = 0,
    permission_mode = "readonly",
    disallowed_tools = "WRITE_FILE",
    memory = character()
  )
  agent_definition_write(definition, yaml_path, tools = tools, skills = skills)
  saveRDS(
    list(definition = definition, tools = tools, skills = skills),
    rds_path
  )
  restored <- callr::r(
    function(rds_path, yaml_path, package_path) {
      if (file.exists(file.path(package_path, "R", "agent.R"))) {
        pkgload::load_all(package_path, quiet = TRUE)
      } else {
        library(deputy, lib.loc = dirname(package_path))
      }
      values <- readRDS(rds_path)
      from_yaml <- agent_definition_read(
        yaml_path,
        tools = values$tools,
        skills = values$skills
      )
      replacement <- ellmer::tool(
        function() 42L,
        name = "replacement",
        description = "Host replacement"
      )
      rebound <- agent_definition_read(
        yaml_path,
        tools = list(count = replacement),
        skills = values$skills
      )
      frozen <- function(value, property, replacement) {
        tryCatch(
          {
            S7::prop(value, property) <- replacement
            FALSE
          },
          error = function(error) grepl("read-only", conditionMessage(error))
        )
      }
      list(
        alias = identical(agent_definition, AgentDefinition),
        rds_class = S7::S7_inherits(values$definition, AgentDefinition),
        yaml_class = S7::S7_inherits(from_yaml, AgentDefinition),
        name = from_yaml$name,
        limit = from_yaml$max_requests,
        permission_mode = from_yaml$permission_mode,
        denylist = from_yaml$disallowed_tools,
        memory = from_yaml$memory,
        initial_prompt = from_yaml$initial_prompt,
        rds_tool_identity = identical(
          values$definition$tools[[1L]],
          values$tools$count
        ),
        yaml_tool_identity = identical(
          from_yaml$tools[[1L]],
          values$tools$count
        ),
        skill_identity = identical(
          from_yaml$skills[[1L]],
          values$skills$concise
        ),
        first_count = values$definition$tools[[1L]](),
        second_count = from_yaml$tools[[1L]](),
        rebound_identity = identical(rebound$tools[[1L]], replacement),
        rebound_value = rebound$tools[[1L]](),
        rds_frozen = frozen(values$definition, "initial_prompt", "changed"),
        yaml_frozen = frozen(from_yaml, "name", "changed"),
        output = capture.output(print(values$definition))
      )
    },
    args = list(
      rds_path = rds_path,
      yaml_path = yaml_path,
      package_path = getNamespaceInfo(asNamespace("deputy"), "path")
    )
  )
  expect_identical(restored$alias, TRUE)
  expect_identical(restored$rds_class, TRUE)
  expect_identical(restored$yaml_class, TRUE)
  expect_identical(restored$name, "reviewer")
  expect_identical(restored$limit, 0L)
  expect_identical(restored$permission_mode, "readonly")
  expect_identical(restored$denylist, "write_file")
  expect_identical(restored$memory, character())
  expect_null(restored$initial_prompt)
  expect_identical(restored$rds_tool_identity, TRUE)
  expect_identical(restored$yaml_tool_identity, TRUE)
  expect_identical(restored$skill_identity, TRUE)
  expect_identical(restored$first_count, 1L)
  expect_identical(restored$second_count, 2L)
  expect_identical(restored$rebound_identity, TRUE)
  expect_identical(restored$rebound_value, 42L)
  expect_identical(restored$rds_frozen, TRUE)
  expect_identical(restored$yaml_frozen, TRUE)
  expect_match(
    paste(restored$output, collapse = "\n"),
    "<AgentDefinition: reviewer >",
    fixed = TRUE
  )
  expect_identical(state$count, 0L)
})
