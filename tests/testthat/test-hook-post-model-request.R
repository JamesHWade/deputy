test_that("PostModelRequest is a hook event whose callback takes a context", {
  expect_true("PostModelRequest" %in% HookEvent)

  matcher <- HookMatcher(
    event = "PostModelRequest",
    callback = function(context) NULL
  )
  expect_equal(matcher@event, "PostModelRequest")

  expect_error(HookMatcher(
    event = "PostModelRequest",
    callback = function(usage, limits) NULL
  ))
})

test_that("PostModelRequest fires after each model request with the run's usage so far", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  agent$register_tool(ellmer::tool(
    function() "probed",
    name = "probe",
    description = "Probe."
  ))
  contexts <- list()
  agent$add_hook(HookMatcher(
    event = "PostModelRequest",
    callback = function(context) {
      contexts <<- c(contexts, list(context))
      NULL
    }
  ))

  result <- agent$run_sync("task")

  expect_identical(
    vapply(contexts, function(context) context$request_number, integer(1)),
    c(1L, 2L)
  )
  expect_identical(
    vapply(contexts, function(context) context$usage$requests, integer(1)),
    c(1L, 2L)
  )
  expect_true(all(vapply(
    contexts,
    function(context) S7::S7_inherits(context$usage, AgentUsage),
    logical(1)
  )))
  expect_true(all(vapply(
    contexts,
    function(context) S7::S7_inherits(context$usage_limits, UsageLimits),
    logical(1)
  )))
  expect_identical(contexts[[2]]$run_id, result$run_id)
})

test_that("PostModelRequest fires for a run that calls no tools", {
  server <- local_runtime_server(list(runtime_reply("answer")))
  agent <- Agent$new(runtime_chat(server))
  fired <- 0L
  agent$add_hook(HookMatcher(
    event = "PostModelRequest",
    callback = function(context) {
      fired <<- fired + 1L
      NULL
    }
  ))

  agent$run_sync("task")

  expect_identical(fired, 1L)
})

test_that("the next model request waits for a PostModelRequest hook's promise", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  agent$register_tool(ellmer::tool(
    function() "probed",
    name = "probe",
    description = "Probe."
  ))
  seen <- integer()
  agent$add_hook(HookMatcher(
    event = "PostModelRequest",
    callback = function(context) {
      promises::then(later_value(NULL, 0.1), function(value) {
        seen <<- c(seen, length(server$requests()))
        value
      })
    }
  ))

  result <- resolve_async_value(agent$run_async("task"), max_polls = 500L)

  expect_identical(seen, c(1L, 2L))
  expect_identical(trimws(result$response), "final answer")
})

test_that("an interrupt while a PostModelRequest hook is pending ends the run before the next request", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  agent$register_tool(ellmer::tool(
    function() "probed",
    name = "probe",
    description = "Probe."
  ))
  agent$add_hook(HookMatcher(
    event = "PostModelRequest",
    callback = function(context) {
      later::later(function() agent$interrupt("enough"), 0.05)
      later_value(NULL, 0.3)
    }
  ))

  result <- resolve_async_value(agent$run_async("task"), max_polls = 500L)

  expect_length(server$requests(), 1L)
  expect_identical(result$stop_reason, "enough")
})

test_that("a PostModelRequest hook that fails does not stop the run", {
  server <- local_runtime_server(list(runtime_reply("answer")))
  agent <- Agent$new(runtime_chat(server))
  agent$add_hook(HookMatcher(
    event = "PostModelRequest",
    callback = function(context) stop("hook broke")
  ))

  result <- agent$run_sync("task")

  expect_identical(result$stop_reason, "complete")
  expect_identical(trimws(result$response), "answer")
  errors <- agent$hooks$last_errors()
  expect_length(errors, 1L)
  expect_identical(errors[[1]]$event, "PostModelRequest")
  expect_match(errors[[1]]$error, "hook broke")
})
