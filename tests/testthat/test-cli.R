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
  expect_true(grepl("--mcp-server <MCP-SERVER>", help, fixed = TRUE))
  expect_true(grepl("<TASK>  Task to run", help, fixed = TRUE))
  expect_false(grepl("-x, --task", help, fixed = TRUE))
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
      "--permission-mode",
      "acceptEdits",
      "-n",
      "7",
      "-c",
      "1.25",
      "-s",
      "load.rds",
      "-S",
      "save.rds",
      "--persist-session",
      "--resume-session-id",
      "session-old",
      "--resume-session-at",
      "2026-08-14T12:00:00Z",
      "--fork-session",
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
      "--mcp-servers",
      "gamma,delta",
      "--setting-source",
      "project",
      "--setting-source",
      "user",
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
  expect_equal(captured$permission_mode, "acceptEdits")
  expect_identical(captured$max_turns, 7L)
  expect_equal(captured$max_cost, 1.25)
  expect_equal(captured$session, "load.rds")
  expect_equal(captured$save_session, "save.rds")
  expect_true(captured$persist_session)
  expect_equal(captured$resume_session_id, "session-old")
  expect_equal(captured$resume_session_at, "2026-08-14T12:00:00Z")
  expect_true(captured$fork_session)
  expect_equal(captured$system_prompt, "Be concise")
  expect_equal(captured$system_prompt_file, "prompt.txt")
  expect_true(captured$no_ask)
  expect_true(captured$mcp)
  expect_equal(captured$mcp_config, ".mcp.json")
  expect_equal(captured$mcp_server, c("alpha", "beta"))
  expect_equal(captured$mcp_servers, "gamma,delta")
  expect_equal(captured$setting_source, c("project", "user"))
  expect_equal(captured$dir, working_dir)
  expect_true(captured$verbose)
  expect_true(captured$no_color)
  expect_true(captured$debug)
  expect_equal(captured$debug_file, "debug.log")
  expect_equal(captured$task, "one complete task")
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

test_that("CLI permission limits include cost in readonly mode", {
  permissions <- cli_get_permissions(
    "readonly",
    working_dir = tempdir(),
    max_turns = 7L,
    max_cost = 0.01
  )

  expect_identical(permissions$max_turns, 7L)
  expect_equal(permissions$max_cost_usd, 0.01)
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

test_that("compat persistence resolves package-owned session helpers", {
  state <- new.env(parent = emptyenv())
  state$configurations <- list()
  agent <- list(
    configure_sdk_compat = function(options) {
      state$configurations[[length(state$configurations) + 1L]] <- options
    },
    load_session = function(path) {
      state$loaded_path <- path
    },
    .__enclos_env__ = list(
      private = list(
        notify = function(message, ...) {
          state$notification <- c(list(message = message), list(...))
        },
        snapshot_compat_state = function(reason) {
          state$snapshot_reason <- reason
        }
      )
    )
  )
  local_mocked_bindings(
    session_store_default_dir = function() "/tmp/deputy-test-sessions",
    generate_session_id = function() "session-new",
    session_store_select_snapshot = function(root, session_id, at) {
      state$selection <- list(root = root, session_id = session_id, at = at)
      list(path = "/tmp/deputy-session.rds")
    },
    .package = "deputy"
  )
  config <- list(
    persist_session = TRUE,
    resume_session_id = "session-old",
    resume_session_at = "2026-08-14T12:00:00Z",
    fork_session = TRUE
  )

  session_id <- cli_configure_compat_session(agent, config)

  expect_equal(session_id, "session-new")
  expect_length(state$configurations, 2L)
  expect_equal(
    state$configurations[[1L]],
    list(
      persist_session = TRUE,
      session_store_dir = "/tmp/deputy-test-sessions",
      session_id = "session-new"
    )
  )
  expect_equal(state$configurations[[2L]], state$configurations[[1L]])
  expect_equal(
    state$selection,
    list(
      root = "/tmp/deputy-test-sessions",
      session_id = "session-old",
      at = "2026-08-14T12:00:00Z"
    )
  )
  expect_equal(state$loaded_path, "/tmp/deputy-session.rds")
  expect_equal(state$notification$code, "session_forked")
  expect_equal(state$notification$source_session_id, "session-old")
  expect_equal(state$notification$active_session_id, "session-new")
  expect_equal(state$snapshot_reason, "fork_restore")
})
