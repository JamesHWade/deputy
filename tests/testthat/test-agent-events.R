test_that("content streams expose tool lifecycle before and after execution", {
  mock <- create_content_stream_chat()
  root <- withr::local_tempdir(pattern = "deputy-events-")
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    usage_limits = UsageLimits(max_requests = 5),
    working_dir = root
  )

  generator <- agent$run("Read input.txt")
  start <- generator()
  tool_start <- generator()

  expect_identical(start$type, "start")
  expect_identical(tool_start$type, "tool_start")
  expect_identical(tool_start$tool_call_id, "tool-use-1")
  expect_false(mock$state$tool_executed)

  tool_end <- generator()
  expect_true(mock$state$tool_executed)
  expect_identical(tool_end$type, "tool_end")
  expect_identical(tool_end$tool_result, "contents")

  remaining <- collect_agent_events(generator)
  all_events <- c(list(start, tool_start, tool_end), remaining)
  run_ids <- vapply(all_events, function(event) event$run_id, character(1))
  expect_length(unique(run_ids), 1L)
  expect_true(all(
    c("text", "text_complete", "turn", "usage", "stop") %in%
      vapply(all_events, function(event) event$type, character(1))
  ))

  usage <- Filter(function(event) event$type == "usage", all_events)[[1]]$usage
  expect_identical(usage$requests, 2L)
  expect_identical(usage$tool_calls, 1L)
  expect_equal(usage$total_tokens, 18)
  expect_equal(usage$cost_usd, 0.015)
})

test_that("post-tool hooks can redact emitted tool results", {
  mock <- create_content_stream_chat(tool_result = "secret")
  root <- withr::local_tempdir(pattern = "deputy-events-")
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    working_dir = root
  )
  agent$add_hook(HookMatcher$new(
    event = "PostToolUse",
    timeout = 0,
    callback = function(tool_name, tool_result, tool_error, context) {
      HookResultPostToolUse(updated_tool_output = "[redacted]")
    }
  ))

  result <- agent$run_sync("Read input.txt")

  expect_length(result$tool_calls(), 1L)
  expect_length(result$tool_results(), 1L)
  expect_identical(result$tool_results()[[1]]$tool_result, "[redacted]")
  expect_false(result$tool_results()[[1]]$suppressed)
})

test_that("interrupt cooperatively stops an active run", {
  mock <- create_content_stream_chat()
  root <- withr::local_tempdir(pattern = "deputy-events-")
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    working_dir = root
  )

  generator <- agent$run("Read input.txt")
  expect_identical(generator()$type, "start")
  expect_true(agent$interrupt("user_interrupted"))

  events <- collect_agent_events(generator)
  stop <- Filter(function(event) event$type == "stop", events)[[1]]
  expect_identical(stop$reason, "user_interrupted")
  expect_false(mock$state$tool_executed)
  expect_false(agent$interrupt())
})

test_that("interrupt counts an already-dispatched request without an assistant turn", {
  chat <- create_mock_chat("unused")
  stream_async <- chat$stream_async
  dispatched <- 0L
  chat$stream_async <- function(...) {
    dispatched <<- dispatched + 1L
    stream_async(...)
  }
  agent <- Agent$new(chat = chat)
  generator <- agent$run("cancel")
  expect_identical(generator()$type, "start")
  expect_identical(dispatched, 1L)
  agent$.__enclos_env__$private$current_stream_controller <- NULL
  expect_true(agent$interrupt("cancelled"))

  events <- collect_agent_events(generator)
  stop <- Filter(function(event) event$type == "stop", events)[[1L]]
  expect_identical(stop$reason, "cancelled")
  expect_identical(stop$usage$requests, 1L)
})

test_that("cancellation during run initialization makes no provider request", {
  chat <- create_mock_chat("unused")
  chat$stream_async <- function(...) cli::cli_abort("unexpected dispatch")
  agent <- Agent$new(chat = chat)
  agent$add_hook(HookMatcher$new(
    event = "SessionStart",
    timeout = 0,
    callback = function(...) {
      agent$interrupt("cancelled")
      NULL
    }
  ))
  result <- agent$run_sync("cancel")
  expect_identical(result$stop_reason, "cancelled")
  expect_identical(result$usage$requests, 0L)
})

test_that("interrupt stops native streams that ignore their controller", {
  chat <- create_mock_chat("unused")
  chunks <- c("one", "two", "three")
  chat$stream <- function(
    prompt = NULL,
    stream = c("text", "content"),
    controller = NULL
  ) {
    index <- 0L
    function() {
      index <<- index + 1L
      if (index > length(chunks)) {
        return(coro::exhausted())
      }
      chunks[[index]]
    }
  }
  chat$last_turn <- function(role = "assistant") {
    create_mock_assistant_turn("one")
  }
  agent <- Agent$new(chat = chat)
  generator <- agent$run("stream")

  expect_identical(generator()$type, "start")
  first <- generator()
  expect_identical(first$type, "text")
  expect_identical(first$text, "one")
  expect_true(agent$interrupt("user_cancelled"))
  remaining <- collect_agent_events(generator)

  text <- vapply(
    Filter(function(event) event$type == "text", remaining),
    function(event) event$text,
    character(1)
  )
  expect_false(any(text %in% c("two", "three")))
  stop <- Filter(function(event) event$type == "stop", remaining)[[1L]]
  expect_identical(stop$reason, "user_cancelled")
})

test_that("tool-call limits reject execution and return a typed stop", {
  mock <- create_content_stream_chat()
  root <- withr::local_tempdir(pattern = "deputy-events-")
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    usage_limits = UsageLimits(max_requests = 5, max_tool_calls = 0),
    working_dir = root
  )

  result <- agent$run_sync("Read input.txt")

  expect_identical(result$stop_reason, "tool_call_limit")
  expect_false(mock$state$tool_executed)
  expect_true(mock$state$tool_rejected)
  expect_identical(result$usage$tool_calls, 1L)
  expect_length(result$tool_calls(), 1L)
  expect_length(result$tool_results(), 1L)
  expect_match(result$tool_results()[[1]]$tool_error, "Run limit reached")
})

test_that("error mode signals structured limit conditions", {
  agent <- Agent$new(chat = create_mock_chat("unused"))

  error <- tryCatch(
    agent$run_sync(
      "Do not call the provider",
      usage_limits = UsageLimits(max_requests = 0, on_exceed = "error")
    ),
    deputy_request_limit = function(error) error
  )

  expect_s3_class(error, "deputy_request_limit")
  expect_identical(error$current_requests, 0L)
  expect_identical(error$max_requests, 0L)
  expect_match(error$run_id, "^run_")
})

test_that("run-level usage overrides keep unspecified agent defaults", {
  mock <- create_content_stream_chat()
  root <- withr::local_tempdir(pattern = "deputy-events-")
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    usage_limits = UsageLimits(
      max_requests = 5,
      max_output_tokens = 200,
      max_cost_usd = 0.25,
      on_exceed = "error"
    ),
    working_dir = root
  )

  generator <- agent$run(
    "Read input.txt",
    usage_limits = UsageLimits(max_tool_calls = 2)
  )
  start <- generator()

  expect_identical(start$usage_limits$max_requests, 5L)
  expect_identical(start$usage_limits$max_tool_calls, 2L)
  expect_identical(start$usage_limits$max_output_tokens, 200L)
  expect_equal(start$usage_limits$max_cost_usd, 0.25)
  expect_identical(start$usage_limits$on_exceed, "stop")

  collect_agent_events(generator)
})

test_that("lazy run generators cannot overlap", {
  mock <- create_content_stream_chat()
  root <- withr::local_tempdir(pattern = "deputy-events-")
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    working_dir = root
  )

  first <- agent$run("First run")
  second <- agent$run("Second run")

  expect_identical(first()$type, "start")
  expect_error(second(), class = "deputy_run_active")
  expect_error(agent$run("Third run"), class = "deputy_run_active")

  events <- collect_agent_events(first)
  expect_true(any(vapply(
    events,
    function(event) event$type == "stop",
    logical(1)
  )))
  expect_false(agent$.__enclos_env__$private$run_active)

  followup <- agent$run("Follow-up run")
  expect_identical(followup()$type, "start")
  collect_agent_events(followup)
})

test_that("abandoned native generators release their active run", {
  chat <- create_mock_chat("done")
  agent <- Agent$new(chat = chat)
  generator <- agent$run("first")

  expect_identical(generator()$type, "start")
  expect_true(agent$.__enclos_env__$private$run_active)
  expect_true(agent$interrupt("abandoned"))
  generator <- NULL
  invisible(gc())

  expect_false(agent$.__enclos_env__$private$run_active)
  next_run <- agent$run("next")
  expect_identical(next_run()$type, "start")
})

test_that("exhausting an old terminal generator cannot clear a newer run", {
  mock <- create_content_stream_chat()
  root <- withr::local_tempdir(pattern = "deputy-events-")
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    working_dir = root
  )

  first <- agent$run("First run")
  first_events <- collect_agent_events(first)
  expect_identical(tail(first_events, 1L)[[1]]$type, "stop")

  second <- agent$run("Second run")
  expect_identical(second()$type, "start")
  expect_true(agent$.__enclos_env__$private$run_active)

  expect_true(coro::is_exhausted(first()))
  expect_true(agent$.__enclos_env__$private$run_active)
  collect_agent_events(second)
})

test_that("relative native tool paths execute inside Agent working_dir", {
  root <- withr::local_tempdir(pattern = "deputy-workspace-")
  outside <- withr::local_tempdir(pattern = "deputy-process-cwd-")
  writeLines("before", file.path(root, "input.txt"))
  writeLines("outside", file.path(outside, "input.txt"))
  agent <- NULL
  mock <- create_content_stream_chat(
    tool_name = "write_file",
    tool_result = "input.txt",
    execute = function(request) {
      do.call(agent$get_tools()[["write_file"]], request@arguments)
    }
  )
  mock$tool <- ellmer::tool(
    fun = function(path) {
      writeLines("after", path)
      path
    },
    name = "write_file",
    description = "Write a test file.",
    arguments = list(path = ellmer::type_string("File path"))
  )
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    enable_file_checkpointing = TRUE,
    working_dir = root
  )
  checkpoint_id <- agent$checkpoint("before relative write")
  withr::local_dir(outside)

  agent$run_sync("Write input.txt")

  expect_identical(
    normalizePath(getwd(), winslash = "/"),
    normalizePath(outside, winslash = "/")
  )
  expect_identical(readLines(file.path(root, "input.txt")), "after")
  expect_identical(readLines(file.path(outside, "input.txt")), "outside")

  agent$rewind_files(checkpoint_id)
  expect_identical(readLines(file.path(root, "input.txt")), "before")
})

test_that("cancellation before the first chunk never falls back", {
  fallback_calls <- 0L
  agent <- NULL
  chat <- create_mock_chat("fallback response")
  chat$chat <- function(prompt = NULL) {
    fallback_calls <<- fallback_calls + 1L
    "fallback response"
  }
  stale_turn <- create_mock_assistant_turn("stale prior turn")
  chat$get_turns <- function() list(stale_turn)
  chat$last_turn <- function(role = "assistant") stale_turn
  chat$stream <- function(
    prompt = NULL,
    stream = c("text", "content"),
    controller = NULL
  ) {
    function() {
      agent$interrupt("user_cancelled")
      stop("cancelled before first chunk")
    }
  }
  agent <- Agent$new(chat = chat)

  generator <- agent$run("Cancel immediately")
  expect_identical(generator()$type, "start")
  events <- collect_agent_events(generator)
  stop <- Filter(function(event) event$type == "stop", events)[[1]]

  expect_identical(fallback_calls, 0L)
  expect_false(any(vapply(
    events,
    function(event) identical(event$type, "turn"),
    logical(1)
  )))
  expect_false(any(vapply(
    events,
    function(event) identical(event$code, "stream_fallback"),
    logical(1)
  )))
  expect_identical(stop$reason, "user_cancelled")
})

test_that("stream failures are surfaced without a second provider request", {
  for (failure_mode in c("stream_setup", "first_chunk")) {
    chat_calls <- 0L
    chat <- create_mock_chat("fallback response")
    chat$stream <- if (identical(failure_mode, "stream_setup")) {
      function(
        prompt = NULL,
        stream = c("text", "content"),
        controller = NULL
      ) {
        stop("stream setup failed")
      }
    } else {
      function(
        prompt = NULL,
        stream = c("text", "content"),
        controller = NULL
      ) {
        function() stop("first chunk failed")
      }
    }
    chat$chat <- function(prompt = NULL) {
      chat_calls <<- chat_calls + 1L
      "fallback response"
    }

    root <- withr::local_tempdir(pattern = "deputy-fallback-")
    agent <- Agent$new(
      chat = chat,
      permissions = permissions_standard(root),
      working_dir = root
    )

    expect_error(
      agent$run_sync("Read input.txt"),
      paste0(gsub("_", " ", failure_mode), " failed"),
      fixed = TRUE,
      info = failure_mode
    )
    expect_identical(chat_calls, 0L, info = failure_mode)
    expect_false(agent$.__enclos_env__$private$run_active)
  }
})

test_that("run_sync never returns a prior turn after an early stop", {
  mock <- create_content_stream_chat()
  mock$state$turns <- list(create_mock_assistant_turn("stale response"))
  agent <- Agent$new(chat = mock$chat)

  result <- agent$run_sync(
    "Do not call the provider",
    usage_limits = UsageLimits(max_requests = 0),
    output_format = list(type = "json_object")
  )

  expect_null(result$response)
  expect_null(result$structured_output)
  expect_identical(result$stop_reason, "request_limit")
})

test_that("pre-tool effects are applied before a real hook rejection", {
  mock <- create_content_stream_chat()
  root <- withr::local_tempdir(pattern = "deputy-events-")
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    working_dir = root
  )
  agent$add_hook(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      HookResultPreToolUse(
        permission = "deny",
        reason = "Rejected after effects",
        continue = FALSE,
        additional_context = "Persist this hook context",
        stop_reason = "hook_policy_stop"
      )
    }
  ))
  request <- ellmer::ContentToolRequest(
    id = "hook-order",
    name = "read_file",
    arguments = list(path = file.path(root, "input.txt")),
    tool = mock$tool
  )

  rejection <- tryCatch(
    agent$.__enclos_env__$private$handle_tool_request(request),
    ellmer_tool_reject = function(error) error
  )

  expect_s3_class(rejection, "ellmer_tool_reject")
  expect_true(agent$.__enclos_env__$private$should_stop)
  expect_identical(
    agent$.__enclos_env__$private$stop_reason_from_hook,
    "hook_policy_stop"
  )
  expect_match(mock$chat$get_system_prompt(), "Persist this hook context")
})

test_that("malformed tool identity is rejected before permission checks", {
  checked <- new.env(parent = emptyenv())
  checked$value <- FALSE
  permissions <- Permissions$new(
    mode = "standard",
    can_use_tool = function(tool_name, tool_input, context) {
      checked$value <- TRUE
      PermissionResultAllow()
    }
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    permissions = permissions
  )
  request <- create_mock_tool_request(name = "run_bash")
  attr(request, "name") <- list("run_bash")

  expect_snapshot(
    agent$.__enclos_env__$private$handle_tool_request(request),
    error = TRUE
  )

  expect_false(checked$value)
  expect_identical(agent$.__enclos_env__$private$current_tool_calls, 0L)
})
