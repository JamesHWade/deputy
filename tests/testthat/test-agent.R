# Tests for Agent class
# Note: create_mock_chat is defined in helper-mocks.R

test_that("Agent initializes correctly", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  expect_s3_class(agent, "Agent")
  expect_s3_class(agent$permissions, "Permissions")
  expect_s3_class(agent$hooks, "HookRegistry")
  expect_equal(agent$working_dir, getwd())
})

test_that("Agent initializes with custom permissions", {
  mock_chat <- create_mock_chat()
  perms <- permissions_readonly()
  agent <- Agent$new(chat = mock_chat, permissions = perms)

  expect_equal(agent$permissions$mode, "readonly")
})

test_that("Agent core fields are immutable after construction", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  original_permissions <- agent$permissions
  original_hooks <- agent$hooks
  original_working_dir <- agent$working_dir

  expect_error(
    agent$chat <- create_mock_chat(),
    "locked binding"
  )
  expect_error(
    agent$permissions <- permissions_readonly(),
    "immutable after construction"
  )
  expect_error(
    agent$working_dir <- tempdir(),
    "immutable after construction"
  )
  expect_error(
    agent$hooks <- HookRegistry$new(),
    "immutable after construction"
  )

  expect_true(is.function(agent$chat))
  expect_identical(agent$permissions, original_permissions)
  expect_identical(agent$hooks, original_hooks)
  expect_identical(agent$working_dir, original_working_dir)
})

test_that("Agent initializes with tools", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    tools = tools_file()
  )

  tools <- mock_chat$get_tools()
  expect_true(length(tools) >= 3)
  expect_true("read_file" %in% names(tools))
})

test_that("Agent initializes with system prompt", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(
    chat = mock_chat,
    system_prompt = "You are a helpful assistant."
  )

  expect_equal(mock_chat$get_system_prompt(), "You are a helpful assistant.")
})

test_that("Agent register_tool works", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  agent$register_tool(tool_read_file)
  tools <- mock_chat$get_tools()
  expect_true("read_file" %in% names(tools))
})

test_that("Agent register_tools works", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  agent$register_tools(tools_file())
  tools <- mock_chat$get_tools()
  expect_true(length(tools) >= 3)
})

test_that("Agent add_hook works", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  expect_equal(agent$hooks$count(), 0)

  agent$add_hook(HookMatcher$new(
    event = "PreToolUse",
    callback = function(...) NULL
  ))

  expect_equal(agent$hooks$count(), 1)
})

test_that("Agent add_hook rejects non-HookMatcher", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  expect_error(
    agent$add_hook("not a hook"),
    "HookMatcher"
  )
})

test_that("Agent cost returns correct structure", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  cost <- agent$cost()

  expect_true("input" %in% names(cost))
  expect_true("output" %in% names(cost))
  expect_true("cached" %in% names(cost))
  expect_true("total" %in% names(cost))
})

test_that("Agent provider returns correct structure", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  provider <- agent$provider()

  expect_equal(provider$name, "mock")
  expect_equal(provider$model, "test-model")
})

test_that("Agent provider surfaces model access errors", {
  mock_chat <- create_mock_chat()
  mock_chat$get_model <- function() stop("no model available")
  agent <- Agent$new(chat = mock_chat)

  expect_error(agent$provider(), "no model available")
})

test_that("Agent turns returns list", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  turns <- agent$turns()
  expect_type(turns, "list")
})

test_that("Agent validates chat argument", {
  expect_error(
    Agent$new(chat = "not a chat"),
    "ellmer Chat"
  )
})

test_that("Agent save_session creates file", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  withr::local_tempdir(pattern = "deputy-test") -> temp_dir
  session_file <- file.path(temp_dir, "session.rds")

  agent$save_session(session_file)

  expect_true(file.exists(session_file))

  # Check session contents
  session <- readRDS(session_file)
  expect_identical(session$schema_version, 1L)
  expect_named(
    session,
    c(
      "schema_version",
      "turns",
      "system_prompt",
      "compaction_summary",
      "tool_result_envelopes",
      "run_context",
      "appended_hook_context_hashes",
      "file_checkpoint_state",
      "metadata"
    )
  )
})

test_that("Agent load_session restores chat state but preserves authority", {
  source_chat <- create_mock_chat()
  withr::local_tempdir(pattern = "deputy-test") -> temp_dir
  saved_working_dir <- file.path(temp_dir, "saved-session-dir")
  receiver_working_dir <- file.path(temp_dir, "receiver-dir")
  dir.create(saved_working_dir)
  dir.create(receiver_working_dir)
  saved_turns <- list(
    create_mock_user_turn("Remember this"),
    create_mock_assistant_turn("Conversation restored")
  )
  source_chat$set_turns(saved_turns)
  source <- Agent$new(
    chat = source_chat,
    system_prompt = "Test prompt",
    permissions = permissions_readonly(),
    working_dir = saved_working_dir
  )
  session_file <- file.path(temp_dir, "session.rds")
  suppressWarnings(suppressMessages(source$save_session(session_file)))

  receiver_chat <- create_mock_chat()
  receiver_permissions <- permissions_standard(receiver_working_dir)
  receiver <- Agent$new(
    chat = receiver_chat,
    permissions = receiver_permissions,
    working_dir = receiver_working_dir
  )
  configured_working_dir <- receiver$working_dir
  suppressMessages(receiver$load_session(session_file))

  expect_equal(receiver_chat$get_system_prompt(), "Test prompt")
  expect_equal(receiver_chat$get_turns(), saved_turns)
  expect_identical(receiver$permissions, receiver_permissions)
  expect_identical(receiver$working_dir, configured_working_dir)
})

test_that("Agent sessions preserve cumulative compaction context", {
  root <- withr::local_tempdir(pattern = "deputy-session-compaction-")
  source_chat <- create_mock_chat()
  source_chat$set_turns(list(
    create_mock_user_turn("Original question"),
    create_mock_assistant_turn("Original answer"),
    create_mock_user_turn("Follow-up")
  ))
  source <- Agent$new(chat = source_chat)
  source$compact(keep_last = 1L, summary = "Saved cumulative summary")
  session_file <- file.path(root, "session.rds")
  suppressMessages(source$save_session(session_file))

  probe <- new.env(parent = emptyenv())
  receiver <- Agent$new(
    chat = create_compaction_mock_chat(
      responses = list("Merged summary"),
      probe = probe
    )
  )
  suppressMessages(receiver$load_session(session_file))
  receiver$.__enclos_env__$private$generate_compaction_summary(list(
    create_mock_user_turn("New question"),
    create_mock_assistant_turn("New answer")
  ))

  expect_match(
    probe$summary_call$prompt,
    "Existing summary from earlier compactions:\nSaved cumulative summary",
    fixed = TRUE
  )
})

test_that("Agent load_session validates payload before mutating conversation", {
  root <- withr::local_tempdir(pattern = "deputy-session-atomic-")
  session_file <- file.path(root, "malformed.rds")
  old_turns <- list(create_mock_user_turn("old turn"))
  chat <- create_mock_chat()
  chat$set_turns(old_turns)
  chat$set_system_prompt("old prompt")
  agent <- Agent$new(chat = chat, working_dir = root)

  saveRDS(
    list(
      schema_version = 1L,
      turns = list(create_mock_user_turn("new turn")),
      system_prompt = "new prompt",
      compaction_summary = NULL,
      tool_result_envelopes = list(),
      run_context = list(),
      appended_hook_context_hashes = new.env(parent = emptyenv()),
      file_checkpoint_state = NULL,
      metadata = list(session_id = "malformed-session")
    ),
    session_file
  )

  expect_error(
    suppressMessages(agent$load_session(session_file)),
    class = "deputy_session_load"
  )
  expect_equal(chat$get_turns(), old_turns)
  expect_identical(chat$get_system_prompt(), "old prompt")

  saveRDS(
    list(
      schema_version = 0L,
      turns = list(create_mock_user_turn("unsafe session")),
      system_prompt = "unsafe prompt",
      run_context = list(),
      appended_hook_context_hashes = character(),
      file_checkpoint_state = NULL,
      metadata = list()
    ),
    session_file
  )
  expect_error(
    suppressMessages(agent$load_session(session_file)),
    class = "deputy_session_load"
  )
  expect_equal(chat$get_turns(), old_turns)
  expect_identical(chat$get_system_prompt(), "old prompt")
})

test_that("Agent load_session validates file exists", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  expect_error(
    agent$load_session("/nonexistent/file.rds"),
    "not found"
  )
})

test_that("Agent print works", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  output <- capture.output(print(agent))

  expect_true(any(grepl("Agent", output)))
  expect_true(any(grepl("provider", output)))
  expect_true(any(grepl("mock", output)))
})

# Compaction tests
test_that("compact method exists", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  expect_true("compact" %in% names(agent))
  expect_true(is.function(agent$compact))
})

test_that("compact does nothing when not enough turns", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # With no turns, compact should do nothing
  output <- capture.output(
    result <- agent$compact(keep_last = 4),
    type = "message"
  )

  expect_s3_class(result, "DeputyCompaction")
  expect_identical(result$method, "none")
})

test_that("compact accepts custom summary", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Add mock turns
  mock_turns <- list(
    structure(
      list(text = "Hello", contents = list()),
      class = c("UserTurn", "Turn")
    ),
    structure(
      list(text = "Hi", contents = list()),
      class = c("AssistantTurn", "Turn")
    ),
    structure(
      list(text = "Q1", contents = list()),
      class = c("UserTurn", "Turn")
    ),
    structure(
      list(text = "A1", contents = list()),
      class = c("AssistantTurn", "Turn")
    ),
    structure(
      list(text = "Q2", contents = list()),
      class = c("UserTurn", "Turn")
    ),
    structure(
      list(text = "A2", contents = list()),
      class = c("AssistantTurn", "Turn")
    )
  )
  mock_chat$set_turns(mock_turns)

  # Compact with custom summary
  suppressMessages({
    agent$compact(keep_last = 2, summary = "Custom summary here")
  })

  # Verify system prompt was updated with custom summary
  prompt <- mock_chat$get_system_prompt()
  expect_true(grepl("Custom summary here", prompt))
})

test_that("generate_fallback_summary creates text summary", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  mock_turns <- list(
    create_mock_user_turn("User msg"),
    create_mock_assistant_turn("Asst msg")
  )

  # Access private method
  fallback <- agent$.__enclos_env__$private$generate_fallback_summary(
    mock_turns
  )

  expect_true(is.character(fallback))
  expect_true(grepl("Compacted", fallback))
  expect_true(grepl("2 earlier turns", fallback))
  expect_true(grepl("User msg", fallback))
  expect_true(grepl("Asst msg", fallback))
})

test_that("compaction summary clone is isolated, callback-free, and silent", {
  request_calls <- 0L
  result_calls <- 0L
  probe <- new.env(parent = emptyenv())
  provider <- create_mock_provider(
    name = "private-gateway",
    model = "private-model",
    base_url = "https://gateway.invalid"
  )
  mock_chat <- create_compaction_mock_chat(
    responses = list("A summary."),
    provider = provider,
    request_callbacks = list(function(request) {
      request_calls <<- request_calls + 1L
    }),
    result_callbacks = list(function(result) {
      result_calls <<- result_calls + 1L
    }),
    simulate_tool_activity = TRUE,
    probe = probe
  )
  run_context <- list(
    product = "tempest",
    research_run_id = "research-123",
    stage = "expert-research"
  )
  agent <- Agent$new(
    chat = mock_chat,
    tools = list(tool_read_file),
    system_prompt = "KEEP ME",
    run_context = run_context,
    agent_id = "agent-compaction",
    session_id = "session-compaction"
  )
  original_turns <- list(
    create_mock_user_turn("Q"),
    create_mock_assistant_turn("A")
  )
  mock_chat$set_turns(original_turns)
  original_callback_counts <- mock_chat$callback_counts()
  original_run_context <- agent$run_context
  original_agent_id <- agent$agent_id
  original_session_id <- agent$session_id()

  summary <- agent$.__enclos_env__$private$generate_compaction_summary(
    original_turns
  )

  expect_equal(summary$summary, "A summary.")
  expect_identical(summary$method, "llm")
  expect_s3_class(summary$usage, "AgentUsage")
  expect_identical(probe$clone_calls, 1L)
  expect_identical(probe$clone_deep, TRUE)
  expect_length(probe$summary_call$turns, 0L)
  expect_null(probe$summary_call$system_prompt)
  expect_length(probe$summary_call$tools, 0L)
  expect_equal(
    probe$summary_call$callback_counts,
    c(request = 0L, result = 0L)
  )
  expect_identical(probe$summary_call$echo, "none")
  expect_identical(probe$summary_call$provider, provider)
  expect_equal(mock_chat$get_system_prompt(), "KEEP ME")
  expect_identical(mock_chat$get_turns(), original_turns)
  expect_named(mock_chat$get_tools(), "read_file")
  expect_equal(mock_chat$callback_counts(), original_callback_counts)
  expect_identical(agent$run_context, original_run_context)
  expect_identical(agent$agent_id, original_agent_id)
  expect_identical(agent$session_id(), original_session_id)
  expect_identical(request_calls, 0L)
  expect_identical(result_calls, 0L)
})

test_that("compaction does not select a new provider constructor", {
  mock_chat <- create_mock_chat(responses = list("A summary."))
  agent <- Agent$new(chat = mock_chat)
  compaction_code <- paste(
    c(
      deparse(body(clone_compaction_chat)),
      deparse(body(
        agent$.__enclos_env__$private$generate_compaction_summary
      ))
    ),
    collapse = "\n"
  )

  expect_no_match(compaction_code, "ellmer::chat_[[:alnum:]_]+")
})

test_that("compaction preserves run context and session identity", {
  mock_chat <- create_compaction_mock_chat(responses = list("A summary."))
  run_context <- list(product = "tempest", research_run_id = "research-123")
  agent <- Agent$new(
    chat = mock_chat,
    run_context = run_context,
    agent_id = "agent-compaction",
    session_id = "session-compaction"
  )
  mock_chat$set_turns(list(
    create_mock_user_turn("Q1"),
    create_mock_assistant_turn("A1"),
    create_mock_user_turn("Q2")
  ))
  original_callback_counts <- mock_chat$callback_counts()

  suppressMessages(agent$compact(keep_last = 1L))

  expect_identical(agent$run_context, run_context)
  expect_identical(agent$agent_id, "agent-compaction")
  expect_identical(agent$session_id(), "session-compaction")
  expect_equal(mock_chat$callback_counts(), original_callback_counts)
})

test_that("compaction falls back only after clone or summary runtime failure", {
  turns <- list(
    create_mock_user_turn("User msg"),
    create_mock_assistant_turn("Assistant msg")
  )
  clone_failure_chat <- create_mock_chat()
  clone_failure_agent <- Agent$new(chat = clone_failure_chat)
  clone_failure_chat$clone <- function(deep = FALSE) {
    stop("clone failed")
  }
  runtime_failure_agent <- Agent$new(
    chat = create_compaction_mock_chat(chat_error = "provider failed")
  )

  clone_fallback <- suppressWarnings(suppressMessages(
    clone_failure_agent$.__enclos_env__$private$generate_compaction_summary(
      turns,
      fallback = "text"
    )
  ))
  runtime_fallback <- suppressWarnings(suppressMessages(
    runtime_failure_agent$.__enclos_env__$private$generate_compaction_summary(
      turns,
      fallback = "text"
    )
  ))

  expect_match(clone_fallback$summary, "Compacted 2 earlier turns")
  expect_match(runtime_fallback$summary, "Compacted 2 earlier turns")
  expect_identical(clone_fallback$method, "text")
  expect_identical(runtime_fallback$method, "text")
})

# Tool data extraction tests
test_that("extract_tool_request_data handles NULL request", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Access private method - should warn and return defaults
  result <- NULL
  expect_warning(
    result <- agent$.__enclos_env__$private$extract_tool_request_data(NULL),
    "NULL request"
  )

  expect_equal(result$tool_name, "unknown")
  expect_equal(result$tool_input, list())
  expect_null(result$tool_annotations)
})

test_that("extract_tool_result_data handles NULL result", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Access private method - should warn and return defaults
  result <- NULL
  expect_warning(
    result <- agent$.__enclos_env__$private$extract_tool_result_data(NULL),
    "NULL result"
  )

  expect_equal(result$tool_name, "unknown")
  expect_null(result$tool_result)
  expect_equal(result$tool_error, "NULL result received")
})

test_that("provider tool call IDs distinguish absence from invalid values", {
  agent <- Agent$new(chat = create_mock_chat())

  absent_request <- create_mock_tool_request()
  attr(absent_request, "id") <- NULL
  expect_no_warning(
    absent <- agent$.__enclos_env__$private$extract_tool_request_data(
      absent_request
    )
  )
  expect_null(absent$provider_tool_call_id)

  invalid_request <- create_mock_tool_request()
  attr(invalid_request, "id") <- list("call_123")
  invalid_result <- ellmer::ContentToolResult(
    value = "ok",
    request = invalid_request
  )

  request_data <- result_data <- NULL
  expect_snapshot({
    request_data <- agent$.__enclos_env__$private$extract_tool_request_data(
      invalid_request
    )
    result_data <- agent$.__enclos_env__$private$extract_tool_result_data(
      invalid_result
    )
  })
  expect_null(request_data$provider_tool_call_id)
  expect_null(result_data$provider_tool_call_id)

  unreadable_request <- new.env(parent = emptyenv())
  unreadable_id <- NULL
  expect_snapshot(
    unreadable_id <- read_provider_tool_call_id(
      function() unreadable_request@id,
      source = "request",
      object = unreadable_request
    )
  )
  expect_null(unreadable_id)
})
