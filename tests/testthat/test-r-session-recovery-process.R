test_that("a killed worker can import selected data without repeating a write", {
  skip_if_not_installed("ps")
  directory <- withr::local_tempdir()
  agent <- Agent$new(chat = create_mock_chat(), working_dir = directory)
  session <- RSession$new(
    agent,
    checkpoint_dir = directory,
    checkpoint_owner_id = "team"
  )
  withr::defer(session$close())
  result <- r_session_await(session$run(paste(
    "measurements <- c(2L, 3L, 5L); scratch <- 17;",
    "cat('once\\n', file = 'effect.txt', append = TRUE)"
  )))
  expect_identical(result@extra$deputy_r$outcome, "complete")
  capture <- r_session_await(session$checkpoint("measurements"))

  ps::ps_kill(ps::ps_handle(session$status()$pid))
  deadline <- Sys.time() + 5
  while (session$status()$state != "lost" && Sys.time() < deadline) {
    Sys.sleep(0.02)
  }
  expect_identical(session$status()$state, "lost")
  receipt <- r_session_await(session$restore_checkpoint(capture$id))
  expect_gt(receipt$restored_generation, capture$generation)
  result <- r_session_await(session$run(paste(
    "stopifnot(identical(measurements, c(2L, 3L, 5L)),",
    "!exists('scratch', inherits = FALSE)); cat('recovered')"
  )))
  expect_match(r_session_text(result), "recovered")
  expect_identical(readLines(file.path(directory, "effect.txt")), "once")
})

test_that("data and conversation evidence survive a killed supervisor", {
  skip_on_os("windows")
  skip_if_not_installed("pkgload")
  directory <- withr::local_tempdir()
  checkpoints <- file.path(directory, "checkpoints")
  dir.create(checkpoints)
  receipt_path <- file.path(directory, "receipt.rds")
  evidence_path <- file.path(directory, "history.rds")
  code <- paste(
    "measurements <- data.frame(n = c(7L, 11L));",
    "cat('once\\n', file = 'effect.txt', append = TRUE); cat('wrote once')"
  )
  server <- local_runtime_server(list(
    runtime_reply(tool = "run_r_code", arguments = list(code = code)),
    runtime_reply("The measurements are ready.")
  ))
  supervisor <- callr::r_bg(
    function(
      package_path,
      url,
      directory,
      checkpoints,
      evidence,
      receipt,
      await
    ) {
      # Use the same source tree or staged installation as the test runner.
      if (file.exists(file.path(package_path, "R", "agent.R"))) {
        pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      } else {
        library(deputy, lib.loc = dirname(package_path))
      }
      agent <- deputy::Agent$new(
        chat = ellmer::chat_openai_compatible(
          base_url = url,
          credentials = function() "fixture",
          model = "gpt-4o-mini",
          echo = "none"
        ),
        working_dir = directory,
        agent_id = "analysis-agent",
        session_id = "analysis-conversation",
        permissions = deputy::Permissions(r_code = TRUE)
      )
      session <- deputy::RSession$new(
        agent,
        checkpoint_dir = checkpoints,
        checkpoint_owner_id = "team"
      )
      on.exit(session$close(), add = TRUE)
      agent$register_tools(session$tools())
      agent$chat("Prepare the measurements.")
      base::stopifnot(agent$last_run()$stop_reason == "complete")
      suppressMessages(agent$save_session(evidence))
      checkpoint <- await(session$checkpoint("measurements"))
      saveRDS(checkpoint, paste0(receipt, ".tmp"))
      base::stopifnot(file.rename(paste0(receipt, ".tmp"), receipt))
      Sys.sleep(120)
    },
    args = list(
      package_path = getNamespaceInfo(asNamespace("deputy"), "path"),
      url = server$url,
      directory = directory,
      checkpoints = checkpoints,
      evidence = evidence_path,
      receipt = receipt_path,
      await = child_function(r_session_await)
    ),
    libpath = .libPaths()
  )
  withr::defer(supervisor$kill_tree())
  deadline <- Sys.time() + 60
  while (
    !file.exists(receipt_path) && supervisor$is_alive() && Sys.time() < deadline
  ) {
    later::run_now(0.02)
  }
  if (!file.exists(receipt_path)) {
    cli::cli_abort(
      "The supervisor did not commit its checkpoint receipt: {supervisor$read_all_error()}"
    )
  }
  capture <- readRDS(receipt_path)
  supervisor$kill()
  supervisor$wait(timeout = 5000)
  expect_false(supervisor$is_alive())
  expect_identical(readLines(file.path(directory, "effect.txt")), "once")

  agent <- Agent$new(
    chat = create_mock_chat(),
    working_dir = directory,
    agent_id = "analysis-agent",
    session_id = "analysis-conversation",
    permissions = Permissions(r_code = FALSE)
  )
  suppressMessages(agent$load_session(evidence_path))
  contents <- unlist(
    lapply(agent$get_turns(), function(turn) turn@contents),
    recursive = FALSE
  )
  result <- Filter(
    function(item) inherits(item, "ellmer::ContentToolResult"),
    contents
  )[[1L]]
  expect_identical(result@extra$deputy_r$code, code)
  expect_match(as.character(result@extra$display$html), "wrote once")
  expect_null(result@request@tool)
  expect_length(agent$get_tools(), 0L)

  reopened <- RSession$new(
    agent,
    checkpoint_dir = checkpoints,
    checkpoint_owner_id = "team"
  )
  withr::defer(reopened$close())
  receipt <- r_session_await(reopened$restore_checkpoint(capture$id))
  expect_identical(receipt$bindings, "measurements")
  expect_identical(receipt$restored_generation, 1L)
  result <- r_session_await(reopened$run("cat(sum(measurements$n))"))
  expect_match(r_session_text(result), "18")
  expect_identical(readLines(file.path(directory, "effect.txt")), "once")
  expect_length(server$requests(), 2L)
})
