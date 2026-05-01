# Tests for newer Claude Agent SDK parity surfaces.

test_that("new SDK permission modes are accepted", {
  expect_true(all(c("dontAsk", "auto") %in% PermissionMode))

  auto <- Permissions$new(mode = "auto")
  expect_equal(auto$mode, "auto")

  dont_ask <- Permissions$new(
    mode = "dontAsk",
    tool_allowlist = "Read",
    permission_prompt_tool_name = "AskUserQuestion"
  )
  result <- dont_ask$check("AskUserQuestion", list(), list())
  expect_s3_class(result, "PermissionResultDeny")
})

test_that("agent permission mode can change dynamically", {
  agent <- Agent$new(chat = create_mock_chat())
  changes <- list()

  agent$add_hook(HookMatcher$new(
    event = "ConfigChange",
    timeout = 0,
    callback = function(key, old_value, new_value, context) {
      changes[[length(changes) + 1L]] <<- list(
        key = key,
        old_value = old_value,
        new_value = new_value,
        working_dir = context$working_dir
      )
      NULL
    }
  ))

  agent$set_permission_mode("plan")

  expect_equal(agent$get_permission_mode(), "plan")
  expect_equal(changes[[1]]$key, "permission_mode")
  expect_equal(changes[[1]]$old_value, "default")
  expect_equal(changes[[1]]$new_value, "plan")
})

test_that("compat options preserve and apply newer SDK option surface", {
  callback_called <- FALSE
  options <- claude_sdk_options(
    chat = create_mock_chat("ok"),
    cwd = getwd(),
    tools = c("Read", "LS"),
    permission_mode = "auto",
    can_use_tool = function(tool_name, tool_input, context) {
      callback_called <<- TRUE
      PermissionResultAllow()
    },
    managed_settings = list(
      includePartialMessages = FALSE,
      outputFormat = "json"
    ),
    task_budget = 3,
    sandbox = list(network = list(allowedDomains = "example.com")),
    plugins = list("example-plugin"),
    title = "Parity session"
  )

  client <- ClaudeSDKClient$new(options)

  expect_equal(client$options$max_turns, 3L)
  expect_equal(client$options$title, "Parity session")
  expect_equal(client$agent$permissions$mode, "auto")
  expect_setequal(names(client$agent$chat$get_tools()), c("Read", "LS"))

  client$agent$permissions$check("custom_tool", list(), list())
  expect_true(callback_called)
})

test_that("compat tools can be explicitly disabled with an empty list", {
  client <- ClaudeSDKClient$new(claude_sdk_options(
    chat = create_mock_chat("ok"),
    cwd = getwd(),
    tools = list()
  ))

  expect_length(client$agent$chat$get_tools(), 0)
})

test_that("new hook events and result fields are available", {
  expect_true(all(c(
    "PostToolUseFailure",
    "SubagentStart",
    "PermissionRequest",
    "ConfigChange"
  ) %in% HookEvent))

  pre <- HookResultPreToolUse(
    permission = "allow",
    updated_input = list(path = "new.txt"),
    additional_context = "Use the revised path."
  )
  expect_equal(pre$updated_input$path, "new.txt")
  expect_equal(pre$additional_context, "Use the revised path.")

  post <- HookResultPostToolUse(
    continue = FALSE,
    updated_tool_output = "replacement",
    suppress_output = TRUE,
    stop_reason = "hook_stop"
  )
  expect_false(post$continue)
  expect_equal(post$updated_tool_output, "replacement")
  expect_true(post$suppress_output)
  expect_equal(post$stop_reason, "hook_stop")
})

test_that("PermissionRequest hooks can allow denied tool requests", {
  agent <- Agent$new(
    chat = create_mock_chat(),
    permissions = permissions_readonly()
  )
  called <- FALSE

  agent$add_hook(HookMatcher$new(
    event = "PermissionRequest",
    timeout = 0,
    callback = function(tool_name, tool_input, permission_result, context) {
      called <<- TRUE
      expect_equal(tool_name, "write_file")
      expect_s3_class(permission_result, "PermissionResultDeny")
      PermissionResultAllow()
    }
  ))

  request <- create_mock_tool_request(
    id = "call_write",
    name = "write_file",
    arguments = list(path = "out.txt", content = "hello")
  )

  expect_no_error(agent$.__enclos_env__$private$on_tool_request(request))
  expect_true(called)
})

test_that("PostToolUseFailure fires for failed tool results", {
  agent <- Agent$new(chat = create_mock_chat())
  failure_seen <- FALSE

  agent$add_hook(HookMatcher$new(
    event = "PostToolUseFailure",
    timeout = 0,
    callback = function(tool_name, tool_result, tool_error, context) {
      failure_seen <<- TRUE
      expect_equal(tool_name, "failing_tool")
      expect_equal(tool_error, "boom")
      expect_equal(context$tool_use_id, "call_fail")
      HookResultPostToolUse()
    }
  ))

  expect_warning(
    agent$.__enclos_env__$private$on_tool_result(list(
      value = NULL,
      error = "boom",
      request = list(name = "failing_tool", id = "call_fail")
    )),
    "not a ContentToolResult"
  )
  expect_true(failure_seen)
})

test_that("expanded AgentDefinition fields are stored and applied", {
  def <- agent_definition(
    name = "reviewer",
    description = "Reviews code",
    prompt = "Review carefully.",
    tools = list(sdk_tool_read, sdk_tool_write),
    disallowed_tools = "Write",
    memory = "Prefer concise findings.",
    initial_prompt = "Start with risks.",
    max_turns = 2,
    permission_mode = "plan",
    mcp_servers = "github",
    background = TRUE,
    effort = "medium"
  )

  expect_equal(def$disallowed_tools, "Write")
  expect_equal(def$memory, "Prefer concise findings.")
  expect_equal(def$initial_prompt, "Start with risks.")
  expect_equal(def$max_turns, 2L)
  expect_equal(def$permission_mode, "plan")
  expect_true(def$background)
  expect_equal(def$effort, "medium")
})

test_that("memory session store adapter supports append load list and delete", {
  store <- session_store_memory()
  withr::local_tempdir(pattern = "deputy-sdk-store") -> store_dir

  client <- ClaudeSDKClient$new(claude_sdk_options(
    chat = create_mock_chat("stored"),
    cwd = getwd(),
    session_store_dir = store_dir,
    session_store = store
  ))
  result <- client$query("capture")

  expect_true(result$session_id %in% store$list_sessions())
  expect_true(nrow(client$list_session_summaries()) >= 1)

  resumed <- ClaudeSDKClient$new(claude_sdk_options(
    chat = create_mock_chat("resumed"),
    cwd = getwd(),
    session_store_dir = tempfile("empty-store"),
    session_store = store
  ))
  expect_no_error(resumed$resume(result$session_id))

  client$delete_session(result$session_id)
  expect_false(result$session_id %in% store$list_sessions())
})

test_that("MCP status is available even before MCP load attempts", {
  agent <- Agent$new(chat = create_mock_chat())
  status <- agent$mcp_status()

  expect_s3_class(status, "data.frame")
  expect_setequal(
    names(status),
    c("status", "config", "servers", "tools", "loaded_at", "error")
  )
})
