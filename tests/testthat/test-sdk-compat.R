# Tests for Claude SDK compatibility facade.

test_that("claude_sdk_query persists and reuses a compat session id", {
  withr::local_tempdir(pattern = "deputy-sdk-store") -> store_dir

  options <- claude_sdk_options(
    chat = create_mock_chat(c("first response", "second response")),
    cwd = getwd(),
    session_store_dir = store_dir
  )
  client <- ClaudeSDKClient$new(options = options)

  first <- client$query("first task")
  second <- client$query("second task")

  expect_false(is.null(first$session_id))
  expect_equal(first$session_id, second$session_id)

  sessions <- client$list_sessions()
  expect_equal(nrow(sessions), 1)
  expect_equal(sessions$session_id[[1]], first$session_id)
  expect_true(sessions$snapshots[[1]] >= 2)
})

test_that("agent sdk aliases use the same compat runtime", {
  expect_s3_class(AgentSDKClient, "R6ClassGenerator")

  options <- agent_sdk_options(
    chat = create_mock_chat("alias response"),
    cwd = getwd()
  )
  expect_s3_class(options, "ClaudeSDKOptions")

  client <- AgentSDKClient$new(options = options)
  result <- client$query("alias task")

  expect_equal(result$response, "alias response")

  one_shot <- agent_sdk_query(
    "one shot",
    options = agent_sdk_options(
      chat = create_mock_chat("one shot response"),
      cwd = getwd()
    )
  )

  expect_equal(one_shot$response, "one shot response")
})

test_that("compat clients register both Agent and Task delegation tools", {
  options <- claude_sdk_options(
    chat = create_mock_chat("delegation ready"),
    cwd = getwd(),
    agents = list(agent_definition(
      name = "reviewer",
      description = "Reviews code",
      prompt = "Review the provided changes."
    ))
  )

  client <- ClaudeSDKClient$new(options = options)
  tool_names <- names(client$agent$chat$get_tools())

  expect_true("Agent" %in% tool_names)
  expect_true("Task" %in% tool_names)
})

test_that("compat resume restores turns, tools, permissions, and settings context", {
  withr::local_tempdir(pattern = "deputy-sdk-store") -> store_dir
  withr::local_tempdir(pattern = "deputy-sdk-project") -> project_dir

  dir.create(file.path(project_dir, ".claude", "commands"), recursive = TRUE)
  writeLines("Project memory block", file.path(project_dir, "CLAUDE.md"))
  writeLines(
    "Summarize the latest state.",
    file.path(project_dir, ".claude", "commands", "summarize.md")
  )
  writeLines(
    '{"allowedTools":["Read","LS"],"permissionPromptToolName":"AskUserQuestion"}',
    file.path(project_dir, ".claude", "settings.json")
  )

  client <- ClaudeSDKClient$new(claude_sdk_options(
    chat = create_mock_chat("initial response"),
    cwd = project_dir,
    session_store_dir = store_dir,
    setting_sources = "project"
  ))

  client$agent$chat$set_turns(list(
    create_mock_user_turn("hello"),
    create_mock_assistant_turn("world")
  ))
  result <- client$query("capture state")

  resumed <- ClaudeSDKClient$new(claude_sdk_options(
    chat = create_mock_chat("resumed"),
    cwd = project_dir,
    session_store_dir = store_dir
  ))
  resumed$resume(result$session_id)

  expect_equal(length(resumed$agent$turns()), 2)
  expect_match(resumed$agent$chat$get_system_prompt(), "Project memory block")
  expect_true("summarize" %in% names(resumed$agent$slash_commands()))
  expect_equal(
    resumed$agent$permissions$permission_prompt_tool_name,
    "AskUserQuestion"
  )
  expect_true("Read" %in% names(resumed$agent$chat$get_tools()))
})

test_that("forking a compat session creates a new session id", {
  withr::local_tempdir(pattern = "deputy-sdk-store") -> store_dir

  client <- ClaudeSDKClient$new(claude_sdk_options(
    chat = create_mock_chat("initial response"),
    cwd = getwd(),
    session_store_dir = store_dir
  ))
  result <- client$query("seed session")

  forked <- ClaudeSDKClient$new(claude_sdk_options(
    chat = create_mock_chat("forked response"),
    cwd = getwd(),
    session_store_dir = store_dir
  ))
  forked$resume(result$session_id, fork = TRUE)

  expect_false(identical(forked$agent$session_id(), result$session_id))

  sessions <- forked$list_sessions()
  expect_true(result$session_id %in% sessions$session_id)
  expect_true(forked$agent$session_id() %in% sessions$session_id)
})

test_that("resume_session_at selects the most recent eligible snapshot", {
  withr::local_tempdir(pattern = "deputy-sdk-store") -> store_dir

  agent <- Agent$new(chat = create_mock_chat())
  agent$configure_sdk_compat(list(
    persist_session = TRUE,
    session_store_dir = store_dir,
    session_id = "session-at"
  ))

  agent$chat$set_system_prompt("first snapshot")
  payload_one <- agent$.__enclos_env__$private$build_session_payload(
    extra_metadata = list(
      snapshot_at = as.POSIXct("2026-03-07 10:00:00", tz = "UTC"),
      session_id = "session-at"
    )
  )
  session_store_save_payload(payload_one, store_dir, "session-at")

  agent$chat$set_system_prompt("second snapshot")
  payload_two <- agent$.__enclos_env__$private$build_session_payload(
    extra_metadata = list(
      snapshot_at = as.POSIXct("2026-03-07 11:00:00", tz = "UTC"),
      session_id = "session-at"
    )
  )
  session_store_save_payload(payload_two, store_dir, "session-at")

  client <- ClaudeSDKClient$new(claude_sdk_options(
    chat = create_mock_chat(),
    cwd = getwd(),
    session_store_dir = store_dir
  ))
  client$resume("session-at", at = "2026-03-07 10:30:00")

  expect_equal(client$agent$chat$get_system_prompt(), "first snapshot")
})

test_that("resume_session_at errors when no eligible snapshot exists", {
  withr::local_tempdir(pattern = "deputy-sdk-store") -> store_dir

  agent <- Agent$new(chat = create_mock_chat())
  agent$configure_sdk_compat(list(
    persist_session = TRUE,
    session_store_dir = store_dir,
    session_id = "session-missing"
  ))

  payload <- agent$.__enclos_env__$private$build_session_payload(
    extra_metadata = list(
      snapshot_at = as.POSIXct("2026-03-07 11:00:00", tz = "UTC"),
      session_id = "session-missing"
    )
  )
  session_store_save_payload(payload, store_dir, "session-missing")

  client <- ClaudeSDKClient$new(claude_sdk_options(
    chat = create_mock_chat(),
    cwd = getwd(),
    session_store_dir = store_dir
  ))

  expect_error(
    client$resume("session-missing", at = "2026-03-07 10:00:00"),
    "No snapshot"
  )
})
