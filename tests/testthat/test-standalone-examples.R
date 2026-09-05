run_standalone_example <- function(
  name,
  chat,
  env = new.env(parent = as.environment("package:deputy"))
) {
  models <- character()
  local_mocked_bindings(
    chat_openai = function(model, ...) {
      models <<- c(models, model)
      if (is.function(chat)) chat() else chat
    },
    .package = "ellmer"
  )
  path <- system.file("examples", "standalone", name, package = "deputy")
  sys.source(path, envir = env)
  attr(env, "models") <- models
  env
}

test_that("basic, structured, session and skill scripts execute independently", {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("yaml")
  withr::local_envvar(DEPUTY_EXAMPLE_MODEL = NA_character_)
  basic <- run_standalone_example(
    "01-basic.R",
    create_mock_chat("An R vector.")
  )
  expect_identical(basic$result$response, "An R vector.")
  expect_identical(attr(basic, "models"), "gpt-5.6-luna")
  structured <- run_standalone_example(
    "06-structured-output.R",
    create_mock_chat('{"status":"ok"}')
  )
  expect_identical(structured$result$structured_output$parsed$status, "ok")
  source_chat <- create_mock_chat("I will remember Cedar.")
  source_stream <- source_chat$stream
  source_chat$stream <- function(prompt) {
    source_chat$set_turns(list(
      create_mock_user_turn(prompt),
      create_mock_assistant_turn("I will remember Cedar.")
    ))
    source_stream(prompt)
  }
  receiver_chat <- create_mock_chat("Cedar")
  receiver_stream <- receiver_chat$stream
  receiver_chat$stream <- function(prompt) {
    history <- receiver_chat$get_turns()
    if (length(history) != 2L) {
      rlang::abort("Session turns were not restored")
    }
    if (!grepl("Cedar", history[[1]]@contents[[1]]@text, fixed = TRUE)) {
      rlang::abort("Project name was not restored")
    }
    receiver_stream(prompt)
  }
  chats <- list(source_chat, receiver_chat)
  index <- 0L
  session <- run_standalone_example("07-session-resume.R", function() {
    index <<- index + 1L
    chats[[index]]
  })
  expect_equal(receiver_chat$get_turns(), source_chat$get_turns())
  expect_identical(index, 2L)
  expect_identical(attr(session, "models"), rep("gpt-5.6-luna", 2L))
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
    env <- new.env(parent = as.environment("package:deputy"))
    read <- NULL
    mock <- create_content_stream_chat(
      use_execution_result = TRUE,
      execute = function(request) {
        read <<- do.call(
          env$agent$get_tools()[["read_file"]],
          request@arguments
        )
        read
      }
    )
    example <- run_standalone_example(name, mock$chat, env)
    expect_match(read, "revenue increased by 12%", fixed = TRUE)
    expect_identical(mock$state$tool_executed, TRUE)
    expect_match(
      as.character(example$result$tool_results()[[1]]$tool_result),
      "revenue increased by 12%",
      fixed = TRUE
    )
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
  env <- new.env(parent = as.environment("package:deputy"))
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

test_that("debate example compares independent heads and synthesizes both arguments", {
  skip_if_not_installed("yaml")
  withr::local_envvar(
    DEPUTY_DEBATE_TOPIC = "Should reviews be mandatory?",
    DEPUTY_EXAMPLE_MODEL = "gpt-5.6-terra"
  )
  state <- new.env(parent = emptyenv())
  state$responder <- function(system_prompt, task) {
    if (grepl("AGAINST", system_prompt, fixed = TRUE)) {
      "Review queues can delay fixes.\nMeasure the cost | benefit."
    } else {
      "Independent review catches mistakes <early>."
    }
  }
  moderator_chat <- create_mock_chat("Pilot reviews and measure outcomes.")
  stream <- moderator_chat$stream
  submitted <- NULL
  moderator_chat$stream <- function(prompt) {
    submitted <<- prompt
    stream(prompt)
  }
  index <- 0L
  example <- run_standalone_example("09-debate.R", function() {
    index <<- index + 1L
    if (index == 1L) create_parallel_chat(state) else moderator_chat
  })
  expect_identical(index, 2L)
  expect_identical(attr(example, "models"), rep("gpt-5.6-terra", 2L))
  expect_identical(state$peak, 2L)
  expect_identical(
    example$batch$status,
    c(support = "completed", challenge = "completed")
  )
  expect_match(example$comparison, "mistakes &lt;early&gt;", fixed = TRUE)
  expect_match(
    example$comparison,
    "<br>Measure the cost &#124; benefit.",
    fixed = TRUE
  )
  expect_match(submitted, "Should reviews be mandatory?", fixed = TRUE)
  expect_match(
    submitted,
    "Independent review catches mistakes <early>.",
    fixed = TRUE
  )
  expect_match(submitted, "Review queues can delay fixes.", fixed = TRUE)
  expect_identical(
    example$synthesis$response,
    "Pilot reviews and measure outcomes."
  )
  expect_identical(example$requests_used, 3L)
  expect_length(example$moderator$get_tools(), 0L)
  expect_identical(names(example$moderator$skills()), "debate")
  expect_match(
    example$moderator$get_system_prompt(),
    "Do not invent sources",
    fixed = TRUE
  )
})

test_that("debate example retains partial comparison and skips synthesis on failure", {
  skip_if_not_installed("yaml")
  state <- new.env(parent = emptyenv())
  state$responder <- function(system_prompt, task) {
    if (grepl("AGAINST", system_prompt, fixed = TRUE)) {
      cli::cli_abort("fixture challenger unavailable")
    }
    "Independent review catches mistakes."
  }
  index <- 0L
  env <- new.env(parent = as.environment("package:deputy"))
  expect_error(
    run_standalone_example(
      "09-debate.R",
      function() {
        index <<- index + 1L
        create_parallel_chat(state)
      },
      env
    ),
    "Debate incomplete"
  )
  expect_identical(index, 1L)
  expect_identical(
    env$batch$status,
    c(support = "completed", challenge = "failed")
  )
  expect_match(
    env$comparison,
    "Independent review catches mistakes.",
    fixed = TRUE
  )
  expect_match(env$comparison, "[failed]", fixed = TRUE)
  expect_match(
    conditionMessage(env$batch$errors$challenge),
    "fixture challenger unavailable",
    fixed = TRUE
  )
  expect_false(exists("synthesis", envir = env, inherits = FALSE))
})
