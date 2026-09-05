cli_test_app <- function() {
  app <- system.file("exec", "deputy.R", package = "deputy")
  if (nzchar(app) && file.exists(app)) {
    return(app)
  }

  app <- testthat::test_path("..", "..", "exec", "deputy.R")
  if (!file.exists(app)) {
    stop("Could not find the deputy Rapp executable")
  }
  normalizePath(app, mustWork = TRUE)
}

cli_test_generator <- function(events, state = NULL) {
  index <- 0L
  function() {
    index <<- index + 1L
    if (!is.null(state)) {
      state$generator_calls <- index
    }
    if (index > length(events)) {
      return(coro::exhausted())
    }
    events[[index]]
  }
}

test_that("the package executable exposes the Rapp command surface", {
  withr::local_options(cli.num_colors = 1)

  help <- capture.output(Rapp::run(cli_test_app(), "--help"))
  help <- paste(help, collapse = "\n")

  expect_true(grepl("Usage: deputy [OPTIONS] [<TASK>]", help, fixed = TRUE))
  expect_true(grepl("-d, --dir <DIR>", help, fixed = TRUE))
  expect_true(grepl("-n, --max-requests <MAX-REQUESTS>", help, fixed = TRUE))
  expect_true(grepl("--mcp-server <MCP-SERVER>", help, fixed = TRUE))
  expect_true(grepl("<TASK>  Task to run", help, fixed = TRUE))
  expect_false(grepl("-x, --task", help, fixed = TRUE))
  expect_false(grepl("--permission-mode", help, fixed = TRUE))
  expect_false(grepl("--max-turns", help, fixed = TRUE))
  expect_false(grepl("--persist-session", help, fixed = TRUE))
  expect_false(grepl("--resume-session-id", help, fixed = TRUE))
  expect_false(grepl("--fork-session", help, fixed = TRUE))
  expect_false(grepl("--mcp-servers", help, fixed = TRUE))
  expect_false(grepl("--setting-source", help, fixed = TRUE))
})

test_that("Rapp parses CLI options before entering the package runtime", {
  working_dir <- withr::local_tempdir()
  captured <- NULL
  local_mocked_bindings(
    deputy_cli_main = function(config) {
      captured <<- config
      invisible(config)
    },
    .package = "deputy"
  )

  Rapp::run(
    cli_test_app(),
    c(
      "-p",
      "openai",
      "-m",
      "gpt-test",
      "-t",
      "minimal",
      "-P",
      "readonly",
      "-n",
      "7",
      "-c",
      "1.25",
      "-s",
      "load.rds",
      "-S",
      "save.rds",
      "-y",
      "Be concise",
      "-f",
      "prompt.txt",
      "-A",
      "-M",
      "-C",
      ".mcp.json",
      "--mcp-server",
      "alpha",
      "--mcp-server",
      "beta",
      "-d",
      working_dir,
      "-v",
      "--no-color",
      "-g",
      "-G",
      "debug.log",
      "one complete task"
    )
  )

  expect_equal(captured$provider, "openai")
  expect_equal(captured$model, "gpt-test")
  expect_equal(captured$tools, "minimal")
  expect_equal(captured$permissions, "readonly")
  expect_identical(captured$max_requests, 7L)
  expect_equal(captured$max_cost, 1.25)
  expect_equal(captured$session, "load.rds")
  expect_equal(captured$save_session, "save.rds")
  expect_equal(captured$system_prompt, "Be concise")
  expect_equal(captured$system_prompt_file, "prompt.txt")
  expect_true(captured$no_ask)
  expect_true(captured$mcp)
  expect_equal(captured$mcp_config, ".mcp.json")
  expect_equal(captured$mcp_server, c("alpha", "beta"))
  expect_equal(captured$dir, working_dir)
  expect_true(captured$verbose)
  expect_true(captured$no_color)
  expect_true(captured$debug)
  expect_equal(captured$debug_file, "debug.log")
  expect_equal(captured$task, "one complete task")
})

test_that("CLI model defaults and overrides reach the real ellmer Chat", {
  withr::local_envvar(OPENAI_API_KEY = "example")
  chat <- NULL
  local_mocked_bindings(
    deputy_cli_main = function(config) {
      config <- cli_normalize_config(config)
      chat <<- cli_create_chat(config$provider, config$model)
      invisible(NULL)
    },
    .package = "deputy"
  )

  Rapp::run(cli_test_app(), "inspect files")
  expect_identical(chat$get_model(), "gpt-5.6-luna")

  Rapp::run(cli_test_app(), c("--provider", "openai", "inspect files"))
  expect_identical(chat$get_model(), "gpt-5.6-luna")

  for (model in c("gpt-5.6-terra", "gpt-5.6-sol", "gpt-4o-mini")) {
    Rapp::run(cli_test_app(), c("--model", model, "inspect files"))
    expect_identical(chat$get_model(), model)
    agent <- Agent$new(chat, tools = list())
    expect_identical(agent$get_model(), model)
  }
})

test_that("Rapp discovers and installs the package executable", {
  destination <- withr::local_tempdir()

  created <- suppressMessages(Rapp::install_pkg_cli_apps(
    "deputy",
    destdir = destination,
    overwrite = TRUE
  ))

  expected_name <- if (.Platform$OS.type == "windows") {
    "deputy.bat"
  } else {
    "deputy"
  }
  expect_equal(basename(created), expected_name)
  expect_true(file.exists(created))
  if (.Platform$OS.type == "unix") {
    expect_equal(unname(file.access(created, mode = 1L)), 0L)
  }
})

test_that("Google uses the current ellmer constructor and its default model", {
  seen_model <- NULL
  local_mocked_bindings(
    chat_google_gemini = function(model) {
      seen_model <<- if (missing(model)) "<provider-default>" else model
      list(provider = "google")
    },
    .package = "ellmer"
  )

  expect_equal(cli_create_chat("google", NULL), list(provider = "google"))
  expect_equal(seen_model, "<provider-default>")

  expect_equal(
    cli_create_chat("google", "gemini-test"),
    list(provider = "google")
  )
  expect_equal(seen_model, "gemini-test")
})

test_that("Anthropic retains its provider default and explicit model override", {
  seen_model <- NULL
  local_mocked_bindings(
    chat_anthropic = function(model) {
      seen_model <<- if (missing(model)) "<provider-default>" else model
      list(provider = "anthropic")
    },
    .package = "ellmer"
  )

  expect_equal(cli_create_chat("anthropic", NULL), list(provider = "anthropic"))
  expect_equal(seen_model, "<provider-default>")
  expect_equal(
    cli_create_chat("anthropic", "claude-test"),
    list(provider = "anthropic")
  )
  expect_equal(seen_model, "claude-test")
})

test_that("CLI builds permissions and usage limits separately", {
  permissions <- cli_get_permissions("readonly", working_dir = tempdir())
  limits <- cli_get_usage_limits(max_requests = 7L, max_cost = 0.01)

  expect_identical(permissions$mode, "readonly")
  expect_identical(limits$max_requests, 7L)
  expect_equal(limits$max_cost_usd, 0.01)
})

test_that("the event walker consumes callable generators through stop", {
  state <- new.env(parent = emptyenv())
  events <- list(
    list(type = "text", text = "hello"),
    list(
      type = "tool_end",
      tool_name = "read_file",
      tool_error = simpleError("denied")
    ),
    list(type = "stop", total_turns = 1L),
    list(type = "text", text = "must not be consumed")
  )
  agent <- list(
    run = function(task) {
      state$task <- task
      cli_test_generator(events, state)
    }
  )
  seen <- list()

  stop_event <- cli_walk_agent_events(agent, "inspect files", function(event) {
    seen[[length(seen) + 1L]] <<- event
  })

  expect_equal(state$task, "inspect files")
  expect_identical(state$generator_calls, 3L)
  expect_equal(
    vapply(seen, `[[`, character(1), "type"),
    c(
      "text",
      "tool_end",
      "stop"
    )
  )
  expect_equal(cli_tool_error(seen[[2L]]), "denied")
  expect_identical(stop_event, events[[3L]])
})

test_that("the event walker does not swallow generator failures", {
  agent <- list(
    run = function(task) {
      function() stop("provider stream failed")
    }
  )

  expect_error(
    cli_walk_agent_events(agent, "inspect files", identity),
    "provider stream failed"
  )
})

test_that("tool failures render the tool_error field", {
  withr::local_options(cli.num_colors = 1)
  debug <- character()
  debug_log <- function(...) {
    debug <<- c(debug, paste0(..., collapse = ""))
  }

  messages <- capture.output(
    cli_render_event(
      list(
        type = "tool_end",
        tool_name = "read_file",
        tool_error = simpleError("permission denied")
      ),
      debug_log = debug_log
    ),
    type = "message"
  )

  expect_true(any(grepl("read_file", messages, fixed = TRUE)))
  expect_true(any(grepl("permission denied", messages, fixed = TRUE)))
  expect_equal(
    debug,
    "tool_end error: read_file -> permission denied"
  )
})

test_that("task mode drains and renders the agent generator", {
  withr::local_options(cli.num_colors = 1)
  state <- new.env(parent = emptyenv())
  agent <- list(
    run = function(task) {
      state$task <- task
      cli_test_generator(
        list(
          list(type = "text", text = "task response"),
          list(type = "stop", total_turns = 2L, cost = list(total = 0))
        ),
        state
      )
    }
  )

  messages <- capture.output(
    output <- capture.output(
      cli_run_task(agent, "summarize", verbose = FALSE),
      type = "output"
    ),
    type = "message"
  )

  expect_equal(state$task, "summarize")
  expect_identical(state$generator_calls, 2L)
  expect_true(any(grepl("task response", output, fixed = TRUE)))
  expect_true(any(grepl("Running task", messages, fixed = TRUE)))
  expect_true(any(grepl("Completed in", messages, fixed = TRUE)))
})

test_that("task mode fails when the agent does not complete", {
  withr::local_options(cli.num_colors = 1)
  agent <- list(
    run = function(task) {
      cli_test_generator(list(
        list(
          type = "stop",
          reason = "provider_error",
          total_turns = 1L,
          cost = list(total = 0)
        )
      ))
    }
  )

  expect_error(
    suppressMessages(cli_run_task(agent, "summarize")),
    class = "deputy_cli_task_failed"
  )
})

test_that("interactive mode runs prompts until a quit command", {
  withr::local_options(cli.num_colors = 1)
  state <- new.env(parent = emptyenv())
  state$inputs <- c("first task", "/quit")
  state$input_index <- 0L
  state$tasks <- character()
  input_reader <- function(prompt) {
    state$input_index <- state$input_index + 1L
    state$inputs[[state$input_index]]
  }
  agent <- list(
    run = function(task) {
      state$tasks <- c(state$tasks, task)
      cli_test_generator(list(
        list(type = "text", text = "interactive response"),
        list(type = "stop", total_turns = 1L, cost = list(total = 0))
      ))
    }
  )

  messages <- capture.output(
    output <- capture.output(
      cli_run_interactive(agent, input_reader = input_reader),
      type = "output"
    ),
    type = "message"
  )

  expect_equal(state$tasks, "first task")
  expect_identical(state$input_index, 2L)
  expect_true(any(grepl("interactive response", output, fixed = TRUE)))
  expect_true(any(grepl("Goodbye", messages, fixed = TRUE)))
})
