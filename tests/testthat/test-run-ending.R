test_that("every stop reason deputy sets maps to exactly one ending", {
  endings <- c(
    stats::setNames(
      rep("RunEndingLimit", length(run_ending_limit_reasons)),
      run_ending_limit_reasons
    ),
    stats::setNames(
      rep("RunEndingFailed", length(run_ending_failure_reasons)),
      run_ending_failure_reasons
    ),
    stats::setNames(
      rep("RunEndingStopped", length(run_ending_stop_reasons)),
      names(run_ending_stop_reasons)
    ),
    complete = "RunEndingAnswered",
    made_up_reason = "RunEndingStopped"
  )

  for (reason in names(endings)) {
    ending <- AgentResult(stop_reason = reason)$ending
    expected_class <- get(endings[[reason]], envir = asNamespace("deputy"))
    expect_true(
      S7::S7_inherits(ending, expected_class),
      info = reason
    )
  }
})

test_that("an AgentResult takes an ending, or derives it from its stop reason", {
  given <- AgentResult(stop_reason = "complete", ending = RunEndingAnswered())
  expect_s7_class(given$ending, RunEndingAnswered)

  derived <- AgentResult(stop_reason = "interrupted")
  expect_s7_class(derived$ending, RunEndingStopped)

  expect_error(
    AgentResult(stop_reason = "complete", ending = "answered"),
    "must be NULL or a RunEnding"
  )
})

test_that("endings validate their fields and are read-only", {
  expect_error(RunEndingStopped("nobody"), "should be one of")
  expect_error(RunEndingStopped("hook", reason = c("a", "b")), "reason")
  expect_error(RunEndingLimit("out_of_budget"), "should be one of")
  expect_error(RunEndingLimit("request_limit", actual = "3"), "actual")
  expect_error(RunEndingCutOff("stop"), "should be one of")
  expect_error(RunEndingFailed(reason = ""), "reason")
  expect_error(RunEndingFailed(error = "boom"), "error")

  stopped <- RunEndingStopped("hook", reason = "enough")
  expect_error(S7::prop(stopped, "by") <- "caller", "read-only")
  expect_error(S7::prop(stopped, "reason") <- NULL, "read-only")

  limit <- RunEndingLimit(
    "request_limit",
    field = "max_requests",
    actual = 3,
    limit = 3
  )
  expect_error(S7::prop(limit, "actual") <- 4, "read-only")
})

test_that("an ending prints and survives saveRDS in a fresh process", {
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  endings <- list(
    answered = RunEndingAnswered(),
    stopped = RunEndingStopped("hook", reason = "enough"),
    limit = RunEndingLimit(
      "request_limit",
      field = "max_requests",
      actual = 3,
      limit = 3
    ),
    cut_off = RunEndingCutOff("max_tokens"),
    failed = RunEndingFailed(
      "error",
      error = simpleError("boom"),
      phase = "stream"
    )
  )
  saveRDS(endings, path)

  restored <- callr::r(
    function(path, package_path) {
      if (file.exists(file.path(package_path, "R", "agent.R"))) {
        pkgload::load_all(package_path, quiet = TRUE)
      } else {
        library(deputy, lib.loc = dirname(package_path))
      }
      values <- readRDS(path)
      ns <- asNamespace("deputy")
      list(
        classes = list(
          answered = S7::S7_inherits(values$answered, ns$RunEndingAnswered),
          stopped = S7::S7_inherits(values$stopped, ns$RunEndingStopped),
          limit = S7::S7_inherits(values$limit, ns$RunEndingLimit),
          cut_off = S7::S7_inherits(values$cut_off, ns$RunEndingCutOff),
          failed = S7::S7_inherits(values$failed, ns$RunEndingFailed)
        ),
        by = values$stopped$by,
        output = lapply(values, function(value) capture.output(print(value)))
      )
    },
    args = list(
      path = path,
      package_path = getNamespaceInfo(asNamespace("deputy"), "path")
    )
  )

  expect_true(all(unlist(restored$classes)))
  expect_identical(restored$by, "hook")
  expect_identical(
    restored$output$stopped,
    capture.output(print(endings$stopped))
  )
  expect_true(any(grepl("<RunEndingStopped>", restored$output$stopped)))
  expect_true(any(grepl("by: hook", restored$output$stopped)))
  expect_true(any(grepl("reason: enough", restored$output$stopped)))
  expect_true(any(grepl("boom", restored$output$failed)))
  expect_true(any(grepl("<RunEndingAnswered>", restored$output$answered)))
})

test_that("a run the model finishes ends answered", {
  mock_chat <- create_mock_chat(responses = list("Hello, world!"))
  mock_chat$stream <- function(prompt = NULL) {
    yielded <- FALSE
    function() {
      if (yielded) {
        return(coro::exhausted())
      }
      yielded <<- TRUE
      "Hello, world!"
    }
  }
  mock_chat$last_turn <- function(role = "assistant") {
    create_mock_assistant_turn(text = "Hello, world!")
  }
  agent <- Agent$new(chat = mock_chat)

  result <- agent$run_sync("Say hello")

  expect_identical(result$stop_reason, "complete")
  expect_s7_class(result$ending, RunEndingAnswered)
})

test_that("an interrupted run ends stopped by the caller, with the reason it gave", {
  mock <- create_content_stream_chat()
  root <- withr::local_tempdir(pattern = "deputy-endings-")
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    working_dir = root
  )

  generator <- agent$run("Read input.txt")
  expect_identical(generator()$type, "start")
  expect_true(agent$interrupt("because I said so"))
  collect_agent_events(generator)

  run <- agent$last_run()
  expect_identical(run$stop_reason, "because I said so")
  expect_s7_class(run$ending, RunEndingStopped)
  expect_identical(run$ending$by, "caller")
  expect_identical(run$ending$reason, "because I said so")
})

test_that("a run a hook stops ends stopped by a hook", {
  run_with_hook_stop <- function(stop_reason = NULL) {
    mock <- create_content_stream_chat()
    root <- withr::local_tempdir(pattern = "deputy-endings-")
    agent <- Agent$new(
      chat = mock$chat,
      tools = list(mock$tool),
      permissions = permissions_standard(root),
      working_dir = root
    )
    agent$hooks$add(HookMatcher(
      event = "PreToolUse",
      timeout = 0,
      callback = function(tool_name, tool_input, context) {
        HookResultPreToolUse(
          permission = "allow",
          continue = FALSE,
          stop_reason = stop_reason
        )
      }
    ))
    agent$run_sync("Read input.txt")
    agent$last_run()
  }

  run <- run_with_hook_stop()
  expect_s7_class(run$ending, RunEndingStopped)
  expect_identical(run$ending$by, "hook")
  expect_identical(run$ending$reason, "hook_requested_stop")

  run <- run_with_hook_stop(stop_reason = "enough")
  expect_identical(run$stop_reason, "enough")
  expect_s7_class(run$ending, RunEndingStopped)
  expect_identical(run$ending$by, "hook")
  expect_identical(run$ending$reason, "enough")

  # A hook may give one of deputy's own words as its reason. It is still the
  # hook that stopped the run.
  run <- run_with_hook_stop(stop_reason = "interrupted")
  expect_identical(run$stop_reason, "interrupted")
  expect_identical(run$ending$by, "hook")
})

test_that("who asked for a stop is kept when the reason is one of deputy's own words", {
  # Recorded at the stop, so it wins over what the word usually means.
  expect_identical(run_ending_for("interrupted", by = "hook")$by, "hook")
  expect_identical(
    run_ending_for("hook_requested_stop", by = "caller")$by,
    "caller"
  )
  # With nobody recorded, the word decides.
  expect_identical(run_ending_for("abandoned")$by, "abandoned")
  expect_identical(run_ending_for("hook_requested_stop")$by, "hook")
  # A parent's end reaches its child as a stop recorded as the parent's, so
  # a caller who gives the same word is still the caller.
  expect_identical(
    run_ending_for("parent_completed", by = "parent")$by,
    "parent"
  )
  expect_identical(
    run_ending_for("parent_completed", by = "caller")$by,
    "caller"
  )
  expect_identical(run_ending_for("parent_completed")$by, "parent")
})

test_that("a caller who interrupts with the parent's word is still the one who stopped the run", {
  agent <- Agent$new(create_mock_chat(list("never sent")))

  stream <- agent$stream_async("go")
  expect_true(agent$interrupt("parent_completed"))
  collect_async_stream(stream)

  result <- agent$last_run()
  expect_identical(result$stop_reason, "parent_completed")
  expect_identical(result$ending@by, "caller")
})

test_that("a child stopped because its parent's run ended is stopped by the parent", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  root_server <- local_runtime_server(list(
    runtime_reply(tool = "launch"),
    runtime_reply("root finished")
  ))
  delayed <- runtime_reply("late child")
  attr(delayed, "fixture_delay") <- 0.15
  child_server <- local_runtime_server(list(delayed))
  root <- Agent$new(runtime_chat(root_server), permissions = permissions_full())
  child <- Agent$new(
    runtime_chat(child_server),
    permissions = permissions_full()
  )
  pending <- NULL
  handle <- NULL
  root$register_tool(ellmer::tool(
    function() {
      pending <<- root$continue_agent_async(
        handle,
        "background child",
        UsageLimits(max_requests = 1)
      )
      # What the root's run does for its descendants when it ends.
      graph_cancel_descendants(root, "parent_completed", by = "parent")
      "launched"
    },
    name = "launch",
    description = "Launch retained child",
    arguments = list()
  ))
  handles <- root$retain_agent_graph(
    agents = list(child = child),
    routes = list(),
    usage_limits = UsageLimits(max_requests = 4),
    max_depth = 1,
    max_delegations = 2,
    max_concurrency = 1
  )
  handle <- handles[[1L]]

  root$run_sync("launch")
  child_result <- resolve_async_value(pending)

  expect_identical(child_result$stop_reason, "parent_completed")
  expect_s7_class(child_result$ending, RunEndingStopped)
  expect_identical(child_result$ending@by, "parent")
  root$release_agent_graph()
})

test_that("a run that reaches a limit ends at that limit, with its figures", {
  mock <- create_content_stream_chat()
  root <- withr::local_tempdir(pattern = "deputy-endings-")
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    usage_limits = UsageLimits(max_requests = 5, max_tool_calls = 0),
    working_dir = root
  )

  result <- agent$run_sync("Read input.txt")

  expect_identical(result$stop_reason, "tool_call_limit")
  expect_s7_class(result$ending, RunEndingLimit)
  expect_identical(result$ending$reason, "tool_call_limit")
  expect_identical(result$ending$field, "max_tool_calls")
  expect_equal(result$ending$actual, 1)
  expect_equal(result$ending$limit, 0)
})

test_that("a run the provider cuts short ends cut off", {
  server <- local_runtime_server(list(
    runtime_reply(text = "partial", finish = "length")
  ))
  agent <- Agent$new(runtime_chat(server))

  result <- NULL
  expect_warning(
    result <- agent$run_sync("Write a long answer"),
    "truncated"
  )

  expect_identical(result$stop_reason, "complete")
  expect_s7_class(result$ending, RunEndingCutOff)
  expect_identical(result$ending$finish_reason, "max_tokens")
})

test_that("a run that fails ends failed, with its error and phase", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      stop("stream failed")
    })()
  }
  agent <- Agent$new(chat = chat)

  expect_error(resolve_async_value(agent$run_async("x")), "stream failed")

  run <- agent$last_run()
  expect_identical(run$stop_reason, "error")
  expect_s7_class(run$ending, RunEndingFailed)
  expect_s3_class(run$ending$error, "condition")
  expect_identical(conditionMessage(run$ending$error), "stream failed")
  expect_identical(run$ending$phase, "stream")
})

test_that("the stop event carries the run's ending", {
  mock <- create_content_stream_chat()
  root <- withr::local_tempdir(pattern = "deputy-endings-")
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    working_dir = root
  )

  result <- agent$run_sync("Read input.txt")

  stops <- Filter(function(event) event$type == "stop", result$events)
  expect_length(stops, 1L)
  expect_s7_class(stops[[1]]$ending, RunEndingAnswered)
  expect_identical(stops[[1]]$ending, result$ending)
})
