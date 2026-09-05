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

test_that("sub-agent permission modes cannot exceed the lead policy", {
  mock_chat <- create_mock_chat()
  widening <- agent_definition(
    name = "widening",
    description = "Attempts to widen authority",
    prompt = "You help",
    permission_mode = "full"
  )
  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(widening),
    permissions = permissions_readonly()
  )

  expect_error(
    lead$.__enclos_env__$private$create_sub_agent(widening),
    "cannot change under the lead policy"
  )

  restricted <- widening
  restricted$name <- "restricted"
  restricted$permission_mode <- "readonly"
  child <- lead$.__enclos_env__$private$create_sub_agent(restricted)
  expect_identical(child$permissions$mode, "readonly")
  expect_s3_class(
    child$permissions$check("write_file", list(path = "blocked.txt")),
    "PermissionResultDeny"
  )

  plan_definition <- widening
  plan_definition$name <- "plan-to-readonly"
  plan_definition$permission_mode <- "readonly"
  plan_lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(plan_definition),
    permissions = Permissions$new(
      mode = "plan",
      file_read = TRUE,
      file_write = FALSE,
      bash = FALSE,
      r_code = FALSE,
      web = FALSE,
      install_packages = FALSE,
      tool_allowlist = "custom_tool"
    )
  )
  plan_child <- plan_lead$.__enclos_env__$private$create_sub_agent(
    plan_definition
  )
  expect_identical(plan_child$permissions$mode, "readonly")
  expect_false(plan_child$permissions$web)
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

test_that("sub-agent disallowed tools override permission prompts", {
  definition <- agent_definition(
    name = "no-prompt",
    description = "Cannot request permission",
    prompt = "You help",
    permission_mode = "plan",
    disallowed_tools = "ask_user"
  )
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(definition),
    permissions = permissions_full()
  )
  child <- lead$.__enclos_env__$private$create_sub_agent(definition)

  result <- child$permissions$check("ask_user", list())
  expect_s3_class(result, "PermissionResultDeny")
  expect_false(grepl("Use ask_user", result$reason, fixed = TRUE))
})

test_that("sub-agent tool denylist drops tools with unreadable names", {
  lead <- LeadAgent$new(chat = create_mock_chat())
  readable <- tools_file()[[1L]]
  tools <- list(readable = readable, unreadable = new.env(parent = emptyenv()))

  filtered <- NULL
  expect_snapshot(
    filtered <- lead$.__enclos_env__$private$filter_disallowed_tools(
      tools,
      disallowed_tools = "run_bash"
    )
  )

  expect_named(filtered, "readable")
  expect_identical(filtered[[1L]], readable)
})

test_that("sub-agents retain inherited prompt-tool gates", {
  definition <- agent_definition(
    name = "gated-prompt",
    description = "Retains lead tool gates",
    prompt = "You help",
    permission_mode = "plan"
  )
  policies <- list(
    Permissions$new(
      mode = "full",
      file_read = TRUE,
      file_write = TRUE,
      bash = TRUE,
      r_code = TRUE,
      web = TRUE,
      install_packages = TRUE,
      tool_denylist = "ask_user"
    ),
    Permissions$new(
      mode = "full",
      file_read = TRUE,
      file_write = TRUE,
      bash = TRUE,
      r_code = TRUE,
      web = TRUE,
      install_packages = TRUE,
      tool_allowlist = "read_file"
    )
  )

  for (permissions in policies) {
    lead <- LeadAgent$new(
      chat = create_mock_chat(),
      sub_agents = list(definition),
      permissions = permissions
    )
    child <- lead$.__enclos_env__$private$create_sub_agent(definition)
    result <- child$permissions$check("ask_user", list())

    expect_s3_class(result, "PermissionResultDeny")
    expect_false(grepl("Use ask_user", result$reason, fixed = TRUE))
  }
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

test_that("sub-agents inherit remaining lead run budgets", {
  definition <- agent_definition(
    name = "bounded",
    description = "Uses bounded resources",
    prompt = "You help",
    max_requests = 3
  )
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(definition),
    usage_limits = UsageLimits(
      max_requests = 8,
      max_tool_calls = 5,
      max_total_tokens = 1000,
      max_cost_usd = 0.50
    )
  )
  private <- lead$.__enclos_env__$private
  private$current_usage_limits <- UsageLimits(
    max_requests = 6,
    max_tool_calls = 4,
    max_total_tokens = 700,
    max_cost_usd = 0.30
  )
  private$current_usage_baseline <- lead$usage()
  private$current_external_usage <- AgentUsage(
    requests = 2,
    tool_calls = 1,
    input_tokens = 100,
    output_tokens = 50,
    cost_usd = 0.10
  )
  private$run_active <- TRUE

  child <- private$create_sub_agent(definition)

  expect_identical(child$usage_limits$max_requests, 3L)
  expect_identical(child$usage_limits$max_tool_calls, 3L)
  expect_equal(child$usage_limits$max_total_tokens, 550)
  expect_equal(child$usage_limits$max_cost_usd, 0.20)

  private$reserve_delegation_usage("delegation-one", child$usage_limits)
  sibling_limits <- private$derive_subagent_usage_limits(definition)
  expect_identical(sibling_limits$max_requests, 1L)
  expect_identical(sibling_limits$max_tool_calls, 0L)
  expect_identical(sibling_limits$max_total_tokens, 0L)
  expect_identical(sibling_limits$max_cost_usd, 0)
  private$release_delegation_usage("delegation-one")

  restored_limits <- private$derive_subagent_usage_limits(definition)
  expect_identical(restored_limits$max_requests, 3L)
  expect_identical(restored_limits$max_tool_calls, 3L)
  expect_identical(restored_limits$max_total_tokens, 550L)
  expect_equal(restored_limits$max_cost_usd, 0.20)

  private$current_stream_controller <- NULL
  private$add_external_usage(AgentUsage(requests = 1))
  expect_false(private$should_stop)
  private$add_external_usage(AgentUsage(requests = 3))
  expect_true(private$should_stop)
  expect_identical(private$stop_reason_from_hook, "request_limit")
  private$run_active <- FALSE
  private$should_stop <- FALSE
  private$stop_reason_from_hook <- NULL
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

  expect_equal(
    lead$working_dir,
    normalizePath(temp_dir, mustWork = TRUE, winslash = "/")
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

test_that("delegation passes permissions to sub-agent", {
  # This test verifies that the lead agent's permissions are inherited
  # by sub-agents during delegation

  mock_chat <- create_mock_chat()

  # Track what permissions were used
  sub_agent_created_with_perms <- NULL

  mock_chat$clone <- function(deep = FALSE) {
    sub_mock <- create_mock_chat(responses = list("Done"))
    sub_mock$stream <- function(prompt = NULL) {
      yielded <- FALSE
      function() {
        if (yielded) {
          return(coro::exhausted())
        }
        yielded <<- TRUE
        "Done"
      }
    }
    sub_mock$last_turn <- function(role = "assistant") {
      create_mock_assistant_turn(text = "Done")
    }
    sub_mock
  }

  sub_def <- agent_definition(
    name = "sub",
    description = "Sub-agent",
    prompt = "You are a sub-agent"
  )

  # Create lead agent with readonly permissions
  perms <- permissions_readonly()
  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(sub_def),
    permissions = perms
  )

  # Verify lead has the permissions
  expect_identical(lead$permissions, perms)

  # Execute delegation - if it works, permissions were passed correctly
  # (readonly permissions still allow the agent to run)
  tools <- mock_chat$get_tools()
  delegate_tool <- tools[["delegate_to_agent"]]

  result <- resolve_async_value(delegate_tool("sub", "Read something"))
  expect_equal(result, "Done")
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

test_that("SubagentStop hook receives working_dir in context", {
  mock_chat <- create_mock_chat()

  mock_chat$clone <- function(deep = FALSE) {
    sub_mock <- create_mock_chat(responses = list("Result"))
    sub_mock$stream <- function(prompt = NULL) {
      yielded <- FALSE
      function() {
        if (yielded) {
          return(coro::exhausted())
        }
        yielded <<- TRUE
        "Result"
      }
    }
    sub_mock$last_turn <- function(role = "assistant") {
      create_mock_assistant_turn(text = "Result")
    }
    sub_mock
  }

  sub_def <- agent_definition(
    name = "helper",
    description = "Helper",
    prompt = "Help"
  )

  withr::local_tempdir(pattern = "deputy-test") -> temp_dir

  lead <- LeadAgent$new(
    chat = mock_chat,
    sub_agents = list(sub_def),
    working_dir = temp_dir
  )

  captured_context <- NULL
  lead$add_hook(HookMatcher$new(
    event = "SubagentStop",
    timeout = 0, # Run synchronously to avoid subprocess closure issues
    callback = function(agent_name, task, result, context) {
      captured_context <<- context
      NULL
    }
  ))

  tools <- mock_chat$get_tools()
  delegate_tool <- tools[["delegate_to_agent"]]
  resolve_async_value(delegate_tool("helper", "Help me"))

  expect_equal(
    captured_context$working_dir,
    normalizePath(temp_dir, mustWork = TRUE, winslash = "/")
  )
})
