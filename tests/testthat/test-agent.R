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
    structure(list(text = "Hello", contents = list()), class = c("UserTurn", "Turn")),
    structure(list(text = "Hi", contents = list()), class = c("AssistantTurn", "Turn")),
    structure(list(text = "Q1", contents = list()), class = c("UserTurn", "Turn")),
    structure(list(text = "A1", contents = list()), class = c("AssistantTurn", "Turn")),
    structure(list(text = "Q2", contents = list()), class = c("UserTurn", "Turn")),
    structure(list(text = "A2", contents = list()), class = c("AssistantTurn", "Turn"))
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
    structure(list(text = "User msg", contents = list()), class = c("UserTurn", "Turn")),
    structure(list(text = "Asst msg", contents = list()), class = c("AssistantTurn", "Turn"))
  )

  # Access private method
  fallback <- agent$.__enclos_env__$private$generate_fallback_summary(mock_turns)

  expect_true(is.character(fallback))
  expect_true(grepl("Compacted", fallback))
  expect_true(grepl("2 earlier turns", fallback))
  expect_true(grepl("User msg", fallback))
  expect_true(grepl("Asst msg", fallback))
})
