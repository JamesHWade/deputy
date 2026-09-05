test_that("agent_definition creates correct structure", {
  def <- agent_definition(
    name = "test_agent",
    description = "A test agent",
    prompt = "You are a test assistant"
  )

  expect_s3_class(def, "AgentDefinition")
  expect_equal(def$name, "test_agent")
  expect_equal(def$description, "A test agent")
  expect_equal(def$prompt, "You are a test assistant")
  expect_equal(def$tools, list())
  expect_equal(def$model, "inherit")
  expect_equal(def$skills, list())
  expect_null(def$max_requests)
  expect_named(
    def,
    c(
      "name",
      "description",
      "prompt",
      "tools",
      "model",
      "skills",
      "disallowed_tools",
      "memory",
      "mcp_servers",
      "initial_prompt",
      "max_requests",
      "permission_mode"
    )
  )
})

test_that("agent_definition accepts tools", {
  def <- agent_definition(
    name = "with_tools",
    description = "Agent with tools",
    prompt = "Test prompt",
    tools = tools_file()
  )

  expect_true(length(def$tools) >= 3)
})

test_that("agent_definition accepts custom model", {
  def <- agent_definition(
    name = "custom_model",
    description = "Uses custom model",
    prompt = "Test prompt",
    model = "anthropic/claude-sonnet-4-20250514"
  )

  expect_equal(def$model, "anthropic/claude-sonnet-4-20250514")
})

test_that("agent_definition canonicalizes routing keys", {
  def <- agent_definition(
    name = "  Review-Agent_1  ",
    description = "Reviews code",
    prompt = "Review the code"
  )

  expect_identical(def$name, "review-agent_1")
})

test_that("agent_definition validates scalar and collection fields", {
  base <- list(
    name = "reviewer",
    description = "Reviews code",
    prompt = "Review the code"
  )
  invalid <- list(
    list(args = list(name = "two words"), field = "name"),
    list(args = list(name = "1reviewer"), field = "name"),
    list(args = list(description = ""), field = "description"),
    list(args = list(prompt = NA_character_), field = "prompt"),
    list(args = list(model = character()), field = "model"),
    list(args = list(tools = tool_read_file), field = "tools"),
    list(args = list(skills = "review"), field = "skills"),
    list(
      args = list(disallowed_tools = list("run_bash")),
      field = "disallowed_tools"
    ),
    list(args = list(memory = list("memory")), field = "memory"),
    list(
      args = list(mcp_servers = c("github", NA_character_)),
      field = "mcp_servers"
    ),
    list(
      args = list(initial_prompt = c("one", "two")),
      field = "initial_prompt"
    )
  )

  for (case in invalid) {
    condition <- rlang::catch_cnd(
      do.call(agent_definition, utils::modifyList(base, case$args))
    )
    expect_s3_class(condition, "error")
    expect_match(conditionMessage(condition), case$field, fixed = TRUE)
  }
})

test_that("agent_definition print works", {
  def <- agent_definition(
    name = "print_test",
    description = "Testing print output",
    prompt = "Test prompt"
  )

  output <- capture.output(print(def))

  expect_true(any(grepl("AgentDefinition", output)))
  expect_true(any(grepl("print_test", output)))
})

# Tests for LeadAgent

test_that("agent_definition accepts only canonical permission modes", {
  for (mode in PermissionMode) {
    definition <- agent_definition(
      name = paste0("agent-", mode),
      description = "Uses a canonical mode",
      prompt = "You help",
      permission_mode = mode
    )
    expect_identical(definition$permission_mode, mode)
  }

  expect_error(
    agent_definition(
      name = "sdk-alias",
      description = "Uses a removed alias",
      prompt = "You help",
      permission_mode = "auto"
    ),
    "Invalid permission mode"
  )

  readonly_definition <- agent_definition(
    name = "full-to-readonly",
    description = "Tightens a full-access lead",
    prompt = "You help",
    permission_mode = "readonly"
  )
  full_lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(readonly_definition),
    permissions = permissions_full()
  )
  readonly_child <- full_lead$.__enclos_env__$private$create_sub_agent(
    readonly_definition
  )
  expect_identical(readonly_child$permissions$mode, "readonly")
  expect_false(readonly_child$permissions$file_write)
})

test_that("agent_definition validates max_requests eagerly", {
  base_args <- list(
    name = "invalid",
    description = "Invalid limit",
    prompt = "Help"
  )

  expect_error(
    do.call(agent_definition, c(base_args, list(max_requests = -1))),
    "non-negative"
  )
  expect_error(
    do.call(agent_definition, c(base_args, list(max_requests = 1.5))),
    "whole number"
  )
  expect_error(
    do.call(agent_definition, c(base_args, list(max_requests = c(1, 2)))),
    "length-1"
  )
  expect_identical(
    do.call(
      agent_definition,
      c(base_args, list(max_requests = 2))
    )$max_requests,
    2L
  )
})

test_that("agent_definition supports model inheritance", {
  def <- agent_definition(
    name = "test",
    description = "Test",
    prompt = "Test"
  )

  # Default should be "inherit"
  expect_equal(def$model, "inherit")

  # Can specify custom model
  def_custom <- agent_definition(
    name = "test",
    description = "Test",
    prompt = "Test",
    model = "openai/gpt-4o"
  )
  expect_equal(def_custom$model, "openai/gpt-4o")
})

test_that("agent_definition supports skills", {
  def <- agent_definition(
    name = "test",
    description = "Test",
    prompt = "Test",
    skills = list("skill1", "skill2")
  )

  expect_equal(length(def$skills), 2)
  expect_true("skill1" %in% def$skills)
})

# Tests for SubagentStop hook

test_that("agent_definition with empty tools is valid", {
  def <- agent_definition(
    name = "no_tools",
    description = "Agent without tools",
    prompt = "You have no tools"
  )

  expect_equal(def$tools, list())
  expect_s3_class(def, "AgentDefinition")
})

test_that("agent_definition with empty skills is valid", {
  def <- agent_definition(
    name = "no_skills",
    description = "Agent without skills",
    prompt = "You have no skills"
  )

  expect_equal(def$skills, list())
  expect_s3_class(def, "AgentDefinition")
})

test_that("agent_definition handles special characters in name", {
  def <- agent_definition(
    name = "agent-with-dashes_and_underscores",
    description = "Test agent",
    prompt = "Test prompt"
  )

  expect_equal(def$name, "agent-with-dashes_and_underscores")
})

test_that("agent_definition handles long descriptions", {
  long_desc <- paste(
    rep("This is a very long description. ", 50),
    collapse = ""
  )

  def <- agent_definition(
    name = "long_desc_agent",
    description = long_desc,
    prompt = "Test prompt"
  )

  expect_equal(def$description, long_desc)
})

test_that("agent_definition handles multi-line prompts", {
  multi_line_prompt <- "Line 1\nLine 2\nLine 3\n\nLine after blank"

  def <- agent_definition(
    name = "multi_line_agent",
    description = "Test",
    prompt = multi_line_prompt
  )

  expect_equal(def$prompt, multi_line_prompt)
})

test_that("agent_definition accepts all parameter types", {
  def <- agent_definition(
    name = "full_agent",
    description = "Fully specified agent",
    prompt = "Full prompt here",
    tools = tools_file(),
    model = "openai/gpt-4o-mini",
    skills = list("skill1", "skill2")
  )

  expect_equal(def$name, "full_agent")
  expect_equal(def$description, "Fully specified agent")
  expect_equal(def$prompt, "Full prompt here")
  expect_true(length(def$tools) >= 3) # tools_file() returns multiple tools
  expect_equal(def$model, "openai/gpt-4o-mini")
  expect_equal(def$skills, list("skill1", "skill2"))
})
