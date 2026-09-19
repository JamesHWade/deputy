test_that("released aliases dispatch with their own permissions and observers", {
  for (release in c("explicit", "collection")) {
    server <- local_runtime_server(rep(
      list(
        runtime_reply(tool = "write_file", arguments = list()),
        runtime_reply("settled")
      ),
      3L
    ))
    chat <- runtime_chat(server)
    effects <- 0L
    child_requests <- 0L
    alias_requests <- 0L
    child <- Agent$new(
      chat,
      permissions = Permissions(file_write = TRUE),
      tools = list(ellmer::tool(
        function() {
          effects <<- effects + 1L
          "written"
        },
        name = "write_file",
        description = "Write",
        arguments = list()
      ))
    )
    child$on_tool_request(function(request) {
      child_requests <<- child_requests + 1L
    })
    alias <- Agent$new(chat, permissions = Permissions(file_write = FALSE))
    alias$on_tool_request(function(request) {
      alias_requests <<- alias_requests + 1L
    })
    local({
      owner <- owned_test_owner()
      handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
      if (release == "explicit") owner$release_agent(handle)
    })
    gc()
    denied <- suppressWarnings(alias$run_sync(
      "denied",
      usage_limits = UsageLimits(max_requests = 2)
    ))
    expect_identical(effects, 0L)
    expect_identical(child_requests, 0L)
    expect_identical(alias_requests, 1L)
    expect_identical(denied$usage$requests, 2L)
    expect_identical(denied$usage$tool_calls, 1L)
    allowed <- child$run_sync(
      "allowed",
      usage_limits = UsageLimits(max_requests = 2)
    )
    expect_identical(effects, 1L)
    expect_identical(child_requests, 1L)
    expect_identical(alias_requests, 1L)
    expect_identical(allowed$usage$tool_calls, 1L)
    suppressWarnings(alias$run_sync(
      "denied again",
      usage_limits = UsageLimits(max_requests = 2)
    ))
    expect_identical(effects, 1L)
    expect_identical(child_requests, 1L)
    expect_identical(alias_requests, 2L)
    expect_null(attr(chat, "deputy_active_runtime"))
  }
})

test_that("active released Chats reject competing aliases and adaptation", {
  child <- owned_test_agent()
  chat <- child$.__enclos_env__$private$.chat
  alias <- Agent$new(chat)
  lead <- LeadAgent$new(
    chat,
    sub_agents = list(agent_definition("leaf", "Leaf", "Leaf"))
  )
  lead$set_tools(list())
  owner <- owned_test_owner()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 1))
  owner$release_agent(handle)
  attempts <- list()
  child$add_hook(HookMatcher("SessionStart", callback = function(...) {
    actions <- list(
      function() alias$run_sync("overlap"),
      function() lead$parallel_delegate(c(leaf = "overlap")),
      function() Agent$new(chat),
      function() alias$register_tools(tool_read_file),
      function() alias$initialize(create_mock_chat()),
      function() owner$retain_agent(alias, UsageLimits(max_requests = 1)),
      function() {
        alias$retain_agent(owned_test_agent(), UsageLimits(max_requests = 1))
      }
    )
    attempts <<- lapply(actions, function(action) {
      tryCatch(action(), error = identity)
    })
    NULL
  }))
  result <- child$run_sync("original")
  expect_identical(result$response, "answer")
  expect_length(attempts, 7L)
  expect_true(all(vapply(
    attempts,
    inherits,
    logical(1),
    "deputy_conversation"
  )))
  expect_null(alias$last_run())
  expect_null(lead$last_run())
  expect_null(attr(chat, "deputy_active_runtime"))
  expect_identical(alias$run_sync("after settlement")$response, "answer")
})


test_that("first retention cannot seize another wrapper's active Chat", {
  runner <- owned_test_agent()
  chat <- runner$.__enclos_env__$private$.chat
  alias <- Agent$new(chat)
  owner <- owned_test_owner()
  attempt <- NULL
  runner$add_hook(HookMatcher("SessionStart", callback = function(...) {
    attempt <<- tryCatch(
      owner$retain_agent(alias, UsageLimits(max_requests = 1)),
      error = identity
    )
    NULL
  }))
  expect_identical(runner$run_sync("active")$response, "answer")
  expect_s3_class(attempt, "deputy_conversation")
  expect_null(alias$.__enclos_env__$private$.conversation_owner)
  expect_null(attr(chat, "deputy_active_runtime"))
  handle <- owner$retain_agent(alias, UsageLimits(max_requests = 1))
  owner$release_agent(handle)
})
