test_that("ellmer exhausts its own HTTP retries before ordered Chat fallback", {
  server <- local_runtime_server(c(
    rep(list(runtime_failure()), 3),
    list(runtime_reply("recovered"))
  ))
  primary <- runtime_chat(
    server,
    model = "primary",
    params = ellmer::params(temperature = 0.1)
  )
  backup <- runtime_chat(
    server,
    model = "backup",
    params = ellmer::params(temperature = 0.2)
  )
  agent <- Agent$new(primary, fallback_chats = list(backup))
  result <- agent$run_sync("task")
  requests <- lapply(server$requests(), `[[`, "body")
  expect_identical(
    vapply(requests, `[[`, character(1), "model"),
    c("primary", "primary", "primary", "backup")
  )
  expect_equal(requests[[4]]$temperature, 0.2)
  expect_length(requests[[4]]$messages, 1L)
  expect_identical(trimws(result$response), "recovered")
  expect_identical(result$usage$requests, 2L)
  expect_identical(result$usage$cost_usd, NA_real_)
  expect_length(runtime_events(agent, "fallback"), 1L)
  expect_length(runtime_events(agent, "request_start"), 2L)
  expect_identical(agent$get_model(), "backup")
  expect_length(backup$get_turns(), 0L)
})

test_that("fallback honors ordering, terminal failures, and request limits", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(
    runtime_failure(),
    runtime_failure(),
    runtime_reply()
  ))
  agent <- Agent$new(
    runtime_chat(server, "a"),
    fallback_chats = list(runtime_chat(server, "b"), runtime_chat(server, "c"))
  )
  expect_identical(trimws(agent$run_sync("task")$response), "done")
  expect_identical(
    vapply(server$requests(), function(x) x$body$model, character(1)),
    c("a", "b", "c")
  )
  expect_identical(agent$last_run()$usage$requests, 3L)

  denied <- local_runtime_server(list(runtime_failure(401L)))
  agent <- Agent$new(
    runtime_chat(denied),
    fallback_chats = list(runtime_chat(server))
  )
  before <- length(server$requests())
  expect_error(agent$run_sync("task"), class = "httr2_http_401")
  expect_length(server$requests(), before)
  expect_identical(agent$last_run()$stop_reason, "error")

  unavailable <- local_runtime_server(list(runtime_failure()))
  agent <- Agent$new(
    runtime_chat(unavailable),
    fallback_chats = list(runtime_chat(server)),
    usage_limits = UsageLimits(max_requests = 1)
  )
  result <- agent$run_sync("task")
  expect_identical(result$stop_reason, "request_limit")
  expect_length(server$requests(), before)
  expect_identical(result$usage$requests, 1L)
})

test_that("a completed side effect is never replayed after a later provider error", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(
    runtime_reply(tool = "effect"),
    runtime_failure()
  ))
  backup <- local_runtime_server(list(runtime_reply("unexpected")))
  effects <- 0L
  tool <- ellmer::tool(
    function() {
      effects <<- effects + 1L
      "changed"
    },
    name = "effect",
    description = "effect"
  )
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(tool),
    permissions = permissions_full(),
    fallback_chats = list(runtime_chat(backup))
  )
  expect_error(agent$run_sync("task"), class = "httr2_http_503")
  expect_identical(effects, 1L)
  expect_length(backup$requests(), 0L)
  expect_identical(agent$last_run()$usage$requests, 2L)
})

test_that("fallback retains the permission ceiling and unknown cost fails closed", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(
    runtime_failure(),
    runtime_reply(tool = "effect"),
    runtime_reply()
  ))
  effects <- 0L
  tool <- ellmer::tool(
    function() {
      effects <<- effects + 1L
      "changed"
    },
    name = "effect",
    description = "effect"
  )
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(tool),
    permissions = Permissions$new(mode = "readonly", tool_denylist = "effect"),
    fallback_chats = list(runtime_chat(server))
  )
  suppressWarnings(agent$run_sync("task"))
  expect_identical(effects, 0L)

  source <- local_runtime_server(list(runtime_failure()))
  backup <- local_runtime_server(list(runtime_reply()))
  limited <- Agent$new(
    runtime_chat(source),
    fallback_chats = list(runtime_chat(backup)),
    usage_limits = UsageLimits(max_cost_usd = 1)
  )
  result <- limited$run_sync("task")
  expect_identical(result$stop_reason, "cost_unavailable")
  expect_length(backup$requests(), 0L)
})

test_that("cancellation and application callback errors never trigger fallback", {
  server <- local_runtime_server(list(runtime_reply()))
  backup <- local_runtime_server(list(runtime_reply()))
  chat <- runtime_chat(server)
  agent <- Agent$new(chat, fallback_chats = list(runtime_chat(backup)))
  chat$on_request_start(function(turns) agent$interrupt())
  expect_identical(agent$run_sync("task")$stop_reason, "interrupted")
  expect_length(backup$requests(), 0L)
  broken <- runtime_chat(server)
  broken$on_request_start(function(turns) cli::cli_abort("application failure"))
  agent <- Agent$new(broken, fallback_chats = list(runtime_chat(backup)))
  expect_error(agent$run_sync("task"), "application failure")
  expect_length(runtime_events(agent, "request_error"), 0L)
  expect_match(
    conditionMessage(runtime_events(agent, "run_error")[[1]]$condition),
    "application failure"
  )
  expect_length(backup$requests(), 0L)
})

test_that("a partial stream is retained without switching or replaying it", {
  server <- local_runtime_server(list(runtime_reply("partial output")))
  backup <- local_runtime_server(list(runtime_reply("unexpected")))
  chat <- runtime_chat(server)
  original <- chat$stream_async
  rlang::env_binding_unlock(chat, "stream_async")
  # Fail the consumer connection after a real producer has yielded content.
  chat$stream_async <- function(
    ...,
    tool_mode = "concurrent",
    stream = "content",
    controller = NULL
  ) {
    incoming <- original(
      ...,
      tool_mode = tool_mode,
      stream = stream,
      controller = controller
    )
    coro::async_generator(function() {
      chunk <- coro::await(incoming())
      coro::yield(chunk)
      controller$cancel()
      coro::await(incoming())
      rlang::abort("fixture connection lost", class = "httr2_failure")
    })()
  }
  agent <- Agent$new(chat, fallback_chats = list(runtime_chat(backup)))
  expect_error(agent$run_sync("task"), "connection lost")
  expect_match(agent$last_run()$response, "partial output")
  expect_length(backup$requests(), 0L)
  expect_identical(agent$last_run()$stop_reason, "error")
})

test_that("observer removers follow the selected Chat and templates keep their callbacks", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(
    runtime_failure(),
    runtime_reply(tool = "effect"),
    runtime_reply(),
    runtime_reply(tool = "effect"),
    runtime_reply()
  ))
  template_calls <- 0L
  observer_calls <- 0L
  template <- runtime_chat(server)
  template$on_tool_request(function(request) {
    template_calls <<- template_calls + 1L
  })
  tool <- ellmer::tool(
    function() "done",
    name = "effect",
    description = "effect"
  )
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(tool),
    permissions = permissions_full(),
    fallback_chats = list(template)
  )
  remove <- agent$on_tool_request(function(request) {
    observer_calls <<- observer_calls + 1L
  })
  agent$run_sync("task")
  remove()
  agent$run_sync("next task")
  expect_identical(observer_calls, 1L)
  expect_identical(template_calls, 2L)
})

test_that("synchronous fallback configuration failures cannot report completion", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(runtime_failure()))
  backup <- runtime_chat(server)
  rlang::env_binding_unlock(backup, "stream_async")
  backup$stream_async <- function(...) {
    cli::cli_abort("invalid backup configuration")
  }
  agent <- Agent$new(runtime_chat(server), fallback_chats = list(backup))
  expect_error(agent$run_sync("task"), "invalid backup configuration")
  expect_identical(agent$last_run()$stop_reason, "error")
  expect_false(agent$.__enclos_env__$private$run_active)
  expect_length(runtime_events(agent, "request_error"), 1L)
  expect_match(
    conditionMessage(runtime_events(agent, "run_error")[[1]]$condition),
    "invalid backup configuration"
  )
})

test_that("request-end callback errors are run failures regardless of callback order", {
  for (order in c("before", "after")) {
    server <- local_runtime_server(list(runtime_reply("response received")))
    backup <- local_runtime_server(list(runtime_reply("unexpected")))
    chat <- runtime_chat(server)
    callback <- function(turn) {
      rlang::abort(
        "application callback failed",
        class = "fixture_callback_error"
      )
    }
    if (order == "before") {
      chat$on_request_end(callback)
    }
    agent <- Agent$new(chat, fallback_chats = list(runtime_chat(backup)))
    if (order == "after") {
      agent$add_hook(HookMatcher$new(
        "SessionStart",
        function(...) {
          chat$on_request_end(callback)
          NULL
        },
        timeout = 0
      ))
    }
    expect_error(agent$run_sync("task"), class = "fixture_callback_error")
    expect_length(runtime_events(agent, "request_error"), 0L)
    # ellmer owns callback delivery order; verify the request actually ran
    # without requiring Deputy's end observer to precede the failing callback.
    expect_length(server$requests(), 1L)
    expect_s3_class(
      runtime_events(agent, "run_error")[[1]]$condition,
      "fixture_callback_error"
    )
    expect_identical(agent$last_run()$usage$requests, 1L)
    expect_identical(agent$last_run()$stop_reason, "error")
    expect_length(backup$requests(), 0L)
  }
})
