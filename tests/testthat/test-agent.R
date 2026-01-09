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

test_that("Agent load_session restores state", {
  mock_chat <- create_mock_chat()
  agent1 <- Agent$new(
    chat = mock_chat,
    system_prompt = "Test prompt"
  )

  withr::local_tempdir(pattern = "deputy-test") -> temp_dir
  session_file <- file.path(temp_dir, "session.rds")

  agent1$save_session(session_file)

  # Create new agent and load session
  mock_chat2 <- create_mock_chat()
  agent2 <- Agent$new(chat = mock_chat2)
  agent2$load_session(session_file)

  expect_equal(mock_chat2$get_system_prompt(), "Test prompt")
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
