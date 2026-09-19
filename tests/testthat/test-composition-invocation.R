test_that("direct composition calls cannot consume a provider invocation", {
  parent <- local_runtime_server(list(
    runtime_reply(
      tool = "ask_specialist",
      arguments = list(task = "legitimate")
    ),
    runtime_reply("synthesis")
  ))
  specialist <- local_runtime_server(list(runtime_reply("evidence")))
  owner <- Agent$new(
    runtime_chat(parent),
    permissions = permissions_full(),
    usage_limits = UsageLimits(max_requests = 4),
    delegation_disclosure = DelegationDisclosure(authorize = function(...) TRUE)
  )
  child <- Agent$new(runtime_chat(specialist))
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 1))
  exported <- delegation_tool(
    owner,
    handle,
    "ask_specialist",
    "Ask",
    UsageLimits(max_requests = 1)
  )
  owner$register_tool(exported)
  attempts <- list()
  owner$on_tool_request(function(request) {
    attempts <<- list(
      tryCatch(exported("stolen source call"), error = identity),
      tryCatch(
        owner$get_tools()[["ask_specialist"]]("stolen adapted call"),
        error = identity
      )
    )
  })
  reentry <- NULL
  owner$add_hook(HookMatcher("SubagentStart", callback = function(...) {
    reentry <<- tryCatch(
      owner$get_tools()[["ask_specialist"]]("legitimate"),
      error = identity
    )
    NULL
  }))
  result <- owner$run_sync("compose")
  expect_identical(trimws(result$response), "synthesis")
  expect_length(attempts, 2L)
  expect_true(all(vapply(
    attempts,
    inherits,
    logical(1),
    "deputy_conversation"
  )))
  expect_s3_class(reentry, "deputy_conversation")
  expect_length(specialist$requests(), 1L)
  body <- jsonlite::toJSON(specialist$requests()[[1L]]$body)
  expect_match(body, "legitimate")
  expect_false(grepl("stolen", body, fixed = TRUE))
  expect_identical(result$usage$requests, 3L)
  runs <- owner$inspect_subagents("host", transcript = TRUE)
  expect_length(runs, 1L)
  runtime <- runs[[1L]]$outcome$runtime
  expect_identical(runtime$tool_call_id, "call_fixture")
  expect_identical(runtime$parent_run_id, result$run_id)
  expect_identical(runtime$parent_agent_id, owner$agent_id)
  expect_identical(runtime$status, "completed")
})

test_that("another executing tool cannot impersonate a composition invocation", {
  specialist_reply <- runtime_reply(
    tool = "ask_specialist",
    arguments = list(task = "legitimate")
  )
  specialist_reply$body <- gsub(
    "call_fixture",
    "call_specialist",
    specialist_reply$body,
    fixed = TRUE
  )
  parent <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    specialist_reply,
    runtime_reply("synthesis")
  ))
  specialist <- local_runtime_server(list(runtime_reply("evidence")))
  owner <- Agent$new(runtime_chat(parent), permissions = permissions_full())
  handle <- owner$retain_agent(
    Agent$new(runtime_chat(specialist)),
    UsageLimits(max_requests = 1)
  )
  owner$register_tool(delegation_tool(
    owner,
    handle,
    "ask_specialist",
    "Ask",
    UsageLimits(max_requests = 1)
  ))
  attempted <- NULL
  owner$register_tool(ellmer::tool(
    function() {
      attempted <<- tryCatch(
        owner$get_tools()[["ask_specialist"]]("stolen"),
        error = identity
      )
      "probe complete"
    },
    name = "probe",
    description = "Probe",
    arguments = list()
  ))
  result <- owner$run_sync(
    "compose",
    usage_limits = UsageLimits(max_requests = 5)
  )
  expect_identical(trimws(result$response), "synthesis")
  expect_s3_class(attempted, "deputy_conversation")
  expect_length(specialist$requests(), 1L)
  body <- jsonlite::toJSON(specialist$requests()[[1L]]$body)
  expect_match(body, "legitimate")
  expect_false(grepl("stolen", body, fixed = TRUE))
  expect_equal(nrow(owner$list_subagents()), 1L)
})
