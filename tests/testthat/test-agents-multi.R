# Tests for multi-agent orchestration

# Reuse mock chat helper from test-agent.R
create_mock_chat <- function(responses = list("Hello!")) {
  response_idx <- 0
  turns <- list()
  tools <- list()
  system_prompt <- NULL

  structure(
    list(
      chat = function(prompt = NULL) {
        response_idx <<- response_idx + 1
        if (response_idx > length(responses)) {
          response_idx <<- length(responses)
        }
        responses[[response_idx]]
      },
      stream = function(prompt = NULL) {
        response_idx <<- response_idx + 1
        if (response_idx > length(responses)) {
          response_idx <<- length(responses)
        }
        text <- responses[[response_idx]]
        yielded <- FALSE
        function() {
          if (yielded) return(coro::exhausted())
          yielded <<- TRUE
          text
        }
      },
      get_turns = function() turns,
      set_turns = function(new_turns) turns <<- new_turns,
      get_system_prompt = function() system_prompt,
      set_system_prompt = function(prompt) system_prompt <<- prompt,
      get_tools = function() tools,
      register_tool = function(tool) {
        tools[[tool@name]] <<- tool
      },
      register_tools = function(tool_list) {
        for (tool in tool_list) {
          tools[[tool@name]] <<- tool
        }
      },
      get_tokens = function() {
        data.frame(input = 100, output = 50, cached_input = 0, cost = 0.001)
      },
      get_provider = function() {
        list(name = "mock", model = "test-model")
      },
      last_turn = function(role = "assistant") {
        structure(
          list(text = responses[[min(response_idx, length(responses))]]),
          class = "AssistantTurn"
        )
      },
      on_tool_request = function(callback) {},
      on_tool_result = function(callback) {}
    ),
    class = "Chat"
  )
}

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
