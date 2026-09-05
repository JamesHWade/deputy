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

test_that("LeadAgent and sub-agents use native session identifiers", {
  sub_agent <- agent_definition(
    name = "helper",
    description = "A helper agent",
    prompt = "You help with tasks"
  )
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(sub_agent),
    session_id = "session-lead"
  )

  child <- lead$.__enclos_env__$private$create_sub_agent(sub_agent)

  expect_identical(lead$session_id(), "session-lead")
  expect_match(child$session_id(), "^session_")
  expect_false(identical(child$session_id(), lead$session_id()))
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

test_that("LeadAgent propagates context policy to sub-agents", {
  directory <- withr::local_tempdir(pattern = "deputy-lead-context-")
  policy <- ContextPolicy(
    max_tokens = 8000,
    compact_to = 0.25,
    fallback = "text",
    max_tool_result_bytes = 1024,
    offload_dir = directory
  )
  definition <- agent_definition(
    name = "helper",
    description = "A helper agent",
    prompt = "You help with tasks"
  )
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(definition),
    context_policy = policy
  )

  child <- lead$.__enclos_env__$private$create_sub_agent(definition)

  expect_identical(lead$context_policy, policy)
  expect_identical(child$context_policy, policy)
})

test_that("LeadAgent clones bind delegation to the cloned registry", {
  original_definition <- agent_definition(
    name = "original",
    description = "Original helper",
    prompt = "You help with original tasks"
  )
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(original_definition)
  )
  cloned <- lead$clone()
  clone_definition <- agent_definition(
    name = "clone_only",
    description = "Clone-only helper",
    prompt = "You help with cloned tasks"
  )

  cloned$register_sub_agent(clone_definition)

  expect_error(
    cloned$get_tools()[["delegate_to_agent"]]("missing", "Do something"),
    "original.*clone_only|clone_only.*original"
  )
  expect_error(
    lead$get_tools()[["delegate_to_agent"]]("missing", "Do something"),
    "Available agents: original$"
  )
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

test_that("readonly sub-agents retain custom lead read restrictions", {
  definition <- agent_definition(
    name = "restricted-reader",
    description = "Must retain the lead read ceiling",
    prompt = "You help",
    permission_mode = "readonly"
  )

  for (lead_mode in c("standard", "plan")) {
    permissions <- Permissions$new(
      mode = lead_mode,
      file_read = FALSE,
      file_write = FALSE,
      bash = FALSE,
      r_code = FALSE,
      web = FALSE,
      install_packages = FALSE
    )
    lead <- LeadAgent$new(
      chat = create_mock_chat(),
      sub_agents = list(definition),
      permissions = permissions
    )
    child <- lead$.__enclos_env__$private$create_sub_agent(definition)

    expect_identical(child$permissions$mode, "readonly")
    expect_false(child$permissions$file_read)
    expect_s3_class(
      child$permissions$check("read_file", list(path = "blocked.txt")),
      "PermissionResultDeny"
    )
  }
})

test_that("readonly sub-agents retain custom callback denials", {
  definition <- agent_definition(
    name = "callback-restricted",
    description = "Must retain the callback ceiling",
    prompt = "You help",
    permission_mode = "readonly"
  )
  callback <- function(tool_name, ...) {
    if (identical(tool_name, "read_file")) {
      return(PermissionResultDeny(reason = "custom read denial"))
    }
    PermissionResultAllow()
  }
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(definition),
    permissions = Permissions$new(
      mode = "standard",
      can_use_tool = callback
    )
  )
  child <- lead$.__enclos_env__$private$create_sub_agent(definition)

  expect_s3_class(
    child$permissions$check("read_file", list(path = "blocked.txt")),
    "PermissionResultDeny"
  )
  expect_s3_class(
    child$permissions$check("run_bash", list(command = "pwd")),
    "PermissionResultDeny"
  )
})

test_that("SubagentStop hook event exists", {
  expect_true("SubagentStop" %in% HookEvent)
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
      NULL
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

test_that("LeadAgent rejects duplicate normalized routing keys", {
  mock_chat <- create_mock_chat()

  agent1 <- agent_definition(
    name = "duplicate",
    description = "First agent",
    prompt = "Prompt 1"
  )
  agent2 <- agent_definition(
    name = "DUPLICATE",
    description = "Second agent with same name",
    prompt = "Prompt 2"
  )

  condition <- rlang::catch_cnd(
    LeadAgent$new(
      chat = mock_chat,
      sub_agents = list(agent1, agent2)
    )
  )

  expect_s3_class(condition, "error")
  expect_match(conditionMessage(condition), "Duplicate", fixed = TRUE)
  expect_match(conditionMessage(condition), "duplicate", fixed = TRUE)
})

test_that("LeadAgent registry is a read-only snapshot", {
  definition <- agent_definition(
    name = "helper",
    description = "Helps with tasks",
    prompt = "Help"
  )
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(definition)
  )

  snapshot <- lead$sub_agent_defs
  snapshot[[1]]$name <- "changed"
  definition$name <- "also-changed"

  expect_identical(lead$available_sub_agents(), "helper")
  expect_identical(lead$sub_agent_defs[[1]]$name, "helper")

  condition <- rlang::catch_cnd({
    lead$sub_agent_defs <- list()
  })
  expect_s3_class(condition, "error")
  expect_match(conditionMessage(condition), "read-only", fixed = TRUE)
})

test_that("LeadAgent rejects duplicate registration", {
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(agent_definition(
      name = "helper",
      description = "Helps",
      prompt = "Help"
    ))
  )

  duplicate <- agent_definition(
    name = "HELPER",
    description = "Also helps",
    prompt = "Help again"
  )
  condition <- rlang::catch_cnd(lead$register_sub_agent(duplicate))

  expect_s3_class(condition, "error")
  expect_match(conditionMessage(condition), "already registered", fixed = TRUE)
  expect_identical(lead$available_sub_agents(), "helper")
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

test_that("register_sub_agent preserves prompt content outside routing", {
  chat <- create_mock_chat()
  chat$set_turns(list(
    create_mock_user_turn("Q1"),
    create_mock_assistant_turn("A1"),
    create_mock_user_turn("Q2")
  ))
  lead <- LeadAgent$new(
    chat = chat,
    sub_agents = list(agent_definition(
      name = "first",
      description = "First helper",
      prompt = "You are the first helper"
    )),
    system_prompt = "Base prompt"
  )
  lead$compact(keep_last = 1L, summary = "Retained lead summary")
  lead$.__enclos_env__$private$append_hook_context("Retained hook context")

  lead$register_sub_agent(agent_definition(
    name = "second",
    description = "Second helper",
    prompt = "You are the second helper"
  ))

  prompt <- lead$get_system_prompt()
  expect_match(prompt, "Retained lead summary", fixed = TRUE)
  expect_match(prompt, "Retained hook context", fixed = TRUE)
  expect_match(prompt, "second", fixed = TRUE)
  expect_length(
    gregexpr("# Available Sub-Agents", prompt, fixed = TRUE)[[1L]],
    1L
  )
})

test_that("register_sub_agent ignores user-authored routing headings", {
  user_section <- paste(
    "Base prompt",
    "# Available Sub-Agents",
    "These headings are user-authored instructions.",
    "# End Available Sub-Agents",
    sep = "\n"
  )
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(agent_definition(
      name = "first",
      description = "First generated helper",
      prompt = "Act as the first helper"
    )),
    system_prompt = user_section
  )

  lead$register_sub_agent(agent_definition(
    name = "second",
    description = "Second generated helper",
    prompt = "Act as the second helper"
  ))

  prompt <- lead$get_system_prompt()
  expect_match(prompt, "user-authored instructions", fixed = TRUE)
  expect_match(prompt, "First generated helper", fixed = TRUE)
  expect_match(prompt, "Second generated helper", fixed = TRUE)
  expect_length(
    gregexpr("# Available Sub-Agents", prompt, fixed = TRUE)[[1L]],
    2L
  )
  expect_length(
    gregexpr(
      "<!-- deputy-lead-routing:v1:start -->",
      prompt,
      fixed = TRUE
    )[[1L]],
    1L
  )
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

# ============================================================================
# Integration tests for delegation execution
# ============================================================================

test_that("delegate_to_agent rejects unknown agent name with error", {
  # This test verifies that the delegate_to_agent tool correctly rejects
  # requests for unknown agent names using tool_reject()

  mock_chat <- create_mock_chat()
  known_agent <- agent_definition(
    name = "known_agent",
    description = "A known agent",
    prompt = "You are known"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(known_agent)
  )

  # Get the delegate tool and call it with unknown agent name
  tools <- mock_chat$get_tools()
  delegate_tool <- tools[["delegate_to_agent"]]

  # tool_reject throws an error with specific message
  expect_error(
    delegate_tool("unknown_agent", "Do something"),
    "Unknown agent.*unknown_agent"
  )
})

test_that("delegate_to_agent error message lists available agents", {
  mock_chat <- create_mock_chat()
  agent1 <- agent_definition(
    name = "reader",
    description = "Reads files",
    prompt = "You read"
  )
  agent2 <- agent_definition(
    name = "writer",
    description = "Writes files",
    prompt = "You write"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(agent1, agent2)
  )

  tools <- mock_chat$get_tools()
  delegate_tool <- tools[["delegate_to_agent"]]

  # Error should list available agents
  expect_error(
    delegate_tool("nonexistent", "Do something"),
    "reader.*writer|writer.*reader"
  )
})

test_that("SubagentStop hook fires after successful delegation", {
  # This test verifies that the SubagentStop hook is fired after a sub-agent
  # completes its task. We mock the sub-agent creation to avoid real API calls.

  mock_chat <- create_mock_chat()

  # Add clone method to mock_chat for model inheritance
  mock_chat$clone <- function(deep = FALSE) {
    sub_mock <- create_mock_chat(responses = list("Sub-agent result"))
    # Override stream to return strings
    sub_mock$stream <- function(prompt = NULL) {
      yielded <- FALSE
      function() {
        if (yielded) {
          return(coro::exhausted())
        }
        yielded <<- TRUE
        "Sub-agent result"
      }
    }
    sub_mock$last_turn <- function(role = "assistant") {
      create_mock_assistant_turn(text = "Sub-agent result")
    }
    sub_mock
  }

  sub_agent_def <- agent_definition(
    name = "helper",
    description = "A helper agent",
    prompt = "You help with tasks"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(sub_agent_def)
  )

  # Track hook firing
  hook_fired <- FALSE
  captured_agent_name <- NULL
  captured_task <- NULL
  captured_result <- NULL

  lead$add_hook(HookMatcher$new(
    event = "SubagentStop",
    timeout = 0, # Run synchronously to avoid subprocess closure issues
    callback = function(agent_name, task, result, context) {
      hook_fired <<- TRUE
      captured_agent_name <<- agent_name
      captured_task <<- task
      captured_result <<- result
      NULL
    }
  ))

  # Call the delegate tool
  tools <- mock_chat$get_tools()
  delegate_tool <- tools[["delegate_to_agent"]]

  result <- resolve_async_value(delegate_tool("helper", "Do a task"))

  # Verify hook was fired with correct arguments

  expect_true(hook_fired)
  expect_equal(captured_agent_name, "helper")
  expect_equal(captured_task, "Do a task")
  expect_equal(captured_result, "Sub-agent result")
})

test_that("delegation executes sub-agent and returns result", {
  # This test verifies the full delegation flow: find agent definition,
  # create sub-agent, run task, return result

  mock_chat <- create_mock_chat()

  # Add clone method for model inheritance
  mock_chat$clone <- function(deep = FALSE) {
    sub_mock <- create_mock_chat(
      responses = list("Task completed successfully")
    )
    sub_mock$stream <- function(prompt = NULL) {
      yielded <- FALSE
      function() {
        if (yielded) {
          return(coro::exhausted())
        }
        yielded <<- TRUE
        "Task completed successfully"
      }
    }
    sub_mock$last_turn <- function(role = "assistant") {
      create_mock_assistant_turn(text = "Task completed successfully")
    }
    sub_mock
  }

  worker_def <- agent_definition(
    name = "worker",
    description = "Does work",
    prompt = "You are a worker"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(worker_def)
  )

  tools <- mock_chat$get_tools()
  delegate_tool <- tools[["delegate_to_agent"]]

  result <- resolve_async_value(delegate_tool("worker", "Complete the task"))

  expect_equal(result, "Task completed successfully")
  expect_length(
    lead$.__enclos_env__$private$delegation_usage_reservations,
    0L
  )
})

test_that("delegation handles sub-agent execution failure", {
  # This test verifies that when a sub-agent fails, the error is properly
  # wrapped and returned as a tool rejection

  mock_chat <- create_mock_chat()

  # Clone that produces a chat which will fail on both stream AND chat
  mock_chat$clone <- function(deep = FALSE) {
    sub_mock <- create_mock_chat()
    sub_mock$stream <- function(prompt = NULL) {
      stop("Simulated stream failure")
    }
    sub_mock$chat <- function(prompt = NULL) {
      stop("Simulated chat failure")
    }
    sub_mock
  }

  failing_agent <- agent_definition(
    name = "failer",
    description = "An agent that fails",
    prompt = "You fail"
  )

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(failing_agent)
  )

  tools <- mock_chat$get_tools()
  delegate_tool <- tools[["delegate_to_agent"]]

  # Should throw an error from tool_reject
  expect_error(
    suppressWarnings(resolve_async_value(
      delegate_tool("failer", "Do something")
    )),
    "Sub-agent 'failer' failed"
  )
  expect_length(
    lead$.__enclos_env__$private$delegation_usage_reservations,
    0L
  )
})
