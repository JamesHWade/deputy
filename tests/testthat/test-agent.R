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
    "immutable after construction"
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

  expect_identical(agent$chat, mock_chat)
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

test_that("Agent provider reports a model for a provider without a model property", {
  chat <- ellmer::chat_openai(
    credentials = function() "test-key",
    model = "gpt-4o-mini"
  )
  skip_if_not(is.null(attr(chat$get_provider(), "model")))
  agent <- Agent$new(chat = chat)

  provider <- agent$provider()

  expect_equal(provider$name, "OpenAI")
  expect_equal(provider$model, "gpt-4o-mini")
})

test_that("Agent provider falls back to unknown when the model cannot be read", {
  mock_chat <- create_mock_chat()
  mock_chat$get_provider <- function() list(name = "mock")
  mock_chat$get_model <- function() stop("no model available")
  agent <- Agent$new(chat = mock_chat)

  provider <- agent$provider()

  expect_equal(provider$name, "mock")
  expect_equal(provider$model, "unknown")
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
  expect_true("turns" %in% names(session))
  expect_true("permissions" %in% names(session))
  expect_true("metadata" %in% names(session))
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
    permissions = permissions_readonly(max_turns = 10),
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

test_that("Agent load_session restores tools only with explicit trust", {
  source_tool <- ellmer::tool(
    fun = function() "source",
    name = "source_tool",
    description = "Serialized source tool."
  )
  receiver_tool <- ellmer::tool(
    fun = function() "receiver",
    name = "receiver_tool",
    description = "Constructor-owned receiver tool."
  )
  root <- withr::local_tempdir(pattern = "deputy-session-tools-")
  session_file <- file.path(root, "session.rds")
  source <- Agent$new(
    chat = create_mock_chat(),
    tools = list(source_tool),
    working_dir = root
  )
  suppressWarnings(suppressMessages(source$save_session(session_file)))

  default_chat <- create_mock_chat()
  default_receiver <- Agent$new(
    chat = default_chat,
    tools = list(receiver_tool),
    working_dir = root
  )
  suppressWarnings(suppressMessages(
    default_receiver$load_session(session_file)
  ))
  expect_setequal(names(default_chat$get_tools()), "receiver_tool")

  trusted_chat <- create_mock_chat()
  trusted_receiver <- Agent$new(
    chat = trusted_chat,
    tools = list(receiver_tool),
    working_dir = root
  )
  suppressWarnings(suppressMessages(
    trusted_receiver$load_session(session_file, restore_tools = TRUE)
  ))
  expect_setequal(
    names(trusted_chat$get_tools()),
    c("receiver_tool", "source_tool")
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
      turns = list(create_mock_user_turn("new turn")),
      system_prompt = "new prompt",
      appended_hook_context_hashes = new.env(parent = emptyenv()),
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

  saveRDS(
    list(
      turns = list(create_mock_user_turn("unsafe session")),
      system_prompt = "unsafe prompt",
      appended_hook_context_hashes = character(),
      metadata = list(session_id = "../outside")
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

  expect_identical(result, agent)
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

  # Create mock turns (text inside the list, not as attribute)
  mock_turns <- list(
    structure(
      list(text = "User msg", contents = list()),
      class = c("UserTurn", "Turn")
    ),
    structure(
      list(text = "Asst msg", contents = list()),
      class = c("AssistantTurn", "Turn")
    )
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

test_that("extract_tool_request_data handles list-style request", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Create a list-style request (not S7)
  list_request <- list(
    name = "test_tool",
    arguments = list(arg1 = "value1"),
    tool = list(annotations = list(read_only_hint = TRUE))
  )

  result <- NULL
  expect_warning(
    result <- agent$.__enclos_env__$private$extract_tool_request_data(
      list_request
    ),
    "not a ContentToolRequest"
  )

  expect_equal(result$tool_name, "test_tool")
  expect_equal(result$tool_input, list(arg1 = "value1"))
  expect_equal(result$tool_annotations, list(read_only_hint = TRUE))
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

test_that("extract_tool_result_data handles list-style result", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Create a list-style result (not S7)
  list_result <- list(
    value = "tool output",
    error = NULL,
    request = list(name = "test_tool")
  )

  result <- NULL
  expect_warning(
    result <- agent$.__enclos_env__$private$extract_tool_result_data(
      list_result
    ),
    "not a ContentToolResult"
  )

  expect_equal(result$tool_name, "test_tool")
  expect_equal(result$tool_result, "tool output")
  expect_null(result$tool_error)
})

test_that("extract_tool_result_data handles result with error", {
  mock_chat <- create_mock_chat()
  agent <- Agent$new(chat = mock_chat)

  # Create a list-style result with error
  list_result <- list(
    value = NULL,
    error = "Something went wrong",
    request = list(name = "failing_tool")
  )

  result <- NULL
  expect_warning(
    result <- agent$.__enclos_env__$private$extract_tool_result_data(
      list_result
    ),
    "not a ContentToolResult"
  )

  expect_equal(result$tool_name, "failing_tool")
  expect_null(result$tool_result)
  expect_equal(result$tool_error, "Something went wrong")
})
