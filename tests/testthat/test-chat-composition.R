test_that("two curated providers compose through one ordinary Agent", {
  parent_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_analyst", arguments = list(task = "analyze")),
    runtime_reply(tool = "ask_editor", arguments = list(task = "edit")),
    runtime_reply("synthesis")
  ))
  analyst_server <- local_runtime_server(list(
    runtime_reply("analysis"),
    runtime_reply("follow-up")
  ))
  editor_server <- local_runtime_server(list(runtime_reply("edited")))
  owner <- Agent$new(
    runtime_chat(parent_server),
    usage_limits = UsageLimits(max_requests = 8),
    delegation_disclosure = DelegationDisclosure(authorize = function(
      requester,
      scope
    ) {
      identical(requester, "host")
    })
  )
  analyst <- runtime_chat(analyst_server, model = "analyst-model")
  editor <- ellmer::chat_openai_compatible(
    base_url = editor_server$url,
    credentials = "fixture",
    model = "editor-model",
    system_prompt = "Editor prompt",
    echo = "none"
  )
  analyst$set_system_prompt("Analyst prompt")
  analyst$set_turns(list(
    ellmer::UserTurn("retained evidence"),
    ellmer::AssistantTurn("acknowledged")
  ))
  callbacks <- 0L
  analyst$on_request_start(function(turns) callbacks <<- callbacks + 1L)
  analyst$register_tool(ellmer::tool(
    function() "analyst data",
    name = "analyst_read",
    description = "Read analyst data",
    arguments = list()
  ))
  editor$register_tool(ellmer::tool(
    function() "editor data",
    name = "editor_read",
    description = "Read editor data",
    arguments = list()
  ))
  h1 <- adopt_chat(
    analyst,
    owner,
    permissions_standard(),
    UsageLimits(max_requests = 3),
    history = "retain",
    callbacks = "replace",
    name = "analyst"
  )
  h2 <- adopt_chat(
    editor,
    owner,
    permissions_standard(),
    UsageLimits(max_requests = 3),
    history = "fresh",
    callbacks = "replace",
    name = "editor"
  )
  owner$register_tools(list(
    delegation_tool(
      owner,
      h1,
      "ask_analyst",
      "Analyze",
      UsageLimits(max_requests = 1)
    ),
    delegation_tool(
      owner,
      h2,
      "ask_editor",
      "Edit",
      UsageLimits(max_requests = 1)
    )
  ))
  sub <- owner$observe_subagents("host")
  result <- owner$run_sync("compose")
  expect_identical(result$response, "synthesis")
  expect_identical(result$usage$requests, 5L)
  expect_identical(callbacks, 0L)
  expect_length(analyst$get_turns(), 2L)
  requests <- analyst_server$requests()
  expect_identical(requests[[1]]$body$model, "analyst-model")
  expect_match(jsonlite::toJSON(requests[[1]]$body), "Analyst prompt")
  expect_match(jsonlite::toJSON(requests[[1]]$body), "retained evidence")
  expect_identical(
    requests[[1]]$body$tools[[1]]$`function`$name,
    "analyst_read"
  )
  other <- editor_server$requests()[[1]]$body
  expect_identical(other$model, "editor-model")
  expect_identical(other$tools[[1]]$`function`$name, "editor_read")
  expect_identical(grepl("retained evidence", jsonlite::toJSON(other)), FALSE)
  views <- owner$inspect_subagents("host", transcript = TRUE)
  expect_length(views, 2L)
  expect_identical(views[[1]]$outcome$runtime$parent_run_id, result$run_id)
  expect_identical(views[[1]]$outcome$runtime$tool_call_id, "call_fixture")
  expect_gt(length(sub$poll()$events), 0L)
  owner$continue_agent(h1, "explicit follow-up", UsageLimits(max_requests = 1))
  expect_match(
    jsonlite::toJSON(analyst_server$requests()[[2]]$body),
    "analysis"
  )
  expect_length(owner$inspect_subagents("host"), 3L)
  sub$close()
})

test_that("composition tool cannot transfer authority or run outside its caller", {
  owner <- owned_test_owner()
  handle <- owner$retain_agent(
    owned_test_agent(),
    UsageLimits(max_requests = 2)
  )
  tool <- delegation_tool(
    owner,
    handle,
    "specialist",
    "Ask specialist",
    UsageLimits(max_requests = 1)
  )
  expect_snapshot(error = TRUE, tool("direct call"))
  expect_snapshot(error = TRUE, owned_test_owner()$register_tool(tool))
  owner$register_tool(tool)
  expect_named(tool@arguments@properties, "task")
})

test_that("adoption preserves source callbacks and fresh history is explicit", {
  server <- local_runtime_server(list(runtime_reply("source response")))
  chat <- runtime_chat(server)
  called <- 0L
  chat$on_request_start(function(turns) called <<- called + 1L)
  owner <- owned_test_owner()
  expect_snapshot(
    error = TRUE,
    adopt_chat(
      chat,
      owner,
      permissions_standard(),
      UsageLimits(),
      history = "fresh",
      callbacks = "preserve"
    )
  )
  handle <- adopt_chat(
    chat,
    owner,
    permissions_standard(),
    UsageLimits(max_requests = 1),
    history = "fresh",
    callbacks = "replace"
  )
  chat$chat("source still independent")
  expect_identical(called, 1L)
  owner$release_agent(handle)
})
