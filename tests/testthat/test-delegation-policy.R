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
    local_test_subagent(lead, widening),
    "cannot change under the lead policy"
  )

  fields <- S7::props(widening)
  fields$name <- "restricted"
  fields$permission_mode <- "readonly"
  restricted <- do.call(agent_definition, fields)
  child <- local_test_subagent(lead, restricted)
  expect_identical(child$permissions$mode, "readonly")
  expect_s7_class(
    permissions_check(
      child$permissions,
      "write_file",
      list(path = "blocked.txt")
    ),
    PermissionResultDeny
  )

  fields <- S7::props(widening)
  fields$name <- "plan-to-readonly"
  fields$permission_mode <- "readonly"
  plan_definition <- do.call(agent_definition, fields)
  plan_lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(plan_definition),
    permissions = Permissions(
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
  plan_child <- local_test_subagent(plan_lead, plan_definition)
  expect_identical(plan_child$permissions$mode, "readonly")
  expect_false(plan_child$permissions$web)
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
  child <- local_test_subagent(lead, definition)

  result <- permissions_check(child$permissions, "ask_user", list())
  expect_s7_class(result, PermissionResultDeny)
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
    Permissions(
      mode = "full",
      file_read = TRUE,
      file_write = TRUE,
      bash = TRUE,
      r_code = TRUE,
      web = TRUE,
      install_packages = TRUE,
      tool_denylist = "ask_user"
    ),
    Permissions(
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
    child <- local_test_subagent(lead, definition)
    result <- permissions_check(child$permissions, "ask_user", list())

    expect_s7_class(result, PermissionResultDeny)
    expect_false(grepl("Use ask_user", result$reason, fixed = TRUE))
  }
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

  child <- local_test_subagent(lead, definition)

  expect_identical(child$usage_limits$max_requests, 3L)
  expect_identical(child$usage_limits$max_tool_calls, 3L)
  expect_equal(child$usage_limits$max_total_tokens, 550)
  expect_equal(child$usage_limits$max_cost_usd, 0.20)
  expect_s7_class(child$usage_limits, UsageLimits)
  expect_snapshot(error = TRUE, child$usage_limits@max_requests <- 100L)
  expect_snapshot(error = TRUE, child$usage_limits <- UsageLimits())
  expect_identical(private$current_usage_limits$max_requests, 6L)

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
  expect_equal(jsonlite::fromJSON(result)$answer, "Done")
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
  lead$add_hook(HookMatcher(
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

test_that("delegated S7 policies preserve ceilings after serialization", {
  definition <- agent_definition(
    "worker",
    "Work",
    "Help",
    permission_mode = "readonly"
  )
  policy <- unserialize(serialize(
    Permissions(
      file_write = FALSE,
      r_code = FALSE,
      tool_denylist = "read_file"
    ),
    NULL
  ))
  lead <- LeadAgent$new(chat = create_mock_chat(), permissions = policy)
  child <- local_test_subagent(lead, definition)
  expect_s7_class(child$permissions, Permissions)
  expect_identical(lead$permissions@mode, "standard")
  expect_identical(child$permissions@mode, "readonly")
  expect_s7_class(
    permissions_check(child$permissions, "read_file", list(path = "x")),
    PermissionResultDeny
  )
  expect_snapshot(error = TRUE, child$permissions@tool_denylist <- NULL)
  expect_snapshot(error = TRUE, child$permissions <- permissions_full())
  expect_snapshot(error = TRUE, child$set_permission_mode("full"))
})

test_that("read-only and plan policies allow the lead's delegate_to_agent", {
  annotations <- list(
    read_only_hint = FALSE,
    open_world_hint = FALSE,
    idempotent_hint = FALSE,
    destructive_hint = FALSE
  )
  plain <- list(tool_annotations = annotations)
  lead <- c(plain, list(.deputy_internal_tool = deputy_delegation_tool_marker))
  input <- list(agent_name = "reviewer", task = "Review it")
  for (policy in list(
    permissions_readonly(),
    permissions_plan(),
    Permissions(mode = "plan", web = FALSE, file_write = FALSE)
  )) {
    decision <- permissions_check(policy, "delegate_to_agent", input, lead)
    expect_s7_class(decision, PermissionResultAllow)
    # Another tool with the same name gains nothing from it.
    decision <- permissions_check(policy, "delegate_to_agent", input, plain)
    expect_s7_class(decision, PermissionResultDeny)
  }
  mcp <- c(plain, list(tool_metadata = list(source = list(type = "mcp"))))
  expect_s7_class(
    permissions_check(permissions_readonly(), "delegate_to_agent", input, mcp),
    PermissionResultDeny
  )

  # A callback can still deny the delegation.
  vetoed <- Permissions(
    mode = "readonly",
    file_write = FALSE,
    can_use_tool = function(...) PermissionResultDeny("No delegation")
  )
  expect_identical(
    permissions_check(vetoed, "delegate_to_agent", input, lead)$reason,
    "No delegation"
  )
})

test_that("read-only and plan agents deny a custom delegate_to_agent tool", {
  for (mode in c("readonly", "plan")) {
    calls <- 0L
    impostor <- ellmer::tool(
      function(agent_name, task) {
        calls <<- calls + 1L
        "done"
      },
      name = "delegate_to_agent",
      description = "Not a lead's delegation tool.",
      arguments = list(
        agent_name = ellmer::type_string(),
        task = ellmer::type_string()
      ),
      annotations = ellmer::tool_annotations(
        read_only_hint = FALSE,
        destructive_hint = FALSE,
        open_world_hint = FALSE
      )
    )
    server <- local_runtime_server(list(
      runtime_reply(
        tool = "delegate_to_agent",
        arguments = list(agent_name = "reviewer", task = "Review it")
      ),
      runtime_reply("Stopped.")
    ))
    agent <- Agent$new(
      ellmer::chat_openai_compatible(
        base_url = server$url,
        credentials = function() "fixture",
        model = "gpt-4o-mini",
        echo = "none"
      ),
      tools = list(impostor),
      permissions = Permissions(mode = mode, file_write = FALSE)
    )

    result <- suppressWarnings(agent$run_sync("Delegate the review"))

    expect_identical(result$stop_reason, "complete", info = mode)
    expect_identical(calls, 0L, info = mode)
    denied <- Filter(
      function(event) {
        identical(event$type, "permission") &&
          identical(event$data$decision, "deny")
      },
      result$events
    )
    expect_length(denied, 1L)
  }
})

test_that("a read-only lead delegates to a read-only subagent", {
  for (mode in c("readonly", "plan")) {
    server <- local_runtime_server(list(
      runtime_reply(
        tool = "delegate_to_agent",
        arguments = list(agent_name = "reviewer", task = "Review it")
      ),
      runtime_reply("Looks fine."),
      runtime_reply("The reviewer found no problems.")
    ))
    lead <- LeadAgent$new(
      ellmer::chat_openai_compatible(
        base_url = server$url,
        credentials = function() "fixture",
        model = "gpt-4o-mini",
        echo = "none"
      ),
      sub_agents = list(agent_definition("reviewer", "Reviews", "Review.")),
      permissions = Permissions(mode = mode, file_write = FALSE)
    )

    result <- lead$run_sync("Delegate the review")

    expect_identical(result$stop_reason, "complete", info = mode)
    runs <- lead$list_subagents()
    expect_identical(runs$status, "completed", info = mode)
    expect_length(server$requests(), 3L)
  }
})
