test_that("stateless responders overlap with isolated conversations and ordered results", {
  state <- new.env(parent = emptyenv())
  state$hold_a_until_b <- TRUE
  lead <- parallel_test_lead(state, tools = list(tool_read_file))
  lead$set_turns(list(create_mock_user_turn("private parent history")))
  before <- lead$turns()
  hooks <- list()
  for (event in c("SubagentStart", "SubagentStop")) {
    lead$add_hook(HookMatcher$new(
      event = event,
      timeout = 0,
      callback = function(agent_name, context, ...) {
        hooks[[length(hooks) + 1L]] <<- context
        NULL
      }
    ))
  }
  batch <- resolve_async_value(lead$parallel_delegate_async(
    c(a = "first", b = "second", c = "third")
  ))
  expect_identical(state$peak, 2L)
  expect_identical(state$completed, c("b", "a", "c"))
  expect_identical(batch$mode, "stateless")
  expect_identical(
    batch$status,
    c(a = "completed", b = "completed", c = "completed")
  )
  expect_identical(
    vapply(batch$results, function(result) result$response, character(1)),
    c(a = "a first", b = "b second", c = "c third")
  )
  expect_identical(lead$turns(), before)
  for (input in state$inputs) {
    expect_length(input$turns, 0L)
    expect_length(input$tools, 0L)
  }
  expect_equal(
    batch$run$usage,
    AgentUsage(
      requests = 3L,
      input_tokens = 30,
      output_tokens = 15,
      cost_usd = 0.003
    )
  )
  expect_identical(lead$last_run(), batch$run)
  expect_identical(batch$run$stop_reason, "complete")
  runs <- lead$list_subagents()
  expect_equal(nrow(runs), 3L)
  expect_identical(unique(runs$parent_run_id), batch$run$run_id)
  expect_length(unique(runs$agent_id), 3L)
  expect_length(unique(runs$session_id), 3L)
  expect_length(hooks, 6L)
  expect_identical(
    unique(vapply(hooks, `[[`, character(1), "run_id")),
    batch$run$run_id
  )
  for (context in hooks) {
    expect_identical(context$parent_agent_id, lead$agent_id)
    expect_identical(context$parent_run_id, batch$run$run_id)
    child <- runs[runs$delegation_id == context$delegation_id, ]
    expect_identical(context$child_agent_id, child$agent_id)
    expect_identical(context$parent_run_id, child$parent_run_id)
  }
  expect_length(lead$.__enclos_env__$private$delegation_usage_reservations, 0L)
})

test_that("fan-out rejects nonstateless definitions and invalid batches before dispatch", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  lead$register_sub_agent(agent_definition(
    "tool",
    "Tool",
    "Tool",
    tools = list(tool_read_file)
  ))
  lead$register_sub_agent(agent_definition(
    "mcp",
    "MCP",
    "MCP",
    mcp_servers = "service"
  ))
  lead$register_sub_agent(agent_definition(
    "skill",
    "Skill",
    "Skill",
    skills = list("skill")
  ))
  for (name in c("tool", "mcp", "skill")) {
    expect_error(
      lead$parallel_delegate(stats::setNames("task", name)),
      "not stateless"
    )
  }
  expect_error(lead$parallel_delegate(c(a = "one", A = "two")), "at most once")
  expect_error(
    lead$parallel_delegate(c(missing = "task")),
    "Unknown AgentDefinitions"
  )
  expect_error(lead$parallel_delegate("task"), "named character vector")
  expect_error(
    lead$parallel_delegate(c(a = "task"), max_active = 0),
    "positive whole number"
  )
  expect_error(
    lead$parallel_delegate(c(a = "task"), mode = "agentic"),
    "stateless"
  )
  expect_length(state$started, 0L)
})

test_that("failed responders retain successful siblings and count dispatch attempts", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  state$fail <- "b"
  batch <- lead$parallel_delegate(c(a = "first", b = "second", c = "third"))
  expect_identical(
    batch$status,
    c(a = "completed", b = "failed", c = "completed")
  )
  expect_match(
    conditionMessage(batch$errors$b),
    "deterministic responder failure"
  )
  expect_null(batch$results$b)
  expect_identical(batch$run$usage$requests, 3L)
  expect_identical(batch$run$usage$cost_usd, NA_real_)
  expect_identical(batch$run$stop_reason, "delegation_error")
  runs <- lead$list_subagents()
  expect_identical(
    runs$status[match(c("a", "b", "c"), runs$agent_name)],
    c("completed", "failed", "completed")
  )
  expect_length(lead$.__enclos_env__$private$delegation_usage_reservations, 0L)
  state$fail <- character()
  next_batch <- lead$parallel_delegate(c(a = "again"))
  expect_identical(next_batch$status, c(a = "completed"))
  expect_identical(next_batch$run$usage$requests, 1L)
})

test_that("zero budgets and preparation failures leave the lead reusable", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  batch <- lead$parallel_delegate(
    c(a = "task"),
    usage_limits = UsageLimits(max_requests = 0)
  )
  expect_identical(batch$status, c(a = "not_started"))
  expect_identical(batch$run$usage$requests, 0L)
  expect_error(
    lead$parallel_delegate(
      c(a = "task"),
      usage_limits = UsageLimits(max_requests = 0, on_exceed = "error")
    ),
    class = "deputy_request_limit"
  )
  expect_length(state$started, 0L)
  private <- lead$.__enclos_env__$private
  clone <- private$.chat$clone
  private$.chat$clone <- function(deep = FALSE) {
    cli::cli_abort("fixture clone failure")
  }
  expect_error(lead$parallel_delegate(c(a = "task")), "fixture clone failure")
  expect_false(private$run_active)
  expect_identical(lead$last_run()$stop_reason, "error")
  private$.chat$clone <- clone
  expect_identical(
    lead$parallel_delegate(c(a = "again"))$status,
    c(a = "completed")
  )
})

test_that("batch request limits reserve slots before concurrent dispatch", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(
    state,
    usage_limits = UsageLimits(max_requests = 2)
  )
  batch <- lead$parallel_delegate(
    c(a = "first", b = "second", c = "third"),
    max_active = 3
  )
  expect_identical(state$started, c("a", "b"))
  expect_identical(batch$status[["c"]], "not_started")
  expect_null(batch$results$c)
  expect_identical(batch$run$usage$requests, 2L)
  expect_identical(batch$run$stop_reason, "request_limit")
  exact <- lead$parallel_delegate(c(a = "first", b = "second"))
  expect_identical(exact$run$stop_reason, "complete")
})

test_that("unavailable costs and observed token overages stop queued responders", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  state$fail <- "b"
  batch <- lead$parallel_delegate(
    c(a = "first", b = "second", c = "third"),
    max_active = 1,
    usage_limits = UsageLimits(max_cost_usd = 0.5)
  )
  expect_identical(batch$run$stop_reason, "cost_unavailable")
  expect_identical(batch$status[["c"]], "not_started")
  expect_identical(batch$run$usage$requests, 2L)
  state$started <- character()
  state$fail <- character()
  batch <- lead$parallel_delegate(
    c(a = "first", b = "second", c = "third"),
    usage_limits = UsageLimits(max_total_tokens = 10)
  )
  expect_identical(batch$run$stop_reason, "total_token_limit")
  expect_identical(batch$status[["c"]], "not_started")
  expect_equal(batch$run$usage$total_tokens, 30)
  expect_length(state$started, 2L)
})

test_that("interrupting a batch drains active responders and releases the lead", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  promise <- lead$parallel_delegate_async(c(
    a = "first",
    b = "second",
    c = "third"
  ))
  expect_error(
    resolve_async_value(lead$run_async("overlap")),
    class = "deputy_run_active"
  )
  expect_true(lead$interrupt("cancelled_by_host"))
  batch <- resolve_async_value(promise)
  expect_identical(batch$run$stop_reason, "cancelled_by_host")
  expect_identical(batch$status[["c"]], "not_started")
  expect_identical(state$active, 0L)
  expect_false(lead$.__enclos_env__$private$run_active)
  expect_length(lead$.__enclos_env__$private$delegation_usage_reservations, 0L)
  again <- lead$parallel_delegate(c(a = "again"))
  expect_identical(again$status, c(a = "completed"))
})

test_that("no-argument custom clones work when their callbacks are isolated", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  chat <- lead$.__enclos_env__$private$.chat
  clone <- chat$clone
  chat$clone <- function() clone()
  lead$.__enclos_env__$private$.chat <- chat
  batch <- lead$parallel_delegate(c(a = "first", b = "second"))
  expect_identical(batch$status, c(a = "completed", b = "completed"))

  manager <- new.env(parent = emptyenv())
  cleared <- FALSE
  manager$clear <- function() cleared <<- TRUE
  chat$.__enclos_env__ <- list(
    private = list(callback_on_tool_request = manager)
  )
  chat$clone <- function() {
    child <- clone()
    child$.__enclos_env__ <- chat$.__enclos_env__
    child
  }
  lead$.__enclos_env__$private$.chat <- chat
  expect_error(
    lead$parallel_delegate(c(a = "again")),
    "must isolate tool callback managers"
  )
  expect_false(cleared)
  expect_length(state$started, 2L)
})

test_that("cancellation from SubagentStart balances hooks without dispatching", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  stopped <- list()
  lead$add_hook(HookMatcher$new(
    event = "SubagentStart",
    timeout = 0,
    callback = function(...) {
      lead$interrupt("cancelled_before_dispatch")
      NULL
    }
  ))
  lead$add_hook(HookMatcher$new(
    event = "SubagentStop",
    timeout = 0,
    callback = function(agent_name, context, ...) {
      stopped[[agent_name]] <<- context$status
      NULL
    }
  ))
  batch <- lead$parallel_delegate(c(a = "first", b = "second"))
  expect_identical(batch$status, c(a = "not_started", b = "not_started"))
  expect_identical(stopped, list(a = "not_started"))
  expect_length(state$started, 0L)
  expect_identical(batch$run$usage$requests, 0L)
  expect_identical(batch$run$stop_reason, "cancelled_before_dispatch")
  expect_identical(lead$list_subagents()$status, "not_started")
  expect_length(lead$.__enclos_env__$private$delegation_usage_reservations, 0L)
})

test_that("released ellmer Chats preserve transport and isolate runtime callbacks", {
  server <- local_parallel_server()
  chat <- ellmer::chat_openai_compatible(
    base_url = server$url,
    model = "gpt-4o-mini",
    credentials = function() "fixture",
    echo = "none"
  )
  lead <- LeadAgent$new(
    chat,
    tools = list(tool_read_file),
    sub_agents = list(
      agent_definition("a", "A", "A"),
      agent_definition("b", "B", "B")
    )
  )
  history <- list(
    ellmer::UserTurn(list(ellmer::ContentText("private history"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("private answer")))
  )
  lead$set_turns(history)
  parent_manager <- chat$.__enclos_env__$private$callback_on_tool_request
  child <- lead$.__enclos_env__$private$create_sub_agent(lead$sub_agent_defs[[
    1L
  ]])
  child_manager <- child$.__enclos_env__$private$.chat$.__enclos_env__$private$callback_on_tool_request
  expect_false(identical(parent_manager, child_manager))
  expect_identical(child_manager$count(), parent_manager$count())
  batch <- lead$parallel_delegate(c(a = "first", b = "second"))
  expect_identical(batch$status, c(a = "completed", b = "completed"))
  expect_identical(trimws(batch$results$a$response), "fixture reply")
  expect_identical(batch$run$usage$requests, 2L)
  expect_equal(batch$run$usage$total_tokens, 30)
  expect_equal(lead$turns(), history)
  requests <- server$requests()
  expect_length(requests, 2L)
  for (request in requests) {
    expect_identical(request$model, "gpt-4o-mini")
    expect_null(request$tools)
    expect_length(request$messages, 2L)
    expect_true(request$messages[[1L]]$content %in% c("A", "B"))
    content <- request$messages[[2L]]$content
    if (is.list(content)) {
      expect_length(content, 1L)
      content <- content[[1L]]$text
    }
    expect_true(content %in% c("first", "second"))
  }
})
