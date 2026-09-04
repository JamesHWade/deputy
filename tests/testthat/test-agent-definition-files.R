write_definition_fixture <- function(
  lines,
  dir = withr::local_tempdir(.local_envir = parent.frame()),
  name = "agent.yaml"
) {
  path <- file.path(dir, name)
  writeLines(lines, path)
  path
}

minimal_definition_yaml <- c(
  "version: 1",
  "name: reviewer",
  "description: Reviews text",
  "prompt: Read carefully"
)

test_that("every AgentDefinition field round-trips through YAML", {
  skip_if_not_installed("yaml")
  tool_registry <- list(read = tool_read_file, list = tool_list_files)
  skill <- Skill$new(
    name = "concise",
    description = "Be concise",
    prompt = "Keep it short"
  )
  skill_registry <- list(concise = skill, local = "/host/approved/skill")
  definition <- agent_definition(
    "Reviewer",
    "Reviews text",
    "Read carefully.\nReport gaps.",
    tools = unname(tool_registry),
    model = "inherit",
    skills = unname(skill_registry),
    disallowed_tools = c("run_bash", "write_file"),
    memory = c("fact one", "fact two"),
    mcp_servers = "local",
    initial_prompt = "Begin here",
    max_requests = 3,
    permission_mode = "readonly"
  )
  path <- tempfile(fileext = ".yaml")
  withr::defer(unlink(path))
  agent_definition_write(
    definition,
    path,
    tools = tool_registry,
    skills = skill_registry
  )
  restored <- agent_definition_read(
    path,
    tools = tool_registry,
    skills = skill_registry
  )
  expect_identical(restored, definition)
  expect_identical(restored$tools[[1]]@annotations, tool_read_file@annotations)
  expect_identical(restored$skills[[1]], skill)
})

test_that("omitted fields, nulls and empty sequences retain constructor defaults", {
  skip_if_not_installed("yaml")
  path <- write_definition_fixture(minimal_definition_yaml)
  expected <- agent_definition("reviewer", "Reviews text", "Read carefully")
  expect_identical(agent_definition_read(path), expected)
  agent_definition_write(expected, path, overwrite = TRUE)
  expect_identical(agent_definition_read(path), expected)
  expected$memory <- character()
  expected$disallowed_tools <- character()
  expected$mcp_servers <- character()
  expected$max_requests <- 0L
  agent_definition_write(expected, path, overwrite = TRUE)
  expect_identical(agent_definition_read(path), expected)
})

test_that("discovery is deterministic and rejects duplicate canonical names", {
  skip_if_not_installed("yaml")
  root <- withr::local_tempdir()
  expect_identical(agent_definitions(file.path(root, "missing")), list())
  expect_identical(agent_definitions(root), list())
  write_definition_fixture(minimal_definition_yaml, root, "z.yaml")
  write_definition_fixture(
    sub("reviewer", "writer", minimal_definition_yaml),
    root,
    "a.yml"
  )
  writeLines("ignored", file.path(root, "notes.md"))
  dir.create(file.path(root, "nested"))
  writeLines("not YAML", file.path(root, "nested", "hidden.yaml"))
  expect_named(agent_definitions(root), c("writer", "reviewer"))
  write_definition_fixture(
    sub("reviewer", "REVIEWER", minimal_definition_yaml),
    root,
    "duplicate.yaml"
  )
  expect_snapshot(
    error = TRUE,
    agent_definitions(root),
    transform = function(x) gsub(root, "<dir>", x, fixed = TRUE)
  )
})

test_that("files reject ambiguous or executable input without side effects", {
  skip_if_not_installed("yaml")
  root <- withr::local_tempdir()
  invalid <- list(
    c(minimal_definition_yaml, "unexpected: true"),
    sub("version: 1", "version: 2", minimal_definition_yaml),
    minimal_definition_yaml[-1],
    c(minimal_definition_yaml, "name: duplicate"),
    c(minimal_definition_yaml, "tools: [unregistered]"),
    c(minimal_definition_yaml, "tools: [read, read]"),
    c(minimal_definition_yaml, "tools: null"),
    c(minimal_definition_yaml, "skills: [/unapproved/path]"),
    c(minimal_definition_yaml, "memory: [true]"),
    c(minimal_definition_yaml, "permission_mode: invalid"),
    c(minimal_definition_yaml, "max_requests: -1"),
    c(minimal_definition_yaml, "sub_agents: []"),
    c("- not", "- a mapping"),
    sub(
      "prompt: Read carefully",
      "prompt: !expr writeLines('executed', 'marker')",
      minimal_definition_yaml
    )
  )
  withr::local_dir(root)
  for (lines in invalid) {
    path <- write_definition_fixture(lines, root)
    error <- tryCatch(
      agent_definition_read(path, tools = list(read = tool_read_file)),
      error = identity
    )
    expect_s3_class(error, "deputy_agent_definition_file")
  }
  expect_false(file.exists("marker"))
})

test_that("writing requires explicit unambiguous registries and protects existing files", {
  skip_if_not_installed("yaml")
  path <- write_definition_fixture("original")
  definition <- agent_definition(
    "reviewer",
    "Reviews text",
    "Read carefully",
    tools = list(tool_read_file)
  )
  expect_snapshot(
    error = TRUE,
    agent_definition_write(definition, path),
    transform = function(x) gsub(path, "<file>", x, fixed = TRUE)
  )
  expect_snapshot(
    error = TRUE,
    agent_definition_write(
      definition,
      path,
      tools = list(read = tool_read_file)
    ),
    transform = function(x) gsub(path, "<file>", x, fixed = TRUE)
  )
  expect_identical(readLines(path), "original")
  error <- tryCatch(
    agent_definition_write(
      definition,
      path,
      overwrite = TRUE,
      tools = list(read = tool_read_file, alias = tool_read_file)
    ),
    error = identity
  )
  expect_s3_class(error, "deputy_agent_definition_file")
  expect_identical(readLines(path), "original")
})

test_that("a loaded definition delegates with its tools, limits and permissions", {
  skip_if_not_installed("yaml")
  registry <- list(read = tool_read_file)
  root <- withr::local_tempdir()
  path <- write_definition_fixture(
    c(
      minimal_definition_yaml,
      "tools: [read]",
      "permission_mode: readonly",
      "max_requests: 2"
    ),
    root
  )
  definition <- agent_definition_read(path, tools = registry)
  lead <- LeadAgent$new(
    chat = create_mock_chat("Reviewed"),
    sub_agents = list(definition),
    permissions = Permissions$new(mode = "standard", file_write = FALSE),
    usage_limits = UsageLimits(max_requests = 5)
  )
  result <- resolve_async_value(lead$get_tools()[["delegate_to_agent"]](
    "reviewer",
    "Review text"
  ))
  expect_identical(lead$list_subagents()$status, "completed")
  expect_identical(lead$sub_agent_defs[[1]]$max_requests, 2L)
  expect_identical(lead$sub_agent_defs[[1]]$permission_mode, "readonly")
  expect_identical(lead$sub_agent_defs[[1]]$tools[[1]]@name, "read_file")
})

test_that("default discovery reads only the Deputy project directory", {
  skip_if_not_installed("yaml")
  project <- withr::local_tempdir()
  withr::local_dir(project)
  dir.create(file.path(".deputy", "agents"), recursive = TRUE)
  dir.create(file.path(".claude", "agents"), recursive = TRUE)
  write_definition_fixture(
    minimal_definition_yaml,
    file.path(".deputy", "agents")
  )
  write_definition_fixture(
    sub("reviewer", "foreign", minimal_definition_yaml),
    file.path(".claude", "agents")
  )
  expect_named(agent_definitions(), "reviewer")
})

test_that("file and registry validation fail before reading or writing content", {
  skip_if_not_installed("yaml")
  root <- withr::local_tempdir()
  path <- write_definition_fixture(minimal_definition_yaml, root)
  for (registry in list(
    list(tool_read_file),
    setNames(list(tool_read_file, tool_list_files), c("same", "same")),
    list(read = function() rlang::abort("Must not run")),
    setNames(list(tool_read_file), "package::read")
  )) {
    error <- tryCatch(
      agent_definition_read(path, tools = registry),
      error = identity
    )
    expect_s3_class(error, "deputy_agent_definition_file")
  }
  for (bad_path in list(
    root,
    file.path(root, "missing"),
    NA_character_,
    character()
  )) {
    error <- tryCatch(agent_definition_read(bad_path), error = identity)
    expect_s3_class(error, "deputy_agent_definition_file")
  }
  oversized <- file.path(root, "large.yaml")
  writeLines(strrep("x", 1024^2 + 1L), oversized)
  error <- tryCatch(agent_definition_read(oversized), error = identity)
  expect_s3_class(error, "deputy_agent_definition_file")
  expect_match(conditionMessage(error), "1 MiB", fixed = TRUE)
})

test_that("a definition file cannot widen its lead's permission ceiling", {
  skip_if_not_installed("yaml")
  path <- write_definition_fixture(c(
    minimal_definition_yaml,
    "permission_mode: full"
  ))
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(agent_definition_read(path)),
    permissions = permissions_readonly()
  )
  expect_snapshot(
    error = TRUE,
    lead$get_tools()[["delegate_to_agent"]]("reviewer", "Review text")
  )
})

test_that("the shipped definition is portable and preserves prompt text", {
  skip_if_not_installed("yaml")
  registry <- list(read_file = tool_read_file)
  directory <- system.file("examples", "agent-definitions", package = "deputy")
  definitions <- agent_definitions(directory, tools = registry)
  expect_named(definitions, "reviewer")
  expect_match(
    definitions$reviewer$prompt,
    "Report unsupported claims",
    fixed = TRUE
  )
  path <- tempfile(fileext = ".yaml")
  withr::defer(unlink(path))
  agent_definition_write(definitions$reviewer, path, tools = registry)
  expect_identical(
    agent_definition_read(path, tools = registry),
    definitions$reviewer
  )
})
