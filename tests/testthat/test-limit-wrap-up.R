wrap_up_agent <- function(server, limits, counter = new.env(), ...) {
  counter$effects <- 0L
  tool <- ellmer::tool(
    function() {
      counter$effects <- counter$effects + 1L
      "export-0042"
    },
    name = "export_findings",
    description = "Export the findings"
  )
  Agent$new(
    runtime_chat(server),
    tools = list(tool),
    permissions = permissions_full(),
    usage_limits = limits,
    ...
  )
}

request_text <- function(request) {
  as.character(jsonlite::toJSON(request$body$messages, auto_unbox = TRUE))
}

test_that("a request limit reached mid-run gets one answer request without tools", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    runtime_reply(tool = "export_findings"),
    runtime_reply("I exported once; I could not check the second export.")
  ))
  counter <- new.env()
  agent <- wrap_up_agent(
    server,
    UsageLimits(max_requests = 2, on_exceed = "wrap_up"),
    counter
  )

  result <- agent$run_sync("Export the findings twice")

  expect_identical(result$stop_reason, "request_limit")
  expect_s7_class(result$ending, RunEndingLimit)
  expect_true(result$ending$wrapped_up)
  expect_match(result$response, "could not check the second export")
  # One request beyond max_requests, and no tool ran for the rejected call.
  expect_length(server$requests(), 3L)
  expect_identical(result$usage$requests, 3L)
  expect_identical(counter$effects, 1L)
  requests <- server$requests()
  expect_false(is.null(requests[[2]]$body$tools))
  expect_null(requests[[3]]$body$tools)
  expect_match(request_text(requests[[3]]), "limit was reached", fixed = TRUE)
  expect_match(request_text(requests[[3]]), "could not check", fixed = TRUE)
  # The rejected call's result still travels with the answer request.
  expect_match(request_text(requests[[3]]), "tool_call_id", fixed = TRUE)
  # The agent has its tools back for the next run.
  expect_true("export_findings" %in% names(agent$get_tools()))
  expect_false(agent$.__enclos_env__$private$run_active)
})

test_that("a tool-call limit gets the same answer request", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    runtime_reply(tool = "export_findings"),
    runtime_reply("Partial answer.")
  ))
  counter <- new.env()
  agent <- wrap_up_agent(
    server,
    UsageLimits(max_tool_calls = 1, on_exceed = "wrap_up"),
    counter
  )

  result <- agent$run_sync("Export the findings twice")

  expect_identical(result$stop_reason, "tool_call_limit")
  expect_true(result$ending$wrapped_up)
  expect_identical(trimws(result$response), "Partial answer.")
  expect_identical(counter$effects, 1L)
  expect_null(server$requests()[[3]]$body$tools)
  # The call the limit refused is closed by ellmer, and the older text asking
  # for a final answer belongs to a counter that the same limit always trips
  # second, so it is never what the model sees.
  expect_match(
    request_text(server$requests()[[3]]),
    "Chat ended before the tool could be invoked",
    fixed = TRUE
  )
  expect_no_match(
    request_text(server$requests()[[3]]),
    "Please provide your final answer",
    fixed = TRUE
  )
  limit_events <- Filter(
    function(event) identical(event$type, "limit_wrap_up"),
    result$events
  )
  expect_length(limit_events, 1L)
  expect_identical(limit_events[[1]]$reason, "tool_call_limit")
})

test_that("a token or cost ceiling that is reached aborts without an answer request", {
  for (limits in list(
    UsageLimits(max_total_tokens = 15, on_exceed = "wrap_up"),
    UsageLimits(max_input_tokens = 10, on_exceed = "wrap_up"),
    UsageLimits(max_output_tokens = 5, on_exceed = "wrap_up")
  )) {
    server <- local_runtime_server(list(
      runtime_reply(tool = "export_findings"),
      runtime_reply("never asked for")
    ))
    agent <- wrap_up_agent(server, limits)

    result <- agent$run_sync("Export the findings")

    expect_match(result$stop_reason, "_token_limit$")
    expect_false(result$ending$wrapped_up)
    expect_length(server$requests(), 1L)
  }
})

test_that("an answer request that would pass a token ceiling is not made", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    runtime_reply("never asked for")
  ))
  # One request used 15 of 20 tokens; the conversation alone is larger than
  # the 5 tokens left, so the answer request cannot fit.
  agent <- wrap_up_agent(
    server,
    UsageLimits(max_requests = 1, max_total_tokens = 20, on_exceed = "wrap_up")
  )

  result <- agent$run_sync("Export the findings")

  expect_identical(result$stop_reason, "request_limit")
  expect_false(result$ending$wrapped_up)
  expect_length(server$requests(), 1L)
  expect_true(is.null(result$response) || !nzchar(result$response))
})

test_that("the headroom check does not depend on the configured estimator", {
  for (estimator in c("auto", "provider")) {
    server <- local_runtime_server(list(
      runtime_reply(tool = "export_findings"),
      runtime_reply("never asked for")
    ))
    agent <- wrap_up_agent(
      server,
      UsageLimits(
        max_requests = 1,
        max_total_tokens = 20,
        on_exceed = "wrap_up"
      ),
      context_policy = ContextPolicy(estimator = estimator)
    )

    result <- agent$run_sync("Export the findings")

    expect_identical(result$stop_reason, "request_limit")
    expect_false(result$ending$wrapped_up)
    expect_length(server$requests(), 1L)
  }
})

test_that("a request limit with token room left still gets the answer request", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    runtime_reply("Answer with what I have.")
  ))
  agent <- wrap_up_agent(
    server,
    UsageLimits(
      max_requests = 1,
      max_total_tokens = 1000000,
      on_exceed = "wrap_up"
    )
  )

  result <- agent$run_sync("Export the findings")

  expect_identical(result$stop_reason, "request_limit")
  expect_true(result$ending$wrapped_up)
  expect_length(server$requests(), 2L)
})

test_that("on_exceed = 'error' signals the limit without an answer request", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    runtime_reply("never asked for")
  ))
  agent <- wrap_up_agent(
    server,
    UsageLimits(max_requests = 1, on_exceed = "error")
  )

  expect_error(
    agent$run_sync("Export the findings"),
    class = "deputy_request_limit"
  )
  expect_length(server$requests(), 1L)
})

test_that("a failed answer request leaves the limit as the ending", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    runtime_failure()
  ))
  agent <- wrap_up_agent(
    server,
    UsageLimits(max_requests = 1, on_exceed = "wrap_up")
  )

  result <- agent$run_sync("Export the findings")

  expect_identical(result$stop_reason, "request_limit")
  expect_false(result$ending$wrapped_up)
  expect_true("export_findings" %in% names(agent$get_tools()))
})

test_that("an interrupt does not get an answer request", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    runtime_reply("never asked for")
  ))
  agent <- wrap_up_agent(
    server,
    UsageLimits(max_requests = 5, on_exceed = "wrap_up")
  )
  agent$add_hook(HookMatcher(
    event = "PostToolUse",
    callback = function(context, ...) {
      agent$interrupt("enough")
      NULL
    }
  ))

  result <- agent$run_sync("Export the findings")

  expect_identical(result$stop_reason, "enough")
  expect_length(server$requests(), 1L)
})

test_that("a run that already answered keeps its complete ending at the limit", {
  server <- local_runtime_server(list(runtime_reply("Done.")))
  agent <- wrap_up_agent(
    server,
    UsageLimits(max_requests = 1, on_exceed = "wrap_up")
  )

  result <- agent$run_sync("Say done")

  expect_identical(result$stop_reason, "complete")
  expect_length(server$requests(), 1L)
})

test_that("the default makes no answer request, so a request limit stays hard", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    runtime_reply("never asked for")
  ))
  agent <- wrap_up_agent(server, UsageLimits(max_requests = 1))

  result <- agent$run_sync("Export the findings")

  expect_identical(UsageLimits()$on_exceed, "stop")
  expect_identical(result$stop_reason, "request_limit")
  expect_false(result$ending$wrapped_up)
  expect_length(server$requests(), 1L)
  expect_identical(result$usage$requests, 1L)
})

test_that("on_exceed accepts 'wrap_up' and prints it", {
  limits <- UsageLimits(max_requests = 2, on_exceed = "wrap_up")
  expect_identical(limits$on_exceed, "wrap_up")
  expect_match(
    paste(cli::ansi_strip(capture.output(print(limits))), collapse = "\n"),
    "on_exceed: wrap_up"
  )
})
