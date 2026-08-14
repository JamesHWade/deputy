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

test_that("SDK file checkpoint option is operational", {
  root <- withr::local_tempdir(pattern = "deputy-sdk-checkpoint-")
  first_path <- file.path(root, "first.bin")
  oversized_path <- file.path(root, "oversized.bin")
  second_path <- file.path(root, "second.bin")
  writeBin(as.raw(1:2), first_path)
  writeBin(as.raw(1:3), oversized_path)
  writeBin(as.raw(3:4), second_path)
  client <- AgentSDKClient$new(agent_sdk_options(
    chat = create_mock_chat("ok"),
    cwd = root,
    tools = list(),
    persist_session = FALSE,
    enable_file_checkpointing = TRUE,
    file_checkpoint_max_file_bytes = 2,
    file_checkpoint_max_journal_bytes = 800
  ))

  checkpoint_id <- client$checkpoint("SDK checkpoint")
  store <- client$agent$.__enclos_env__$private$.file_checkpoints
  store$before_tool("Write", list(path = "first.bin"), "first")
  store$after_tool("first", success = TRUE)

  expect_error(
    store$before_tool("Write", list(path = "oversized.bin"), "oversized"),
    "max_file_bytes",
    class = "deputy_file_checkpoint_limit_error"
  )
  expect_error(
    store$before_tool("Write", list(path = "second.bin"), "second"),
    "max_journal_bytes",
    class = "deputy_file_checkpoint_limit_error"
  )

  expect_identical(
    client$list_checkpoints()$checkpoint_id,
    checkpoint_id
  )
  expect_identical(
    client$rewind_files(checkpoint_id)$restored_changes,
    1L
  )
})

test_that("new hook events and result fields are available", {
  expect_true(all(
    c(
      "PostToolUseFailure",
      "SubagentStart",
      "PermissionRequest",
      "ConfigChange"
    ) %in%
      HookEvent
  ))

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

test_that("SDK resume never imports serialized tool authority", {
  store <- session_store_memory()
  payload_tool <- ellmer::tool(
    fun = function(path) writeLines("payload", path),
    name = "payload_writer",
    description = "A serialized payload tool.",
    arguments = list(path = ellmer::type_string("Output path")),
    annotations = ellmer::tool_annotations(read_only_hint = TRUE)
  )
  source <- Agent$new(
    chat = create_mock_chat("source"),
    tools = list(payload_tool)
  )
  store$append(
    "untrusted-session",
    source$.__enclos_env__$private$build_session_payload()
  )

  client <- AgentSDKClient$new(claude_sdk_options(
    chat = create_mock_chat("receiver"),
    tools = character(),
    permission_mode = "plan",
    persist_session = FALSE,
    session_store = store,
    session_store_dir = tempfile("deputy-empty-store")
  ))
  client$resume("untrusted-session")

  expect_false("payload_writer" %in% names(client$agent$chat$get_tools()))
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

test_that("hook updated_input warns and leaves request arguments intact", {
  agent <- Agent$new(chat = create_mock_chat())

  agent$add_hook(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      HookResultPreToolUse(
        permission = "allow",
        updated_input = list(path = "rewritten.txt")
      )
    }
  ))

  request <- create_mock_tool_request(
    id = "call_write",
    name = "read_file",
    arguments = list(path = "original.txt")
  )

  expect_warning(
    agent$.__enclos_env__$private$on_tool_request(request),
    "tool input rewriting is not currently applied"
  )

  # The original request must remain unchanged - silently mutating only the
  # callback's local copy is the very bug this test guards against.
  expect_equal(request@arguments$path, "original.txt")
})

test_that("repeated hook additional_context is de-duplicated in the system prompt", {
  agent <- Agent$new(
    chat = create_mock_chat(),
    system_prompt = "Base."
  )

  agent$add_hook(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      HookResultPreToolUse(
        permission = "allow",
        additional_context = "Watch out for paths."
      )
    }
  ))

  request <- create_mock_tool_request(
    id = "call_read",
    name = "read_file",
    arguments = list(path = "a.txt")
  )

  agent$.__enclos_env__$private$on_tool_request(request)
  prompt_after_first <- agent$chat$get_system_prompt()

  # Fire many more times - identical content should not re-append.
  for (i in seq_len(5)) {
    agent$.__enclos_env__$private$on_tool_request(request)
  }
  prompt_after_repeats <- agent$chat$get_system_prompt()

  expect_identical(prompt_after_first, prompt_after_repeats)
  expect_equal(
    length(gregexpr(
      "# Hook Additional Context",
      prompt_after_repeats,
      fixed = TRUE
    )[[1]]),
    1L
  )
})

test_that("subagent failures are recorded in list_subagents", {
  # Build a throwing mock chat: its chat()/stream() raise on first turn,
  # and clone() returns the same throwing chat so the cloned sub-agent
  # also fails.
  make_throwing_chat <- function() {
    chat <- create_mock_chat()
    chat$chat <- function(...) stop("intentional failure")
    chat$stream <- function(...) stop("intentional failure")
    chat$clone <- function() make_throwing_chat()
    chat
  }
  throwing_chat <- make_throwing_chat()

  failing_def <- agent_definition(
    name = "failer",
    description = "Always fails",
    prompt = "Test prompt"
  )

  lead <- LeadAgent$new(
    chat = throwing_chat,
    sub_agents = list(failing_def)
  )

  delegate <- lead$.__enclos_env__$private$create_delegate_tool()

  err <- tryCatch(
    delegate(agent_name = "failer", task = "do thing"),
    ellmer_tool_reject = function(e) e,
    error = function(e) e
  )
  # Either ellmer_tool_reject was raised or some condition propagated.
  expect_true(inherits(err, "condition"))

  runs <- lead$list_subagents()
  expect_equal(nrow(runs), 1L)
  expect_equal(runs$status, "failed")
  expect_match(runs$error, "intentional failure")
})

test_that("claude_sdk_options validates numeric and character argument types", {
  expect_error(
    claude_sdk_options(max_turns = "ten"),
    "max_turns"
  )
  expect_error(
    claude_sdk_options(max_cost_usd = -1),
    "max_cost_usd"
  )
  expect_error(
    claude_sdk_options(skills = 42),
    "skills"
  )
  expect_error(
    claude_sdk_options(allowed_tools = list("Read")),
    "allowed_tools"
  )
  expect_error(
    claude_sdk_options(enable_file_checkpointing = "yes"),
    "enable_file_checkpointing"
  )
  expect_error(
    claude_sdk_options(file_checkpoint_max_file_bytes = Inf),
    class = "deputy_file_checkpoint_error"
  )
})

test_that("claude_sdk_options exposes bounded checkpoint storage", {
  options <- claude_sdk_options(
    file_checkpoint_max_file_bytes = 1024,
    file_checkpoint_max_journal_bytes = 4096
  )

  expect_identical(options$file_checkpoint_max_file_bytes, 1024)
  expect_identical(options$file_checkpoint_max_journal_bytes, 4096)
})

test_that("max_turns NULL remains an operational unlimited option", {
  options <- claude_sdk_options(
    chat = create_mock_chat("done"),
    max_turns = NULL,
    persist_session = FALSE
  )

  expect_null(options$max_turns)
  client <- AgentSDKClient$new(options)
  expect_identical(client$query("finish")$response, "done")
})

test_that("claude_sdk_options stores SDK-shape options it does not yet apply", {
  # The values are kept on the returned object so callers can introspect them.
  opts <- suppressWarnings(claude_sdk_options(sandbox = "strict"))
  expect_equal(opts$sandbox, "strict")
})

test_that("compat_load_explicit_skills warns on unresolved skill names", {
  agent <- Agent$new(chat = create_mock_chat())
  options <- list(skills = c("does-not-exist", "/no/such/path"))
  settings <- list(skills = list())

  expect_warning(
    deputy:::compat_load_explicit_skills(agent, options, settings),
    "Could not resolve"
  )
})
