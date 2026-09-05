test_that("ellmer sends the schema and converts data through the governed API", {
  server <- local_runtime_server(list(runtime_reply(
    '{"status":"ok"}',
    stream = FALSE
  )))
  agent <- Agent$new(runtime_chat(server))
  type <- ellmer::type_from_schema(
    '{"type":"object","properties":{"status":{"type":"string"}},"required":["status"],"additionalProperties":false}'
  )
  expect_identical(
    agent$chat_structured("extract", type = type),
    list(status = "ok")
  )
  request <- server$requests()[[1]]$body
  expect_identical(request$response_format$type, "json_schema")
  expect_identical(
    request$response_format$json_schema$schema$properties$status$type,
    "string"
  )
  expect_null(request$tools)
  expect_identical(agent$last_run()$usage$requests, 1L)
  expect_length(runtime_events(agent, "structured_attempt"), 1L)
})

test_that("tool work, extraction, and corrections share one run without replay", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "effect"),
    runtime_reply("work complete"),
    runtime_reply('{"count":0}', stream = FALSE),
    runtime_reply('{"count":1}', stream = FALSE)
  ))
  effects <- 0L
  tool <- ellmer::tool(
    function() {
      effects <<- effects + 1L
      "written"
    },
    name = "effect",
    description = "Perform effect"
  )
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(tool),
    permissions = permissions_full()
  )
  starts <- 0L
  agent$add_hook(HookMatcher$new(
    "SessionStart",
    function(...) {
      starts <<- starts + 1L
      NULL
    },
    timeout = 0
  ))
  result <- agent$run_sync(
    "perform the task",
    type = ellmer::type_object(count = ellmer::type_integer()),
    validate = function(x) if (x$count == 1L) TRUE else "count must equal 1",
    max_corrections = 1
  )
  expect_identical(result$structured_output, list(count = 1L))
  expect_identical(trimws(result$response), "work complete")
  expect_identical(result$stop_reason, "complete")
  expect_identical(effects, 1L)
  expect_identical(starts, 1L)
  expect_identical(result$usage$requests, 4L)
  requests <- lapply(server$requests(), `[[`, "body")
  expect_length(requests[[1]]$tools, 1L)
  expect_null(requests[[3]]$tools)
  expect_null(requests[[4]]$tools)
  attempts <- runtime_events(agent, "structured_attempt")
  expect_identical(vapply(attempts, `[[`, logical(1), "valid"), c(FALSE, TRUE))
  expect_identical(attempts[[1]]$value, list(count = 0L))
  expect_identical(
    unique(vapply(result$events, `[[`, character(1), "run_id")),
    result$run_id
  )
})

test_that("corrections stop at finite attempt and shared request limits", {
  server <- local_runtime_server(list(runtime_reply(
    '{"count":0}',
    stream = FALSE
  )))
  agent <- Agent$new(
    runtime_chat(server),
    usage_limits = UsageLimits(max_requests = 2)
  )
  type <- ellmer::type_object(count = ellmer::type_integer())
  expect_error(
    agent$chat_structured(
      "extract",
      type = type,
      validate = function(x) FALSE,
      max_corrections = 1
    ),
    class = "deputy_structured_output_invalid"
  )
  expect_length(server$requests(), 2L)
  expect_identical(agent$last_run()$stop_reason, "error")
  expect_identical(agent$last_run()$usage$requests, 2L)
  expect_null(agent$chat_structured(
    "extract",
    type = type,
    validate = function(x) FALSE,
    max_corrections = 5
  ))
  expect_length(server$requests(), 4L)
  expect_identical(agent$last_run()$stop_reason, "request_limit")
  expect_false(agent$.__enclos_env__$private$run_active)
})

test_that("unavailable validators and cancellation do not initiate correction", {
  server <- local_runtime_server(list(runtime_reply(
    '{"count":0}',
    stream = FALSE
  )))
  agent <- Agent$new(runtime_chat(server))
  type <- ellmer::type_object(count = ellmer::type_integer())
  expect_error(
    agent$chat_structured(
      "extract",
      type = type,
      validate = function(x) NA,
      max_corrections = 5
    ),
    class = "deputy_validation_unavailable"
  )
  expect_length(server$requests(), 1L)
  agent$chat_structured(
    "extract",
    type = type,
    validate = function(x) {
      agent$interrupt()
      FALSE
    },
    max_corrections = 5
  )
  expect_length(server$requests(), 2L)
  expect_identical(agent$last_run()$stop_reason, "interrupted")
})

test_that("invalid JSON has bounded evidence and terminal provider errors are not corrections", {
  server <- local_runtime_server(list(
    runtime_reply('{"count":', stream = FALSE),
    runtime_reply('{"count":1}', stream = FALSE)
  ))
  agent <- Agent$new(runtime_chat(server))
  type <- ellmer::type_object(count = ellmer::type_integer())
  expect_identical(
    agent$chat_structured("extract", type = type, max_corrections = 1),
    list(count = 1L)
  )
  expect_length(runtime_events(agent, "structured_attempt"), 2L)
  server2 <- local_runtime_server(list(runtime_failure(401L)))
  agent2 <- Agent$new(runtime_chat(server2))
  expect_error(
    agent2$chat_structured("extract", type = type, max_corrections = 5),
    class = "httr2_http_401"
  )
  expect_length(server2$requests(), 1L)
})

test_that("structured streams reuse ellmer native support", {
  server <- local_runtime_server(list(runtime_reply('{"count":1}')))
  agent <- Agent$new(runtime_chat(server))
  chunks <- coro::collect(agent$stream(
    "extract",
    type = ellmer::type_object(count = ellmer::type_integer()),
    stream = "content"
  ))
  expect_true(all(vapply(chunks, inherits, logical(1), "ellmer::Content")))
  expect_s3_class(agent$get_turns()[[2]]@contents[[1]], "ellmer::ContentJson")
  expect_null(server$requests()[[1]]$body$tools)
  expect_identical(agent$last_run()$usage$requests, 1L)
})

test_that("ellmer's schema-tool fallback is governed without invoking ordinary tools", {
  response <- list(
    status = 200L,
    headers = list("Content-Type" = "application/json"),
    body = '{"id":"msg_fixture","type":"message","role":"assistant","model":"claude-3-5-haiku-20241022","content":[{"type":"tool_use","id":"toolu_fixture","name":"_structured_tool_call","input":{"data":{"count":1}}}],"stop_reason":"tool_use","usage":{"input_tokens":10,"output_tokens":5}}'
  )
  server <- local_runtime_server(list(response))
  chat <- ellmer::chat_anthropic(
    base_url = server$url,
    model = "claude-3-5-haiku-20241022",
    credentials = function() "fixture",
    echo = "none"
  )
  effects <- 0L
  tool <- ellmer::tool(
    function() {
      effects <<- effects + 1L
    },
    name = "effect",
    description = "effect"
  )
  agent <- Agent$new(chat, tools = list(tool))
  value <- agent$chat_structured(
    "extract",
    type = ellmer::type_object(count = ellmer::type_integer())
  )
  expect_identical(value, list(count = 1L))
  request <- server$requests()[[1]]$body
  expect_identical(request$tools[[1]]$name, "_structured_tool_call")
  expect_length(request$tools, 1L)
  expect_identical(effects, 0L)
  expect_identical(agent$last_run()$usage$requests, 1L)
})

test_that("truncated structured responses are terminal and budget errors retain results", {
  server <- local_runtime_server(list(runtime_reply(
    '{"count":',
    stream = FALSE,
    finish = "length"
  )))
  agent <- Agent$new(runtime_chat(server))
  type <- ellmer::type_object(count = ellmer::type_integer())
  expect_error(
    agent$chat_structured("extract", type = type, max_corrections = 2),
    "truncated"
  )
  expect_length(server$requests(), 1L)
  expect_identical(agent$last_run()$stop_reason, "error")
  limited <- Agent$new(
    runtime_chat(server),
    usage_limits = UsageLimits(max_requests = 0, on_exceed = "error")
  )
  expect_error(
    limited$chat_structured("extract", type = type),
    class = "deputy_request_limit"
  )
  expect_identical(limited$last_run()$stop_reason, "request_limit")
  expect_identical(limited$last_run()$usage$requests, 0L)
})

test_that("a failed extraction retains its original condition after completed task work", {
  server <- local_runtime_server(list(
    runtime_reply("work complete"),
    runtime_failure(401L)
  ))
  agent <- Agent$new(runtime_chat(server))
  expect_error(
    agent$run_sync(
      "task",
      type = ellmer::type_object(count = ellmer::type_integer()),
      max_corrections = 5
    ),
    class = "httr2_http_401"
  )
  expect_identical(trimws(agent$last_run()$response), "work complete")
  expect_identical(agent$last_run()$stop_reason, "error")
  expect_identical(agent$last_run()$usage$requests, 2L)
  expect_s3_class(
    runtime_events(agent, "request_error")[[1]]$condition,
    "httr2_http_401"
  )
  expect_length(server$requests(), 2L)
})
