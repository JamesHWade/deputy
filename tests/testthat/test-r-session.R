test_that("R sessions reuse variables, queue dependencies and isolate owners", {
  directory <- withr::local_tempdir()
  agent <- Agent$new(
    chat = create_mock_chat(),
    working_dir = directory,
    run_context = list(conversation_id = "one")
  )
  other_agent <- Agent$new(
    chat = create_mock_chat(),
    working_dir = directory,
    run_context = list(conversation_id = "two")
  )
  session <- RSession$new(agent)
  other <- RSession$new(other_agent)
  withr::defer(session$close())
  withr::defer(other$close())
  expect_null(session$status()$pid)
  first <- session$run(
    "x <- 17; options(deputy_test_option = 8); Sys.sleep(0.05); x"
  )
  second <- session$run("x + getOption('deputy_test_option')")
  expect_match(r_session_text(r_session_await(first)), "fresh R session")
  expect_match(r_session_text(r_session_await(second)), "25")
  expect_match(
    r_session_text(r_session_await(other$run("exists('x')"))),
    "FALSE"
  )
  expect_identical(session$status()$generation, 1L)
  expect_identical(session$status()$queued, 0L)
  expect_snapshot(error = TRUE, other_agent$register_tools(session$tools()))
  agent$register_tools(session$tools())
  expect_named(agent$get_tools(), "run_r_code")
  before <- getwd()
  r_session_await(session$run("setwd(tempdir())"))
  expect_match(
    r_session_text(r_session_await(session$run("getwd()"))),
    normalizePath(directory, winslash = "/"),
    fixed = TRUE
  )
  expect_identical(getwd(), before)
  session$close()
  expect_identical(session$status()$state, "closed")
  expect_null(session$status()$pid)
  expect_snapshot(error = TRUE, session$run("1"))
})

test_that("base and ggplot2 figures preserve drawing updates and ordered conditions", {
  skip_if_not_installed("ggplot2")
  agent <- Agent$new(
    chat = create_mock_chat(),
    working_dir = withr::local_tempdir()
  )
  session <- RSession$new(agent)
  withr::defer(session$close())
  code <- paste(
    "x <- 5; cat('before'); plot(1:3); title('First'); warning('careful');",
    "plot(3:1); message('after'); stop('recover'); x <- 99"
  )
  result <- r_session_await(session$run(code))
  record <- result@extra$deputy_r
  expect_identical(record$outcome, "error")
  expect_identical(
    vapply(record$segments, `[[`, character(1), "type"),
    c("text", "plot", "warning", "plot", "message", "error")
  )
  images <- Filter(
    function(x) inherits(x, "ellmer::ContentImage"),
    result@value
  )
  expect_length(images, 2L)
  expect_identical(
    record$segments[[2L]]$data[1:8],
    as.raw(c(137, 80, 78, 71, 13, 10, 26, 10))
  )
  expect_match(r_session_text(r_session_await(session$run("x + 1"))), "6")
  ggplot <- r_session_await(session$run(paste(
    "ggplot2::ggplot(data.frame(x=1:3), ggplot2::aes(x,x)) + ggplot2::geom_point()"
  )))
  expect_length(
    Filter(function(x) inherits(x, "ellmer::ContentImage"), ggplot@value),
    1L
  )
  expect_identical(ggplot@extra$deputy_r$outcome, "complete")
  display <- as.character(result@extra$display$html)
  expect_match(display, "data:image/png;base64,", fixed = TRUE)
  expect_match(display, "Details", fixed = TRUE)
  expect_identical(
    as.character(unserialize(serialize(result, NULL))@extra$display$html),
    display
  )
})

test_that("timeouts and cancellation discard dependent queued code and restart honestly", {
  directory <- withr::local_tempdir()
  agent <- Agent$new(chat = create_mock_chat(), working_dir = directory)
  # Instrumented workers need time to initialize even for a simple expression.
  session <- RSession$new(agent, timeout = 10)
  withr::defer(session$close())
  initial <- r_session_await(session$run("x <- 2"))
  expect_identical(initial@extra$deputy_r$outcome, "complete")
  timed <- session$run("Sys.sleep(60)")
  queued <- session$run("file.create('must-not-exist')")
  expect_identical(r_session_await(timed)@extra$deputy_r$outcome, "timed_out")
  expect_identical(
    r_session_await(queued)@extra$deputy_r$outcome,
    "not_executed"
  )
  expect_identical(file.exists(file.path(directory, "must-not-exist")), FALSE)
  restarted <- r_session_await(session$run("exists('x')"))
  expect_identical(restarted@extra$deputy_r$outcome, "complete")
  expect_match(r_session_text(restarted), "FALSE")
  expect_match(r_session_text(restarted), "timed_out")
  expect_identical(restarted@extra$deputy_r$generation, 2L)
  pending <- session$run("Sys.sleep(5)")
  next_call <- session$run("file.create('must-not-exist')")
  session$cancel()
  expect_identical(r_session_await(pending)@extra$deputy_r$outcome, "cancelled")
  expect_identical(
    r_session_await(next_call)@extra$deputy_r$outcome,
    "not_executed"
  )
  expect_null(session$status()$pid)
  expect_identical(file.exists(file.path(directory, "must-not-exist")), FALSE)
  expect_match(
    r_session_text(r_session_await(session$run("1 + 1"))),
    "fresh R session"
  )
})

test_that("worker crashes settle and finite output and queue limits are enforced", {
  agent <- Agent$new(
    chat = create_mock_chat(),
    working_dir = withr::local_tempdir()
  )
  session <- RSession$new(agent, queue_limit = 1L, max_output_bytes = 1024L)
  withr::defer(session$close())
  output <- r_session_await(session$run("cat(strrep('a', 10000))"))
  expect_identical(output@extra$deputy_r$outcome, "output_truncated")
  expect_lt(nchar(r_session_text(output), "bytes"), 1400)
  crashed <- r_session_await(session$run("quit(save='no')"))
  # The process may exit before polling, or close its pipe during the read.
  expect_contains(
    c("worker_exited", "worker_failed"),
    crashed@extra$deputy_r$outcome
  )
  expect_null(session$status()$pid)
  first <- session$run("Sys.sleep(5)")
  second <- session$run("1")
  expect_snapshot(error = TRUE, session$run("2"))
  session$close()
  expect_identical(r_session_await(first)@extra$deputy_r$outcome, "closed")
  expect_identical(
    r_session_await(second)@extra$deputy_r$outcome,
    "not_executed"
  )
})

test_that("idle worker loss and garbage collection release live state", {
  agent <- Agent$new(
    chat = create_mock_chat(),
    working_dir = withr::local_tempdir()
  )
  session <- RSession$new(agent)
  withr::defer(session$close())
  r_session_await(session$run("x <- 9"))
  pid <- session$status()$pid
  ps::ps_kill(ps::ps_handle(pid))
  deadline <- Sys.time() + 5
  while (pid %in% ps::ps_pids() && Sys.time() < deadline) {
    Sys.sleep(0.01)
  }
  expect_identical(session$status()$state, "lost")
  result <- r_session_await(session$run("exists('x')"))
  expect_match(r_session_text(result), "FALSE")
  expect_match(r_session_text(result), "worker_exited")
  expect_identical(result@extra$deputy_r$generation, 2L)
  orphan <- RSession$new(agent)
  orphan_result <- r_session_await(orphan$run(paste(
    "child <- callr::r_bg(function() Sys.sleep(60));",
    "cat('child_pid=', child$get_pid(), sep='')"
  )))
  child_match <- regmatches(
    r_session_text(orphan_result),
    regexec("child_pid=([0-9]+)", r_session_text(orphan_result))
  )[[1L]]
  child_pid <- as.integer(child_match[[2L]])
  child_handle <- ps::ps_handle(child_pid)
  withr::defer(try(ps::ps_kill(child_handle), silent = TRUE))
  orphan_pid <- orphan$status()$pid
  rm(orphan)
  # Finished poll callbacks must release the owner before collection.
  later::run_now(0.05)
  gc()
  deadline <- Sys.time() + 5
  while (
    any(c(orphan_pid, child_pid) %in% ps::ps_pids()) && Sys.time() < deadline
  ) {
    later::run_now(0.01)
    gc()
  }
  expect_false(orphan_pid %in% ps::ps_pids())
  expect_false(child_pid %in% ps::ps_pids())
})

test_that("grid and patchwork compositions yield native figures and widgets fail explicitly", {
  skip_if_not_installed("patchwork")
  agent <- Agent$new(
    chat = create_mock_chat(),
    working_dir = withr::local_tempdir()
  )
  session <- RSession$new(agent)
  withr::defer(session$close())
  for (code in c(
    "grid::grid.newpage(); grid::grid.rect(); grid::grid.text('Grid figure')",
    "p <- ggplot2::ggplot(data.frame(x=1:3), ggplot2::aes(x,x)) + ggplot2::geom_point(); patchwork::wrap_plots(p,p)"
  )) {
    result <- r_session_await(session$run(code))
    expect_identical(result@extra$deputy_r$outcome, "complete")
    expect_length(
      Filter(function(x) inherits(x, "ellmer::ContentImage"), result@value),
      1L
    )
  }
  skip_if_not_installed("htmlwidgets")
  result <- r_session_await(session$run(
    "htmlwidgets::createWidget('example', list(x=1))"
  ))
  expect_identical(result@extra$deputy_r$outcome, "unsupported_output")
  expect_match(
    r_session_text(result),
    "No interactive widget or rich table was saved",
    fixed = TRUE
  )
  expect_length(
    Filter(function(x) inherits(x, "ellmer::ContentImage"), result@value),
    0L
  )
})

test_that("Agent clones cannot read or cancel the original R owner", {
  agent <- Agent$new(
    chat = create_mock_chat(),
    working_dir = withr::local_tempdir()
  )
  session <- RSession$new(agent)
  withr::defer(session$close())
  r_session_await(session$run("x <- 27"))
  agent$register_tools(session$tools())
  expect_error(
    agent$clone(),
    "different Agent",
    class = "deputy_tool_registration"
  )
  expect_match(r_session_text(r_session_await(session$run("x"))), "27")
  expect_identical(session$status()$generation, 1L)
  # Equal public identifiers are not proof of identical process-local ownership.
  other <- Agent$new(
    chat = create_mock_chat(),
    working_dir = agent$working_dir,
    agent_id = agent$agent_id,
    session_id = agent$session_id()
  )
  expect_error(
    other$register_tools(session$tools()),
    "different Agent",
    class = "deputy_tool_registration"
  )
  pending <- session$run("Sys.sleep(0.1); x + 1")
  cancel_active_r_session_tools(session$tools(), other, other$run_context)
  expect_match(r_session_text(r_session_await(pending)), "28")
})

test_that("intermediate callr progress conditions preserve the worker and terminal result", {
  agent <- Agent$new(
    chat = create_mock_chat(),
    working_dir = withr::local_tempdir()
  )
  session <- RSession$new(agent)
  withr::defer(session$close())
  result <- r_session_await(session$run(paste(
    "x <- 41; signalCondition(structure(list(message='progress'),",
    "class=c('callr_message','condition'))); x + 1"
  )))
  expect_identical(result@extra$deputy_r$outcome, "complete")
  expect_match(r_session_text(result), "42")
  expect_match(r_session_text(r_session_await(session$run("x"))), "41")
  expect_identical(session$status()$generation, 1L)
})
