test_that("owners must release retained handles before reinitialization", {
  factories <- list(
    function() owned_test_owner(permissions = permissions_readonly()),
    function() {
      LeadAgent$new(create_mock_chat(), permissions = permissions_readonly())
    }
  )
  for (factory in factories) {
    owner <- factory()
    child <- owned_test_agent()
    handle <- owner$retain_agent(child, UsageLimits(max_requests = 1))
    chat <- owner$.__enclos_env__$private$.chat
    id <- owner$agent_id
    permissions <- owner$permissions
    expect_error(
      owner$initialize(create_mock_chat(), permissions = permissions_full()),
      "Release retained conversations",
      class = "deputy_conversation"
    )
    expect_identical(owner$.__enclos_env__$private$.chat, chat)
    expect_identical(owner$agent_id, id)
    expect_identical(owner$permissions, permissions)
    result <- owner$continue_agent(
      handle,
      "unchanged",
      UsageLimits(max_requests = 1)
    )
    expect_identical(result$response, "answer")
    owner$release_agent(handle)
    replacement <- create_mock_chat()
    owner$initialize(replacement, permissions = permissions_full())
    expect_identical(owner$.__enclos_env__$private$.chat, replacement)
  }
})

test_that("retained children and aliases cannot interrupt owner continuations", {
  factories <- list(
    owned_test_owner,
    function() LeadAgent$new(create_mock_chat())
  )
  for (factory in factories) {
    owner <- factory()
    child <- owned_test_agent()
    alias <- Agent$new(child$.__enclos_env__$private$.chat)
    handle <- owner$retain_agent(child, UsageLimits(max_requests = 1))
    attempts <- list()
    cancelled <- NULL
    owner$add_hook(HookMatcher("SubagentStart", callback = function(...) {
      attempts <<- list(
        tryCatch(child$interrupt("bypass"), error = identity),
        tryCatch(alias$interrupt("alias_bypass"), error = identity)
      )
      cancelled <<- owner$cancel_agent(handle, "owner_cancelled")
      NULL
    }))
    result <- owner$continue_agent(
      handle,
      "cancel",
      UsageLimits(max_requests = 1)
    )
    expect_length(attempts, 2L)
    expect_true(all(vapply(
      attempts,
      inherits,
      logical(1),
      "deputy_conversation"
    )))
    expect_identical(cancelled, TRUE)
    expect_identical(result$stop_reason, "owner_cancelled")
    expect_identical(owner$list_subagents()$stop_reason, "owner_cancelled")
    expect_length(child$turns(), 0L)
    owner$release_agent(handle)
    expect_identical(child$interrupt(), FALSE)
    expect_identical(alias$interrupt(), FALSE)
  }
})


test_that("saved observer removers respect retained ownership", {
  server <- local_runtime_server(rep(
    list(
      runtime_reply(tool = "read_fixture", arguments = list()),
      runtime_reply("settled")
    ),
    2L
  ))
  child <- Agent$new(
    runtime_chat(server),
    permissions = permissions_full(),
    tools = list(ellmer::tool(
      function() "evidence",
      name = "read_fixture",
      description = "Read",
      arguments = list()
    ))
  )
  requests <- 0L
  results <- 0L
  removers <- list(
    child$on_tool_request(function(request) requests <<- requests + 1L),
    child$on_tool_result(function(result) results <<- results + 1L)
  )
  owner <- owned_test_owner(permissions = permissions_full())
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  for (remove in removers) {
    expect_error(remove(), class = "deputy_conversation")
  }
  active_attempts <- list()
  owner$add_hook(HookMatcher("PreToolUse", callback = function(...) {
    active_attempts <<- lapply(removers, function(remove) {
      tryCatch(remove(), error = identity)
    })
    NULL
  }))
  owner$continue_agent(handle, "observe", UsageLimits(max_requests = 2))
  expect_length(active_attempts, 2L)
  expect_true(all(vapply(
    active_attempts,
    inherits,
    logical(1),
    "deputy_conversation"
  )))
  expect_identical(requests, 1L)
  expect_identical(results, 1L)
  owner$release_agent(handle)
  for (remove in removers) {
    remove()
  }
  child$run_sync("removed", usage_limits = UsageLimits(max_requests = 2))
  expect_identical(requests, 1L)
  expect_identical(results, 1L)
})
