run_standalone_example <- function(
  name,
  chat,
  env = new.env(parent = globalenv())
) {
  local_mocked_bindings(chat_openai = function(...) chat, .package = "ellmer")
  path <- system.file("examples", "standalone", name, package = "deputy")
  sys.source(path, envir = env)
  env
}

test_that("basic, structured, session and skill scripts execute independently", {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("yaml")
  basic <- run_standalone_example(
    "01-basic.R",
    create_mock_chat("An R vector.")
  )
  expect_identical(basic$result$response, "An R vector.")
  structured <- run_standalone_example(
    "06-structured-output.R",
    create_mock_chat('{"status":"ok"}')
  )
  expect_identical(structured$result$structured_output$parsed$status, "ok")
  session_chat <- create_mock_chat("Cedar")
  saved_turns <- list(
    create_mock_user_turn("My project is Cedar."),
    create_mock_assistant_turn("I will remember Cedar.")
  )
  session_chat$set_turns(saved_turns)
  session <- run_standalone_example("07-session-resume.R", session_chat)
  expect_equal(session$resumed$get_turns(), saved_turns)
  expect_identical(session$resumed$run_context$project, "session-example")
  expect_identical(session$result$response, "Cedar")
  expect_false(file.exists(session$session_file))
  skill <- run_standalone_example(
    "08-skills.R",
    create_mock_chat("Two review bullets.")
  )
  expect_length(skill$agent$skills, 1L)
  expect_match(
    skill$agent$get_system_prompt(),
    "correctness, then readability",
    fixed = TRUE
  )
})

test_that("file and hook examples perform the requested read", {
  for (name in c("02-tools.R", "04-hooks.R")) {
    env <- new.env(parent = globalenv())
    read <- NULL
    mock <- create_content_stream_chat(execute = function(request) {
      read <<- tool_read_file(file.path(env$workspace, request@arguments$path))
    })
    example <- run_standalone_example(name, mock$chat, env)
    expect_match(read, "revenue increased by 12%", fixed = TRUE)
    expect_identical(mock$state$tool_executed, TRUE)
    if (name == "04-hooks.R") {
      expect_length(example$audit, 1L)
      expect_identical(example$audit[[1]]$tool, "read_file")
      expect_type(example$audit[[1]]$run_id, "character")
    }
  }
})

test_that("permissions example blocks a real attempted write", {
  mock <- create_shiny_tool_chat(
    "write_file",
    list(path = "blocked.txt", content = "hello")
  )
  example <- run_standalone_example("03-permissions.R", mock$chat)
  expect_identical(mock$state$rejected, TRUE)
  expect_false(file.exists(file.path(example$workspace, "blocked.txt")))
})

test_that("delegation example runs its registered reviewer during the lead run", {
  env <- new.env(parent = globalenv())
  mock <- create_shiny_tool_chat(
    "delegate_to_agent",
    list(agent_name = "reviewer", task = "Review mean(c(1, NA))."),
    execute = function(request) {
      resolve_async_value(env$lead$get_tools()[["delegate_to_agent"]](
        "reviewer",
        "Review mean(c(1, NA))."
      ))
    }
  )
  example <- run_standalone_example("05-delegation.R", mock$chat, env)
  expect_null(mock$state$rejection)
  runs <- example$lead$list_subagents()
  expect_equal(nrow(runs), 1L)
  expect_identical(runs$agent_name, "reviewer")
  expect_identical(runs$status, "completed")
})
