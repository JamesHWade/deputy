test_that("follow-ups retain history and identity with independent run accounting", {
  owner <- owned_test_owner()
  child <- owned_test_agent(system_prompt = "specialist")
  child$run_sync("existing history")
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  first <- owner$continue_agent(handle, "first", UsageLimits(max_requests = 1))
  second <- owner$continue_agent(
    handle,
    "second",
    UsageLimits(max_requests = 1)
  )
  expect_identical(first$agent_id, second$agent_id)
  expect_identical(first$session_id, second$session_id)
  expect_identical(first$run_id == second$run_id, FALSE)
  expect_identical(first$delegation_id == second$delegation_id, FALSE)
  expect_length(child$turns(), 6L)
  expect_identical(child$get_system_prompt(), "specialist")
  views <- owner$inspect_subagents("owner", transcript = TRUE)
  expect_identical(views[[2]]$cumulative_usage$requests, 2L)
  expect_identical(
    views[[2]]$outcome$runtime$previous_delegation_id,
    first$delegation_id
  )
  expect_length(views[[1]]$turns, 4L)
  exhausted <- owner$continue_agent(
    handle,
    "third",
    UsageLimits(max_requests = 100)
  )
  expect_identical(exhausted$stop_reason, "request_limit")
  expect_identical(exhausted$usage$requests, 0L)
  expect_length(child$turns(), 6L)
})

test_that("ownership denies foreign, duplicate, direct and expired access", {
  owner <- owned_test_owner()
  other <- owned_test_owner()
  child <- owned_test_agent()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 5))
  expect_snapshot(
    error = TRUE,
    other$continue_agent(handle, "foreign", UsageLimits())
  )
  expect_snapshot(error = TRUE, other$retain_agent(child, UsageLimits()))
  expect_snapshot(error = TRUE, child$run_sync("direct"))
  expect_snapshot(error = TRUE, owner$clone())
  expect_snapshot(error = TRUE, child$clone())
  expect_snapshot(
    error = TRUE,
    owner$inspect_subagents("stranger", transcript = TRUE)
  )
  owner$continue_agent(handle, "authorized", UsageLimits(max_requests = 1))
  owner$release_agent(handle)
  expect_snapshot(
    error = TRUE,
    owner$continue_agent(handle, "expired", UsageLimits())
  )
  expect_length(owner$inspect_subagents("owner"), 0L)
  expect_identical(child$run_sync("released")$response, "answer")
})

test_that("busy rejection and cooperative cancellation settle exactly once", {
  owner <- owned_test_owner()
  child <- owned_test_agent()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 3))
  pending <- owner$continue_agent_async(
    handle,
    "first",
    UsageLimits(max_requests = 1)
  )
  expect_snapshot(
    error = TRUE,
    owner$continue_agent_async(handle, "overlap", UsageLimits())
  )
  expect_snapshot(error = TRUE, owner$release_agent(handle))
  owner$cancel_agent(handle)
  owner$cancel_agent(handle)
  cancelled <- resolve_async_value(pending)
  expect_s7_class(cancelled, AgentResult)
  expect_identical(cancelled$stop_reason, "interrupted")
  expect_identical(cancelled$usage$requests, 0L)
  expect_identical(cancelled$agent_id, child$agent_id)
  expect_identical(cancelled$session_id, child$session_id())
  expect_identical(
    cancelled$delegation_id,
    owner$list_subagents()$delegation_id
  )
  expect_equal(nrow(owner$list_subagents()), 1L)
  expect_identical(owner$list_subagents()$stop_reason, "interrupted")
  expect_identical(owner$cancel_agent(handle), FALSE)
  expect_identical(
    owner$continue_agent(
      handle,
      "explicit retry",
      UsageLimits(max_requests = 1)
    )$response,
    "answer"
  )
})

test_that("cancellation before child dispatch returns an interrupted result", {
  owner <- owned_test_owner()
  child <- owned_test_agent()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  owner$add_hook(HookMatcher(
    "SubagentStart",
    timeout = 0,
    callback = function(...) {
      owner$cancel_agent(handle)
      NULL
    }
  ))
  result <- owner$continue_agent(
    handle,
    "cancel",
    UsageLimits(max_requests = 1)
  )
  expect_s7_class(result, AgentResult)
  expect_identical(result$stop_reason, "interrupted")
  expect_identical(result$usage$requests, 0L)
  expect_null(result$run_id)
  expect_null(result$response)
  expect_identical(result$agent_id, child$agent_id)
  expect_identical(result$session_id, child$session_id())
  expect_identical(result$delegation_id, owner$list_subagents()$delegation_id)
  expect_identical(owner$list_subagents()$status, "not_started")
  expect_length(child$get_turns(), 0L)
})

test_that("manual compaction cannot bypass a retained Chat lease", {
  server <- local_runtime_server(list(runtime_reply("summary", stream = FALSE)))
  chat <- runtime_compaction_chat(server)
  child <- Agent$new(chat)
  alias <- Agent$new(chat)
  owner <- owned_test_owner()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  before <- child$get_turns()
  for (agent in list(child, alias)) {
    expect_error(agent$compact(keep_last = 0), "current owner")
    expect_error(
      agent$compact(keep_last = 0, automatic = TRUE),
      "current owner"
    )
  }
  expect_length(server$requests(), 0L)
  expect_identical(child$get_turns(), before)
  owner$release_agent(handle)
  result <- child$compact(keep_last = 0, summary = "released summary")
  expect_identical(result$method, "custom")
})

test_that("configuration changes and finite retention reject before execution", {
  owner <- owned_test_owner()
  child <- owned_test_agent()
  handle <- owner$retain_agent(
    child,
    UsageLimits(max_requests = 3),
    max_runs = 1
  )
  owner$continue_agent(handle, "once", UsageLimits(max_requests = 1))
  expect_snapshot(
    error = TRUE,
    owner$continue_agent(handle, "twice", UsageLimits())
  )
  owner$release_agent(handle)
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 3))
  # Raw host access is outside the public facade; still reject changed setup.
  child$.__enclos_env__$private$.chat$set_system_prompt("changed")
  expect_snapshot(
    error = TRUE,
    owner$continue_agent(handle, "changed", UsageLimits())
  )
})

test_that("retained conversation mutation rejects through every public entry", {
  server <- local_runtime_server(list())
  chat <- runtime_chat(server)
  chat$set_turns(list(ellmer::UserTurn("retained evidence")))
  child <- Agent$new(chat, system_prompt = "retained policy")
  alias <- Agent$new(chat)
  path <- withr::local_tempfile(fileext = ".rds")
  child$save_session(path)
  tool <- ellmer::tool(
    function() "read",
    "Read",
    arguments = list(),
    name = "read"
  )
  operations <- list(
    initialize = function(agent) {
      agent$initialize(
        create_mock_chat(),
        permissions = permissions_full(),
        system_prompt = "replacement"
      )
    },
    add_turn = function(agent) agent$add_turn("replacement", "answer"),
    set_turns = function(agent) agent$set_turns(list()),
    set_system_prompt = function(agent) agent$set_system_prompt("replacement"),
    set_model = function(agent) agent$set_model("replacement"),
    set_tools = function(agent) agent$set_tools(list(tool)),
    register_tool = function(agent) agent$register_tool(tool),
    register_tools = function(agent) agent$register_tools(list(tool)),
    load_session = function(agent) agent$load_session(path),
    load_skill = function(agent) agent$load_skill(Skill("replacement")),
    load_mcp = function(agent) agent$load_mcp(config = "nonexistent.json")
  )
  before <- list(
    turns = child$get_turns(),
    prompt = child$get_system_prompt(),
    model = child$get_model(),
    tools = child$get_tools()
  )
  owner <- owned_test_owner()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  for (agent in list(child, alias)) {
    for (operation in operations) {
      expect_error(operation(agent), "current owner")
    }
  }
  expect_identical(child$get_turns(), before$turns)
  expect_identical(child$get_system_prompt(), before$prompt)
  expect_identical(child$get_model(), before$model)
  expect_identical(child$get_tools(), before$tools)
  expect_length(server$requests(), 0L)
  owner$release_agent(handle)
  alias$set_turns(list())
  expect_length(child$get_turns(), 0L)
  child$load_session(path)
  expect_identical(child$get_turns(), before$turns)
  child$set_system_prompt("released policy")
  expect_identical(alias$get_system_prompt(), "released policy")
})

test_that("an active retained run cannot be rewritten through an alias", {
  child <- owned_test_agent()
  alias <- Agent$new(child$.__enclos_env__$private$.chat)
  child$set_turns(list(create_mock_user_turn("retained evidence")))
  attempts <- list()
  child$add_hook(HookMatcher(
    "UserPromptSubmit",
    timeout = 0,
    callback = function(...) {
      attempts <<- lapply(list(child, alias), function(agent) {
        tryCatch(agent$set_turns(list()), error = identity)
      })
      NULL
    }
  ))
  owner <- owned_test_owner()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 1))
  result <- owner$continue_agent(
    handle,
    "continue",
    UsageLimits(max_requests = 1)
  )
  expect_identical(result$response, "answer")
  expect_length(attempts, 2L)
  expect_true(all(vapply(attempts, inherits, logical(1), "deputy_error")))
  expect_length(child$get_turns(), 3L)
  expect_identical(
    child$get_turns()[[1L]]@contents[[1L]]@text,
    "retained evidence"
  )
})

test_that("LeadAgent aliases cannot change or execute a retained conversation", {
  child <- owned_test_agent()
  alias <- LeadAgent$new(
    child$.__enclos_env__$private$.chat,
    sub_agents = list(agent_definition("leaf", "Work", "Work"))
  )
  owner <- owned_test_owner()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  prompt <- child$get_system_prompt()
  definition <- agent_definition("extra", "Work", "Work")
  expect_error(alias$initialize(create_mock_chat()), "current owner")
  expect_error(alias$register_sub_agent(definition), "current owner")
  expect_identical(alias$available_sub_agents(), "leaf")
  expect_identical(child$get_system_prompt(), prompt)
  expect_error(alias$parallel_delegate(c(leaf = "work")), "current owner")
  expect_equal(nrow(alias$list_subagents()), 0L)
  owner$release_agent(handle)
  alias$register_sub_agent(definition)
  expect_identical(alias$available_sub_agents(), c("leaf", "extra"))
})

test_that("current caller policy and specialist policy both govern tools", {
  fixture <- create_content_stream_chat(tool_name = "read_file")
  child <- Agent$new(fixture$chat, tools = list(fixture$tool))
  owner <- owned_test_owner(
    permissions = Permissions(mode = "standard", file_read = FALSE)
  )
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 3))
  owner$continue_agent(handle, "read", UsageLimits(max_requests = 1))
  expect_identical(fixture$state$tool_executed, FALSE)
  expect_identical(fixture$state$tool_rejected, TRUE)
})

test_that("ordinary Agents expose bounded child observation without executing twice", {
  owner <- owned_test_owner()
  child <- owned_test_agent()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  subscription <- owner$observe_subagents("owner")
  first <- subscription$poll()
  expect_length(first$events, 0L)
  owner$continue_agent(handle, "run", UsageLimits(max_requests = 1))
  events <- subscription$poll()
  expect_gt(length(events$events), 0L)
  expect_identical(child$last_run()$usage$requests, 1L)
  subscription$close()
})

test_that("cancelled follow-ups do not charge or expose a preceding run", {
  owner <- owned_test_owner()
  child <- owned_test_agent()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 3))
  first <- owner$continue_agent(handle, "first", UsageLimits(max_requests = 1))
  pending <- owner$continue_agent_async(
    handle,
    "cancel before dispatch",
    UsageLimits(max_requests = 1)
  )
  owner$cancel_agent(handle)
  resolve_async_value(pending)
  view <- owner$inspect_subagents("owner")[[2L]]
  expect_identical(view$usage$requests, 0L)
  expect_identical(view$cumulative_usage$requests, 1L)
  expect_identical(view$outcome$answer, "")
  expect_identical(view$outcome$runtime$run_id == first$run_id, FALSE)
})

test_that("provider failures release leases and need an explicit retry", {
  owner <- owned_test_owner()
  chat <- create_mock_chat()
  attempts <- 0L
  chat$stream_async <- function(...) {
    attempts <<- attempts + 1L
    if (attempts == 1L) {
      abort_deputy("fixture provider failure")
    }
    as_mock_async_stream(ellmer::ContentText("recovered"))
  }
  child <- Agent$new(chat)
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 3))
  expect_snapshot(
    error = TRUE,
    owner$continue_agent(handle, "fail", UsageLimits(max_requests = 1))
  )
  expect_identical(attempts, 1L)
  result <- owner$continue_agent(handle, "retry", UsageLimits(max_requests = 1))
  expect_identical(result$response, "recovered")
  expect_identical(
    owner$inspect_subagents("owner")[[2]]$cumulative_usage$requests,
    2L
  )
})

test_that("delayed streams cannot bypass transferred ownership", {
  owner <- owned_test_owner()
  child <- owned_test_agent()
  delayed <- child$stream_async("created before retention")
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  expect_snapshot(error = TRUE, collect_async_stream(delayed))
  expect_null(child$last_run())
  owner$release_agent(handle)
})

test_that("caller hooks are enforced without replacing specialist hooks", {
  fixture <- create_content_stream_chat()
  child <- Agent$new(fixture$chat, tools = list(fixture$tool))
  owner <- owned_test_owner()
  owner$add_hook(HookMatcher("PreToolUse", callback = function(...) {
    list(decision = "deny", reason = "host denies")
  }))
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 3))
  before <- child$hooks$count()
  owner$continue_agent(handle, "read", UsageLimits(max_requests = 1))
  expect_identical(fixture$state$tool_executed, FALSE)
  expect_identical(child$hooks$count(), before)
})

test_that("a retained mutable Chat cannot be adopted through a second wrapper", {
  owner <- owned_test_owner()
  chat <- create_mock_chat()
  child <- Agent$new(chat)
  alias <- Agent$new(chat)
  delayed_alias <- alias$stream_async("delayed alias")
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  expect_snapshot(
    error = TRUE,
    owned_test_owner()$retain_agent(alias, UsageLimits())
  )
  expect_snapshot(error = TRUE, Agent$new(chat))
  expect_error(alias$clone(), class = "deputy_conversation")
  expect_error(alias$clone(deep = TRUE), class = "deputy_conversation")
  expect_snapshot(error = TRUE, alias$run_sync("alias bypass"))
  expect_snapshot(error = TRUE, collect_async_stream(delayed_alias))
  owner$release_agent(handle)
})

test_that("leased Chat aliases cannot admit or dispatch retained children", {
  owner <- owned_test_owner()
  child <- owned_test_agent()
  alias <- Agent$new(child$.__enclos_env__$private$.chat)
  nested <- owned_test_agent()
  old_handle <- alias$retain_agent(nested, UsageLimits(max_requests = 2))
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  other <- owned_test_agent()

  expect_error(
    alias$retain_agent(other, UsageLimits(max_requests = 1)),
    class = "deputy_conversation"
  )
  expect_null(other$.__enclos_env__$private$.conversation_owner)
  expect_error(
    alias$continue_agent(old_handle, "bypass", UsageLimits(max_requests = 1)),
    class = "deputy_conversation"
  )
  expect_error(
    alias$continue_agent_async(
      old_handle,
      "bypass",
      UsageLimits(max_requests = 1)
    ),
    class = "deputy_conversation"
  )
  expect_equal(nrow(alias$list_subagents()), 0L)
  expect_length(nested$turns(), 0L)

  alias$release_agent(old_handle)
  owner$release_agent(handle)
  restored <- alias$retain_agent(other, UsageLimits(max_requests = 1))
  result <- alias$continue_agent(
    restored,
    "allowed",
    UsageLimits(max_requests = 1)
  )
  expect_identical(result$response, "answer")
  alias$release_agent(restored)
  expect_s3_class(alias$clone(), "Agent")
})

test_that("interrupt reports cancellation of an independent retained child", {
  owner <- owned_test_owner()
  child <- owned_test_agent()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 1))
  interrupted <- NULL
  owner$add_hook(HookMatcher("SubagentStart", callback = function(...) {
    interrupted <<- owner$interrupt("host_cancelled")
    NULL
  }))
  expect_identical(owner$interrupt(), FALSE)
  result <- owner$continue_agent(
    handle,
    "cancel",
    UsageLimits(max_requests = 1)
  )
  expect_identical(interrupted, TRUE)
  expect_identical(result$stop_reason, "host_cancelled")
  expect_identical(result$usage$requests, 0L)
  expect_length(child$turns(), 0L)
  expect_identical(owner$list_subagents()$stop_reason, "host_cancelled")
  expect_identical(owner$interrupt(), FALSE)
  owner$release_agent(handle)
})

test_that("outstanding alias continuations prevent shared Chat adoption", {
  owner <- owned_test_owner()
  child <- owned_test_agent()
  alias <- Agent$new(child$.__enclos_env__$private$.chat)
  nested <- owned_test_agent()
  old_handle <- alias$retain_agent(nested, UsageLimits(max_requests = 2))
  during_dispatch <- NULL
  alias$add_hook(HookMatcher("SubagentStart", callback = function(...) {
    during_dispatch <<- tryCatch(
      owner$retain_agent(child, UsageLimits(max_requests = 1)),
      error = identity
    )
    NULL
  }))
  pending <- alias$continue_agent_async(
    old_handle,
    "queued work",
    UsageLimits(max_requests = 1)
  )
  expect_error(
    owner$retain_agent(child, UsageLimits(max_requests = 1)),
    class = "deputy_conversation"
  )
  result <- resolve_async_value(pending)
  expect_identical(result$response, "answer")
  expect_s3_class(during_dispatch, "deputy_conversation")
  expect_null(attr(
    alias$.__enclos_env__$private$.chat,
    "deputy_active_conversations"
  ))
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 1))
  expect_error(
    alias$continue_agent(old_handle, "bypass", UsageLimits(max_requests = 1)),
    class = "deputy_conversation"
  )
  alias$release_agent(old_handle)
  owner$release_agent(handle)
})

test_that("sibling histories stay separate and current policy can narrow", {
  owner <- owned_test_owner()
  a <- owned_test_agent("alpha")
  b <- owned_test_agent("beta")
  ha <- owner$retain_agent(a, UsageLimits(max_requests = 2))
  hb <- owner$retain_agent(b, UsageLimits(max_requests = 2))
  owner$continue_agent(ha, "only alpha", UsageLimits(max_requests = 1))
  owner$continue_agent(hb, "only beta", UsageLimits(max_requests = 1))
  expect_identical(a$turns()[[1]]@contents[[1]]@text, "only alpha")
  expect_identical(b$turns()[[1]]@contents[[1]]@text, "only beta")
  fixture <- create_content_stream_chat(tool_name = "write_file")
  child <- Agent$new(fixture$chat, tools = list(fixture$tool))
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  owner$set_permission_mode("readonly")
  owner$continue_agent(handle, "write", UsageLimits(max_requests = 1))
  expect_identical(fixture$state$tool_executed, FALSE)
})


test_that("collection of an idle owner releases borrowed conversations", {
  child <- owned_test_agent()
  local({
    owner <- owned_test_owner()
    owner$retain_agent(child, UsageLimits(max_requests = 1))
  })
  gc()
  child$add_hook(HookMatcher("PreToolUse", callback = function(...) NULL))
  expect_identical(child$hooks$count(), 1L)
  expect_identical(child$run_sync("owner collected")$response, "answer")
  owner <- owned_test_owner()
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 1))
  owner$release_agent(handle)
})

test_that("mid-stream failures and cancellation retain partial history for retry", {
  for (mode in c("fail", "cancel")) {
    owner <- owned_test_owner()
    chat <- create_mock_chat()
    attempts <- 0L
    chat$stream_async <- function(prompt, ...) {
      coro::async_generator(function() {
        attempts <<- attempts + 1L
        chat$set_turns(c(chat$get_turns(), list(create_mock_user_turn(prompt))))
        if (attempts == 1L) {
          chat$set_turns(c(
            chat$get_turns(),
            list(create_mock_assistant_turn("partial"))
          ))
          coro::yield(ellmer::ContentText("partial"))
          if (mode == "fail") {
            abort_deputy("failure after partial output")
          }
          owner$cancel_agent(handle)
        } else {
          coro::yield(ellmer::ContentText("recovered"))
        }
      })()
    }
    child <- Agent$new(chat)
    handle <- owner$retain_agent(child, UsageLimits(max_requests = 3))
    result <- tryCatch(
      owner$continue_agent(handle, "first", UsageLimits(max_requests = 1)),
      deputy_error = identity
    )
    view <- owner$inspect_subagents("owner", transcript = TRUE)[[1L]]
    expect_identical(view$outcome$answer, "partial")
    expect_length(view$turns, 2L)
    expect_identical(view$turns[[2L]]@contents[[1L]]@text, "partial")
    result <- owner$continue_agent(
      handle,
      "recover",
      UsageLimits(max_requests = 1)
    )
    expect_identical(result$response, "recovered")
    expect_length(child$turns(), 3L)
  }
})


test_that("cloned owners release idle specialists when collected", {
  child <- owned_test_agent()
  local({
    owner <- owned_test_owner()$clone()
    owner$retain_agent(child, UsageLimits(max_requests = 1))
  })
  gc()
  child$add_hook(HookMatcher("PreToolUse", callback = function(...) NULL))
  expect_identical(child$hooks$count(), 1L)
  expect_identical(child$run_sync("cloned owner collected")$response, "answer")
})


test_that("optional outcome identities remain named null fields", {
  owner <- owned_test_owner()
  handle <- owner$retain_agent(
    owned_test_agent(),
    UsageLimits(max_requests = 1)
  )
  owner$continue_agent(handle, "first", UsageLimits(max_requests = 1))
  runtime <- owner$inspect_subagents("owner")[[1L]]$outcome$runtime
  expect_identical(anyNA(names(runtime)), FALSE)
  expect_identical(any(names(runtime) == ""), FALSE)
  expect_null(runtime$previous_delegation_id)
})


test_that("delayed owner streams cannot start over independently active children", {
  owner <- owned_test_owner()
  delayed <- owner$stream_async("created while idle")
  handle <- owner$retain_agent(
    owned_test_agent(),
    UsageLimits(max_requests = 2)
  )
  rejected <- NULL
  owner$add_hook(HookMatcher("SubagentStart", callback = function(...) {
    rejected <<- tryCatch(collect_async_stream(delayed), error = identity)
    NULL
  }))
  result <- owner$continue_agent(
    handle,
    "independent child",
    UsageLimits(max_requests = 1)
  )
  expect_s3_class(rejected, "deputy_conversation")
  expect_match(conditionMessage(rejected), "Wait for active child")
  expect_identical(result$response, "answer")
  expect_null(owner$last_run())
  expect_identical(owner$run_sync("after child settled")$response, "answer")
})


test_that("retention rebinds shared tool callbacks and adapters to the child", {
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
  owner_hooks <- 0L
  active_registration <- NULL
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
  alias <- Agent$new(chat)
  alias$on_tool_request(function(request) {
    alias_requests <<- alias_requests + 1L
  })
  owner <- owned_test_owner(permissions = Permissions(file_write = TRUE))
  owner$add_hook(HookMatcher("PreToolUse", callback = function(...) {
    owner_hooks <<- owner_hooks + 1L
    active_registration <<- tryCatch(
      alias$on_tool_result(function(result) {
        alias_requests <<- alias_requests + 1L
      }),
      error = identity
    )
    NULL
  }))
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 4))
  for (observer in list(child, alias)) {
    denied_request <- tryCatch(
      observer$on_tool_request(function(request) {
        alias_requests <<- alias_requests + 1L
      }),
      error = identity
    )
    denied_result <- tryCatch(
      observer$on_tool_result(function(result) {
        alias_requests <<- alias_requests + 1L
      }),
      error = identity
    )
    expect_s3_class(denied_request, "deputy_conversation")
    expect_s3_class(denied_result, "deputy_conversation")
  }
  first <- owner$continue_agent(handle, "write", UsageLimits(max_requests = 2))
  expect_identical(trimws(first$response), "settled")
  expect_identical(effects, 1L)
  expect_identical(child_requests, 1L)
  expect_identical(alias_requests, 0L)
  expect_identical(owner_hooks, 1L)
  expect_s3_class(active_registration, "deputy_conversation")
  expect_identical(first$usage$requests, 2L)
  expect_identical(first$usage$tool_calls, 1L)

  owner$set_permission_mode("readonly")
  second <- suppressWarnings(owner$continue_agent(
    handle,
    "write again",
    UsageLimits(max_requests = 2)
  ))
  expect_identical(trimws(second$response), "settled")
  expect_identical(effects, 1L)
  expect_identical(alias_requests, 0L)
  expect_identical(second$usage$requests, 2L)
  expect_identical(
    owner$inspect_subagents("owner")[[2L]]$cumulative_usage$requests,
    4L
  )
  expect_match(
    jsonlite::toJSON(server$requests()[[4L]]$body),
    "denied|not allowed|read.only",
    ignore.case = TRUE
  )

  owner$release_agent(handle)
  released_results <- 0L
  child$on_tool_result(function(result) {
    released_results <<- released_results + 1L
  })
  released <- child$run_sync("released")
  expect_identical(released_results, 1L)
  expect_identical(trimws(released$response), "settled")
  expect_identical(effects, 2L)
  expect_identical(alias_requests, 0L)
  expect_identical(owner_hooks, 1L)
})


test_that("retained hook registries cannot widen policy before dispatch", {
  server <- local_runtime_server(rep(
    list(
      runtime_reply(tool = "write_file"),
      runtime_reply("settled")
    ),
    2L
  ))
  effects <- 0L
  child <- Agent$new(
    runtime_chat(server),
    permissions = Permissions(file_write = FALSE),
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
  original_hooks <- child$hooks
  allow <- HookMatcher("PermissionRequest", callback = function(...) {
    PermissionResultAllow()
  })
  owner <- owned_test_owner(permissions = permissions_full())
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  expect_error(original_hooks$add(allow), class = "deputy_conversation")
  pending <- owner$continue_agent_async(
    handle,
    "write",
    UsageLimits(max_requests = 2)
  )
  expect_error(
    child$initialize(create_mock_chat(), permissions = permissions_full()),
    class = "deputy_conversation"
  )
  runtime_hooks <- child$hooks
  count <- runtime_hooks$count()
  expect_error(child$add_hook(allow), class = "deputy_conversation")
  expect_error(runtime_hooks$add(allow), class = "deputy_conversation")
  expect_error(original_hooks$initialize(), class = "deputy_conversation")
  expect_error(runtime_hooks$initialize(), class = "deputy_conversation")
  expect_identical(runtime_hooks$count(), count)
  result <- suppressWarnings(resolve_async_value(pending))
  expect_identical(trimws(result$response), "settled")
  expect_identical(effects, 0L)
  expect_identical(child$hooks, original_hooks)
  expect_error(original_hooks$add(allow), class = "deputy_conversation")
  owner$release_agent(handle)
  original_hooks$add(allow)
  expect_identical(child$hooks$count(), 1L)
  released <- child$run_sync("released")
  expect_identical(trimws(released$response), "settled")
  expect_identical(effects, 1L)
})
