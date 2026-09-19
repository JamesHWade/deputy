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


test_that("retained permission modes change only after release", {
  child <- owned_test_agent(permissions = permissions_full())
  alias <- Agent$new(
    child$.__enclos_env__$private$.chat,
    permissions = permissions_full()
  )
  owner <- owned_test_owner(permissions = permissions_full())
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 1))
  original <- child$permissions
  expect_error(
    child$set_permission_mode("readonly"),
    class = "deputy_conversation"
  )
  expect_error(
    alias$set_permission_mode("readonly"),
    class = "deputy_conversation"
  )
  expect_identical(child$permissions, original)
  attempted <- NULL
  owner$add_hook(HookMatcher("SubagentStart", callback = function(...) {
    attempted <<- tryCatch(
      child$set_permission_mode("readonly"),
      error = identity
    )
    owner$set_permission_mode("readonly")
    NULL
  }))
  owner$continue_agent(handle, "narrow caller", UsageLimits(max_requests = 1))
  expect_s3_class(attempted, "deputy_conversation")
  expect_identical(child$permissions, original)
  expect_identical(owner$get_permission_mode(), "readonly")
  owner$release_agent(handle)
  child$set_permission_mode("readonly")
  expect_identical(child$get_permission_mode(), "readonly")
})

test_that("rejected incoming Chats preserve existing disclosure and lead state", {
  lead <- parallel_test_lead(
    new.env(parent = emptyenv()),
    delegation_disclosure = DelegationDisclosure(authorize = function(
      requester,
      scope
    ) {
      identical(requester, "owner")
    })
  )
  lead$parallel_delegate(c(a = "settled evidence"))
  original_view <- lead$inspect_subagents("owner", transcript = TRUE)
  original_defs <- lead$available_sub_agents()
  original_chat <- lead$.__enclos_env__$private$.chat
  original_buffer <- lead$.__enclos_env__$private$.delegation_buffer
  original_disclosure <- lead$.__enclos_env__$private$.delegation_disclosure
  child <- owned_test_agent()
  owner <- owned_test_owner()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 1))
  target <- child$.__enclos_env__$private$.chat
  for (agent in list(lead, owned_test_owner())) {
    before <- agent$.__enclos_env__$private$.delegation_disclosure
    expect_error(
      agent$initialize(
        target,
        delegation_disclosure = DelegationDisclosure(authorize = function(...) {
          TRUE
        })
      ),
      class = "deputy_conversation"
    )
    expect_identical(
      agent$.__enclos_env__$private$.delegation_disclosure,
      before
    )
  }
  expect_identical(lead$.__enclos_env__$private$.chat, original_chat)
  expect_identical(
    lead$.__enclos_env__$private$.delegation_buffer,
    original_buffer
  )
  expect_identical(
    lead$.__enclos_env__$private$.delegation_disclosure,
    original_disclosure
  )
  expect_identical(lead$available_sub_agents(), original_defs)
  expect_identical(
    lead$inspect_subagents("owner", transcript = TRUE),
    original_view
  )
  expect_error(
    lead$inspect_subagents("stranger", transcript = TRUE),
    class = "deputy_error"
  )
  owner$release_agent(handle)
})


test_that("retention rejects foreign native delegation tools", {
  chat <- create_mock_chat()
  child <- Agent$new(chat)
  alias <- LeadAgent$new(
    chat,
    sub_agents = list(agent_definition("leaf", "Leaf", "Leaf"))
  )
  owner <- owned_test_owner()
  before <- child$get_tools()
  expect_error(
    owner$retain_agent(child, UsageLimits(max_requests = 1)),
    "cannot contain delegation tools",
    class = "deputy_conversation"
  )
  expect_identical(child$get_tools(), before)
  expect_null(child$.__enclos_env__$private$.conversation_owner)
  expect_null(attr(chat, "deputy_conversation_owner"))
  expect_equal(nrow(alias$list_subagents()), 0L)
  renamed <- attr(before[["delegate_to_agent"]], "deputy_runtime_source_tool")
  renamed@name <- "foreign_leaf"
  isolated <- Agent$new(create_mock_chat(), tools = list(renamed))
  expect_error(
    owner$retain_agent(isolated, UsageLimits(max_requests = 1)),
    "cannot contain delegation tools"
  )
  alias$set_tools(list())
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 1))
  owner$release_agent(handle)
})


test_that("owners cannot retain an alias of their own Chat", {
  owner <- owned_test_owner()
  chat <- owner$.__enclos_env__$private$.chat
  child <- Agent$new(chat)
  tools <- child$get_tools()
  expect_error(
    owner$retain_agent(child, UsageLimits(max_requests = 1)),
    "must use distinct Chats",
    class = "deputy_conversation"
  )
  expect_null(attr(chat, "deputy_conversation_owner"))
  expect_null(child$.__enclos_env__$private$.conversation_owner)
  expect_length(owner$.__enclos_env__$private$owned_conversations, 0L)
  expect_identical(child$get_tools(), tools)
  expect_identical(owner$run_sync("still usable")$response, "answer")
})
