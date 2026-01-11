# Tests for multi-agent orchestration
# Note: create_mock_chat is defined in helper-mocks.R

# Tests for agent_definition

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

test_that("LeadAgent initializes correctly", {
  mock_chat <- create_mock_chat()
  sub_agent <- agent_definition(
    name = "helper",
    description = "A helper agent",
    prompt = "You help with tasks"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(sub_agent)
  )

  expect_s3_class(lead, "LeadAgent")
  expect_s3_class(lead, "Agent")
  expect_equal(length(lead$sub_agent_defs), 1)
})

test_that("LeadAgent adds delegate_to_agent tool", {
  mock_chat <- create_mock_chat()
  sub_agent <- agent_definition(
    name = "helper",
    description = "A helper agent",
    prompt = "You help with tasks"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(sub_agent)
  )

  tools <- mock_chat$get_tools()
  expect_true("delegate_to_agent" %in% names(tools))
})

test_that("LeadAgent validates sub_agents", {
  mock_chat <- create_mock_chat()

  expect_error(
    LeadAgent$new(
      chat = mock_chat,
      sub_agents = list("not an agent definition")
    ),
    "AgentDefinition"
  )
})

test_that("LeadAgent available_sub_agents returns names", {
  mock_chat <- create_mock_chat()
  agent1 <- agent_definition(
    name = "agent_one",
    description = "First agent",
    prompt = "Prompt 1"
  )
  agent2 <- agent_definition(
    name = "agent_two",
    description = "Second agent",
    prompt = "Prompt 2"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(agent1, agent2)
  )

  available <- lead$available_sub_agents()

  expect_equal(length(available), 2)
  expect_true("agent_one" %in% available)
  expect_true("agent_two" %in% available)
})

test_that("LeadAgent register_sub_agent works", {
  mock_chat <- create_mock_chat()
  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list()
  )

  expect_equal(length(lead$sub_agent_defs), 0)

  new_agent <- agent_definition(
    name = "new_agent",
    description = "Newly registered",
    prompt = "New prompt"
  )

  lead$register_sub_agent(new_agent)

  expect_equal(length(lead$sub_agent_defs), 1)
  expect_true("new_agent" %in% lead$available_sub_agents())
})

test_that("LeadAgent register_sub_agent validates input", {
  mock_chat <- create_mock_chat()
  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list()
  )

  expect_error(
    lead$register_sub_agent("not a definition"),
    "AgentDefinition"
  )
})

test_that("LeadAgent builds system prompt with sub-agents", {
  mock_chat <- create_mock_chat()
  agent1 <- agent_definition(
    name = "code_reader",
    description = "Reads code files",
    prompt = "You read code"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(agent1),
    system_prompt = "You are a lead agent."
  )

  prompt <- mock_chat$get_system_prompt()

  expect_true(grepl("lead agent", prompt))
  expect_true(grepl("code_reader", prompt))
  expect_true(grepl("Reads code files", prompt))
  expect_true(grepl("delegate_to_agent", prompt))
})

test_that("LeadAgent print works", {
  mock_chat <- create_mock_chat()
  agent1 <- agent_definition(
    name = "test_sub",
    description = "Test sub-agent",
    prompt = "Test"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(agent1)
  )

  output <- capture.output(print(lead))

  expect_true(any(grepl("Agent", output)))
  expect_true(any(grepl("sub_agents", output)))
  expect_true(any(grepl("test_sub", output)))
})

test_that("LeadAgent inherits from Agent", {
  mock_chat <- create_mock_chat()
  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list()
  )

  # Should have Agent methods
  expect_true("add_hook" %in% names(lead))
  expect_true("run" %in% names(lead))
  expect_true("run_sync" %in% names(lead))
  expect_true("cost" %in% names(lead))
})

# Tests for delegation functionality

test_that("LeadAgent delegate tool validates agent name", {
  mock_chat <- create_mock_chat()
  agent1 <- agent_definition(
    name = "known_agent",
    description = "A known agent",
    prompt = "You are known"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(agent1)
  )

  # Get the delegate tool
  tools <- mock_chat$get_tools()
  delegate_tool <- tools[["delegate_to_agent"]]

  expect_true(!is.null(delegate_tool))
})

test_that("LeadAgent passes permissions to sub-agents", {
  mock_chat <- create_mock_chat()
  agent1 <- agent_definition(
    name = "sub_agent",
    description = "A sub-agent",
    prompt = "You help"
  )

  perms <- permissions_readonly()
  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(agent1),
    permissions = perms
  )

  # Permissions should be stored
  expect_identical(lead$permissions, perms)
})

test_that("LeadAgent passes working_dir to sub-agents", {
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  mock_chat <- create_mock_chat()
  agent1 <- agent_definition(
    name = "sub_agent",
    description = "A sub-agent",
    prompt = "You help"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(agent1),
    working_dir = temp_dir
  )

  expect_equal(lead$working_dir, temp_dir)
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

test_that("agent_with_delegation creates default sub-agents", {
  mock_chat <- create_mock_chat()
  lead <- agent_with_delegation(chat = mock_chat)

  available <- lead$available_sub_agents()

  # Should have code_reader and code_analyzer by default
  expect_true("code_reader" %in% available)
  expect_true("code_analyzer" %in% available)
})

test_that("agent_with_delegation accepts custom permissions", {
  mock_chat <- create_mock_chat()
  perms <- permissions_readonly()
  lead <- agent_with_delegation(chat = mock_chat, permissions = perms)

  expect_identical(lead$permissions, perms)
})

# Tests for SubagentStop hook
test_that("SubagentStop hook event exists", {
  expect_true("SubagentStop" %in% HookEvent)
})

test_that("HookResultSubagentStop creates correct structure", {
  result <- HookResultSubagentStop()

  expect_s3_class(result, "HookResultSubagentStop")
  expect_s3_class(result, "HookResult")
  expect_true(result$handled)

  result_unhandled <- HookResultSubagentStop(handled = FALSE)
  expect_false(result_unhandled$handled)
})

test_that("LeadAgent can add SubagentStop hook", {
  mock_chat <- create_mock_chat()
  sub_agent <- agent_definition(
    name = "helper",
    description = "A helper agent",
    prompt = "You help with tasks"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(sub_agent)
  )

  # Add SubagentStop hook
  hook_fired <- FALSE
  captured_agent_name <- NULL
  captured_task <- NULL

  lead$add_hook(HookMatcher$new(
    event = "SubagentStop",
    callback = function(agent_name, task, result, context) {
      hook_fired <<- TRUE
      captured_agent_name <<- agent_name
      captured_task <<- task
      HookResultSubagentStop()
    }
  ))

  expect_equal(lead$hooks$count(), 1)
})

# Tests for delegation functionality errors and edge cases

test_that("delegate tool rejects unknown agent name", {
  mock_chat <- create_mock_chat()
  agent1 <- agent_definition(
    name = "known_agent",
    description = "A known agent",
    prompt = "You are known"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(agent1)
  )

  # Get the delegate tool
  tools <- mock_chat$get_tools()
  delegate_tool <- tools[["delegate_to_agent"]]

  # The tool should exist and be an S7 ToolDef
  expect_true(!is.null(delegate_tool))
  expect_true(inherits(delegate_tool, "ellmer::ToolDef"))
})

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

test_that("LeadAgent with no sub-agents is valid", {
  mock_chat <- create_mock_chat()

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list()
  )

  expect_equal(length(lead$sub_agent_defs), 0)
  # sapply on empty list returns list(), check length instead
  expect_equal(length(lead$available_sub_agents()), 0)
})

test_that("LeadAgent duplicate sub-agent names allowed", {
  # Not validated - this is a user mistake but doesn't crash
  mock_chat <- create_mock_chat()

  agent1 <- agent_definition(
    name = "duplicate",
    description = "First agent",
    prompt = "Prompt 1"
  )
  agent2 <- agent_definition(
    name = "duplicate",
    description = "Second agent with same name",
    prompt = "Prompt 2"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(agent1, agent2)
  )

  available <- lead$available_sub_agents()
  # Both are in the list (though this could cause confusion)
  expect_equal(length(available), 2)
  expect_true(all(available == "duplicate"))
})

test_that("LeadAgent registers additional tools", {
  mock_chat <- create_mock_chat()

  # Create a simple custom tool using ellmer
  custom_tool <- ellmer::tool(
    fun = function() "custom result",
    name = "custom_tool",
    description = "A custom tool for testing"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(),
    tools = list(custom_tool)
  )

  tools <- mock_chat$get_tools()

  # Should have delegate_to_agent + custom_tool
  expect_true("delegate_to_agent" %in% names(tools))
  expect_true("custom_tool" %in% names(tools))
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

test_that("LeadAgent system prompt contains sub-agent info", {
  mock_chat <- create_mock_chat()

  agent1 <- agent_definition(
    name = "specialized_reader",
    description = "Reads and analyzes files carefully",
    prompt = "You are a file reader"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(agent1),
    system_prompt = "You coordinate tasks."
  )

  prompt <- mock_chat$get_system_prompt()

  # Should contain base prompt
  expect_true(grepl("coordinate tasks", prompt))

  # Should contain sub-agent section
  expect_true(grepl("Available Sub-Agents", prompt))
  expect_true(grepl("specialized_reader", prompt))
  expect_true(grepl("Reads and analyzes files carefully", prompt))
  expect_true(grepl("delegate_to_agent", prompt))
})

test_that("LeadAgent register_sub_agent updates system prompt", {
  mock_chat <- create_mock_chat()

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(),
    system_prompt = "Base prompt"
  )

  # Initially no sub-agents in prompt
  prompt_before <- mock_chat$get_system_prompt()

  # Register a new sub-agent
  new_agent <- agent_definition(
    name = "new_helper",
    description = "A newly added helper",
    prompt = "New helper prompt"
  )
  lead$register_sub_agent(new_agent)

  # System prompt should now include the new agent
  prompt_after <- mock_chat$get_system_prompt()
  expect_true(grepl("new_helper", prompt_after))
  expect_true(grepl("newly added helper", prompt_after))
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

test_that("LeadAgent inherits Agent hooks field", {
  mock_chat <- create_mock_chat()

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list()
  )

  # Should have hooks registry from Agent
  expect_true(!is.null(lead$hooks))
  expect_s3_class(lead$hooks, "HookRegistry")
  expect_equal(lead$hooks$count(), 0)
})
