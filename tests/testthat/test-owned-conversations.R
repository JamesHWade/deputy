owned_test_agent <- function(text = "answer", ...) {
  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, ...) {
    coro::async_generator(function() {
      chat$set_turns(c(chat$get_turns(), list(create_mock_user_turn(prompt))))
      coro::yield(ellmer::ContentText(text))
      chat$set_turns(c(
        chat$get_turns(),
        list(create_mock_assistant_turn(text))
      ))
    })()
  }
  Agent$new(chat, ...)
}

owned_test_owner <- function(...) {
  owned_test_agent(
    delegation_disclosure = DelegationDisclosure(
      authorize = function(requester, scope) identical(requester, "owner")
    ),
    ...
  )
}

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
  resolve_async_value(pending)
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
  child$set_system_prompt("changed")
  expect_snapshot(
    error = TRUE,
    owner$continue_agent(handle, "changed", UsageLimits())
  )
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
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 2))
  expect_snapshot(
    error = TRUE,
    owned_test_owner()$retain_agent(alias, UsageLimits())
  )
  expect_snapshot(error = TRUE, Agent$new(chat))
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
