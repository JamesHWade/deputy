test_that("Agent checkpoints journal successful mutating tool calls", {
  root <- withr::local_tempdir(pattern = "deputy-agent-checkpoint-")
  path <- file.path(root, "note.txt")
  writeLines("original", path)
  mock <- create_checkpoint_callback_chat()
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(tool_write_file),
    permissions = permissions_standard(root),
    enable_file_checkpointing = TRUE,
    working_dir = root
  )
  checkpoint_id <- agent$checkpoint("before write")
  request <- ellmer::ContentToolRequest(
    id = "write-1",
    name = "write_file",
    arguments = list(path = path, content = "changed"),
    tool = tool_write_file
  )
  mock$request_callback()(request)
  writeLines("changed", path)
  mock$result_callback()(ellmer::ContentToolResult(
    value = path,
    request = request
  ))

  expect_identical(readLines(path), "changed")
  expect_identical(agent$list_checkpoints()$checkpoint_id, checkpoint_id)
  rewind <- agent$rewind_files(checkpoint_id)
  expect_identical(readLines(path), "original")
  expect_identical(rewind$restored_changes, 1L)
})

test_that("file checkpoint journals survive session serialization", {
  root <- withr::local_tempdir(pattern = "deputy-agent-checkpoint-")
  path <- file.path(root, "persisted.txt")
  session_path <- file.path(root, "session.rds")
  writeLines("before", path)
  mock <- create_checkpoint_callback_chat()
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(tool_write_file),
    permissions = permissions_standard(root),
    enable_file_checkpointing = TRUE,
    working_dir = root
  )
  checkpoint_id <- agent$checkpoint("persisted")
  request <- ellmer::ContentToolRequest(
    id = "write-persisted",
    name = "write_file",
    arguments = list(path = path, content = "after"),
    tool = tool_write_file
  )
  mock$request_callback()(request)
  writeLines("after", path)
  mock$result_callback()(ellmer::ContentToolResult(
    value = path,
    request = request
  ))
  suppressMessages(agent$save_session(session_path))

  restored <- Agent$new(
    chat = create_mock_chat("restored"),
    enable_file_checkpointing = TRUE,
    working_dir = root
  )
  suppressWarnings(suppressMessages(
    restored$load_session(session_path, restore_tools = FALSE)
  ))
  restored$rewind_files(checkpoint_id)

  expect_identical(readLines(path), "before")
})

test_that("provider errors finalize and persist orphaned tool captures", {
  root <- withr::local_tempdir(pattern = "deputy-orphan-checkpoint-")
  session_root <- file.path(root, "sessions")
  path <- file.path(root, "orphaned.txt")
  writeLines("before", path)
  mock <- create_checkpoint_callback_chat()
  request <- ellmer::ContentToolRequest(
    id = "orphaned-write",
    name = "write_file",
    arguments = list(path = path, content = "after"),
    tool = tool_write_file
  )
  mock$chat$last_turn <- function(role = "assistant") {
    ellmer::AssistantTurn(
      contents = list(request),
      tokens = c(1, 1, 0),
      cost = 0
    )
  }
  step <- 0L
  mock$chat$stream <- function(
    prompt = NULL,
    stream = c("text", "content"),
    controller = NULL
  ) {
    function() {
      step <<- step + 1L
      if (step == 1L) {
        mock$request_callback()(request)
        writeLines("after", path)
        return(request)
      }
      coro::exhausted()
    }
  }
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(tool_write_file),
    permissions = permissions_standard(root),
    enable_file_checkpointing = TRUE,
    working_dir = root
  )
  agent$configure_sdk_compat(list(
    persist_session = TRUE,
    session_store_dir = session_root,
    session_id = "orphaned-session"
  ))

  result <- agent$run_sync("write then fail")
  checkpoint_id <- result$events[[1L]]$checkpoint_id

  expect_identical(result$stop_reason, "provider_error")
  expect_identical(readLines(path), "after")
  expect_true(file.exists(result$snapshot_path))
  expect_no_error(agent$checkpoint("next checkpoint"))

  restored <- Agent$new(
    chat = create_mock_chat("restored"),
    enable_file_checkpointing = TRUE,
    working_dir = root
  )
  suppressWarnings(suppressMessages(
    restored$load_session(result$snapshot_path)
  ))
  restored$rewind_files(checkpoint_id)
  expect_identical(readLines(path), "before")
})

test_that("session checkpoint state cannot enable checkpointing", {
  root <- withr::local_tempdir(pattern = "deputy-checkpoint-authority-")
  session_path <- file.path(root, "session.rds")
  source <- Agent$new(
    chat = create_mock_chat("source"),
    enable_file_checkpointing = TRUE,
    working_dir = root
  )
  source$checkpoint("persisted checkpoint")
  suppressMessages(source$save_session(session_path))

  receiver <- Agent$new(
    chat = create_mock_chat("receiver"),
    enable_file_checkpointing = FALSE,
    working_dir = root
  )
  suppressMessages(receiver$load_session(session_path, restore_tools = FALSE))

  expect_error(
    receiver$list_checkpoints(),
    class = "deputy_file_checkpoint_error"
  )
})

test_that("session checkpoint state cannot cross configured roots", {
  sandbox <- withr::local_tempdir(pattern = "deputy-checkpoint-authority-")
  source_root <- file.path(sandbox, "source")
  receiver_root <- file.path(sandbox, "receiver")
  dir.create(source_root)
  dir.create(receiver_root)
  session_path <- file.path(sandbox, "session.rds")

  source <- Agent$new(
    chat = create_mock_chat("source"),
    enable_file_checkpointing = TRUE,
    working_dir = source_root
  )
  source$checkpoint("source checkpoint")
  suppressMessages(source$save_session(session_path))

  receiver_chat <- create_mock_chat("receiver")
  receiver <- Agent$new(
    chat = receiver_chat,
    system_prompt = "receiver prompt",
    enable_file_checkpointing = TRUE,
    working_dir = receiver_root
  )
  receiver_turns <- list(create_mock_user_turn("receiver history"))
  receiver_chat$set_turns(receiver_turns)
  receiver_checkpoint <- receiver$checkpoint("receiver checkpoint")

  expect_error(
    suppressMessages(
      receiver$load_session(session_path, restore_tools = FALSE)
    ),
    class = "deputy_file_checkpoint_path_error"
  )
  expect_identical(
    receiver$working_dir,
    normalizePath(receiver_root, mustWork = TRUE, winslash = "/")
  )
  expect_identical(receiver_chat$get_turns(), receiver_turns)
  expect_identical(receiver_chat$get_system_prompt(), "receiver prompt")
  expect_identical(
    receiver$list_checkpoints()$checkpoint_id,
    receiver_checkpoint
  )
})

test_that("runs expose automatic checkpoint IDs", {
  root <- withr::local_tempdir(pattern = "deputy-agent-checkpoint-")
  agent <- Agent$new(
    chat = create_mock_chat("done"),
    enable_file_checkpointing = TRUE,
    working_dir = root
  )

  result <- agent$run_sync("Answer briefly")
  checkpoint_events <- Filter(
    function(event) event$type == "file_checkpoint",
    result$events
  )

  expect_length(checkpoint_events, 1L)
  expect_identical(
    checkpoint_events[[1]]$checkpoint_id,
    result$events[[1]]$checkpoint_id
  )
  expect_identical(
    agent$list_checkpoints()$checkpoint_id,
    checkpoint_events[[1]]$checkpoint_id
  )
})

test_that("checkpoint methods fail clearly when disabled", {
  agent <- Agent$new(chat = create_mock_chat())

  expect_error(
    agent$checkpoint("disabled"),
    class = "deputy_file_checkpoint_error"
  )
  expect_error(
    agent$list_checkpoints(),
    class = "deputy_file_checkpoint_error"
  )
})

test_that("session restore and rewind reject active runs", {
  root <- withr::local_tempdir(pattern = "deputy-active-state-")
  session_path <- file.path(root, "session.rds")
  agent <- Agent$new(
    chat = create_mock_chat("done"),
    enable_file_checkpointing = TRUE,
    working_dir = root
  )
  checkpoint_id <- agent$checkpoint("before active run")
  suppressMessages(agent$save_session(session_path))
  generator <- agent$run("active")
  expect_identical(generator()$type, "start")

  expect_error(
    agent$load_session(session_path),
    class = "deputy_run_active"
  )
  expect_error(
    agent$rewind_files(checkpoint_id),
    class = "deputy_run_active"
  )
  expect_error(
    agent$compact(keep_last = 0, summary = "blocked"),
    class = "deputy_run_active"
  )

  generator <- NULL
  invisible(gc())
  expect_false(agent$.__enclos_env__$private$run_active)
})

test_that("LeadAgent shares its workspace checkpoint journal with sub-agents", {
  root <- withr::local_tempdir(pattern = "deputy-lead-checkpoint-")
  path <- file.path(root, "delegated.txt")
  writeLines("before", path)
  definition <- agent_definition(
    name = "writer",
    description = "Writes a file",
    prompt = "Write the requested file.",
    tools = list(tool_write_file)
  )
  lead <- LeadAgent$new(
    chat = create_mock_chat("done"),
    sub_agents = list(definition),
    permissions = permissions_standard(root),
    enable_file_checkpointing = TRUE,
    file_checkpoint_max_file_bytes = 8,
    file_checkpoint_max_journal_bytes = 4096,
    working_dir = root
  )
  child <- lead$.__enclos_env__$private$create_sub_agent(definition)

  expect_identical(
    child$.__enclos_env__$private$.file_checkpoints,
    lead$.__enclos_env__$private$.file_checkpoints
  )

  checkpoint_id <- lead$checkpoint("before delegation")
  store <- child$.__enclos_env__$private$.file_checkpoints
  oversized_path <- file.path(root, "oversized.txt")
  writeLines("too-large", oversized_path)
  expect_error(
    store$before_tool(
      "write_file",
      list(path = oversized_path),
      "delegated-oversized"
    ),
    "max_file_bytes",
    class = "deputy_file_checkpoint_limit_error"
  )
  store$before_tool(
    "write_file",
    list(path = path, content = "after"),
    "delegated-write"
  )
  writeLines("after", path)
  store$after_tool("delegated-write", success = TRUE)

  lead$rewind_files(checkpoint_id)
  expect_identical(readLines(path), "before")
})
