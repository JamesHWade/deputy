test_that("delegations expose live records and settle in admission order", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  state$hold_a_until_b <- TRUE
  starts <- list()
  stops <- list()
  lead$add_hook(HookMatcher("SubagentStart", callback = function(...) {
    starts[[length(starts) + 1L]] <<- lead$list_subagents()
    NULL
  }))
  lead$add_hook(HookMatcher("SubagentStop", callback = function(context, ...) {
    stops[[context$delegation_id]] <<- lead$list_subagents()
    NULL
  }))

  batch <- lead$parallel_delegate(c(a = "first", b = "second", c = "third"))

  expect_identical(starts[[1]]$agent_name, c("a", "b", "c"))
  expect_identical(starts[[1]]$status, c("running", "queued", "queued"))
  expect_identical(is.na(starts[[1]]$completed_at), rep(TRUE, 3L))
  expect_identical(state$completed, c("b", "a", "c"))
  runs <- lead$list_subagents()
  expect_identical(runs$agent_name, c("a", "b", "c"))
  expect_identical(runs$stop_reason, rep("complete", 3L))
  expect_identical(runs$status, rep("completed", 3L))
  expect_identical(runs$delegation_id, starts[[1]]$delegation_id)
  expect_identical(anyNA(runs$completed_at), FALSE)
  for (id in names(stops)) {
    record <- stops[[id]]
    expect_identical(record$status[record$delegation_id == id], "completed")
  }
  expect_identical(
    vapply(lead$get_subagent_results(), function(x) x$run_id, character(1)),
    runs$run_id
  )
  expect_identical(batch$run$usage$requests, 3L)
})

test_that("ordinary delegation preserves non-complete results and exact reasons", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(
    state,
    usage_limits = UsageLimits(max_total_tokens = 1)
  )
  statuses <- character()
  lead$add_hook(HookMatcher("SubagentStop", callback = function(context, ...) {
    statuses <<- c(statuses, context$status)
    expect_identical(context$stop_reason, "total_token_limit")
    NULL
  }))
  answer <- resolve_async_value(lead$get_tools()$delegate_to_agent("a", "task"))

  expect_identical(jsonlite::fromJSON(answer)$answer, "a task")
  expect_identical(statuses, "stopped")
  expect_identical(lead$list_subagents()$status, "stopped")
  expect_identical(lead$list_subagents()$stop_reason, "total_token_limit")
  result <- lead$get_subagent_results()[[1L]]
  expect_identical(result$response, "a task")
  expect_equal(result$usage$total_tokens, 15)
  expect_length(lead$get_subagent_messages()[[1L]], 2L)
})

test_that("preparation failures retain admitted ordinary and batch records", {
  state <- new.env(parent = emptyenv())
  chat <- create_parallel_chat(state)
  chat$clone <- function(deep = FALSE) {
    cli::cli_abort("fixture preparation failed")
  }
  lead <- LeadAgent$new(
    chat,
    sub_agents = list(
      agent_definition("a", "A", "a"),
      agent_definition("b", "B", "b")
    )
  )
  ordinary <- tryCatch(
    lead$get_tools()$delegate_to_agent("a", "task"),
    error = identity
  )
  expect_s3_class(ordinary, "error")
  runs <- lead$list_subagents()
  expect_identical(runs$status, "failed")
  expect_identical(runs$stop_reason, "setup_error")
  expect_identical(is.na(runs$started_at), TRUE)
  expect_match(runs$error, "fixture preparation failed")
  expect_identical(lead$get_subagent_results(), list(NULL))

  batch <- tryCatch(
    lead$parallel_delegate(c(a = "one", b = "two")),
    error = identity
  )
  expect_s3_class(batch, "error")
  runs <- lead$list_subagents()
  expect_identical(runs$status, c("failed", "failed", "not_started"))
  expect_identical(
    runs$stop_reason,
    c("setup_error", "setup_error", "batch_error")
  )
  expect_length(unique(runs$delegation_id), 3L)
  expect_length(state$started, 0L)
})

test_that("observer errors remain inspectable without duplicate outcomes", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  fail <- TRUE
  for (event in c("SubagentStart", "SubagentStop")) {
    lead$add_hook(HookMatcher(event, callback = function(...) {
      if (fail) {
        cli::cli_abort("fixture observer failure")
      }
      NULL
    }))
  }
  answer <- resolve_async_value(lead$get_tools()$delegate_to_agent("a", "task"))
  expect_identical(jsonlite::fromJSON(answer)$answer, "a task")
  runs <- lead$list_subagents()
  expect_equal(nrow(runs), 1L)
  expect_identical(runs$status, "completed")
  expect_identical(runs$stop_reason, "complete")
  expect_match(runs$hook_error, "SubagentStart: fixture observer failure")
  expect_match(runs$hook_error, "SubagentStop: fixture observer failure")
  fail <- FALSE
  again <- lead$parallel_delegate(c(a = "again", b = "next"))
  expect_identical(again$status, c(a = "completed", b = "completed"))
  expect_identical(again$run$usage$requests, 2L)
})

test_that("budget-stopped batches retain all selected records", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  result <- lead$parallel_delegate(
    c(a = "one", b = "two"),
    usage_limits = UsageLimits(max_requests = 0)
  )
  runs <- lead$list_subagents()
  expect_identical(runs$status, c("not_started", "not_started"))
  expect_identical(runs$stop_reason, rep("request_limit", 2L))
  expect_identical(is.na(runs$started_at), rep(TRUE, 2L))
  expect_identical(anyNA(runs$completed_at), FALSE)
  expect_identical(lead$get_subagent_results(), list(NULL, NULL))
  expect_identical(result$run$usage$requests, 0L)
})

test_that("released ellmer exposes ordinary child identity during a request", {
  reply <- fixture_gate(runtime_reply("child reply"), "child")
  server <- local_runtime_server(list(reply))
  chat <- ellmer::chat_openai_compatible(
    base_url = server$url,
    credentials = function() "fixture",
    model = "gpt-4o-mini",
    echo = "none"
  )
  lead <- LeadAgent$new(
    chat,
    sub_agents = list(agent_definition("a", "A", "a"))
  )
  promise <- lead$get_tools()$delegate_to_agent("a", "child task")
  running <- lead$list_subagents()
  expect_identical(running$status, "running")
  expect_match(running$run_id, "^run_")
  expect_match(running$session_id, "^session_")
  expect_identical(lead$get_subagent_results(), list(NULL))
  # The reply is withheld until the running state has been observed.
  server$release("child")
  expect_identical(
    trimws(
      jsonlite::fromJSON(
        resolve_async_value(promise, max_polls = 6000L)
      )$answer
    ),
    "child reply"
  )
  complete <- lead$list_subagents()
  expect_identical(complete$delegation_id, running$delegation_id)
  expect_identical(complete$run_id, running$run_id)
  expect_identical(complete$status, "completed")
  expect_length(
    lead$get_subagent_messages(session_id = complete$session_id)[[1]],
    2L
  )
  expect_length(server$requests(), 1L)
})

test_that("lead interruption settles its ordinary child and balances hooks", {
  # Streaming: the gate opens itself and `when_gate()` interrupts before the
  # child's stream is consumed (see `fixture_gate()`).
  child_reply <- fixture_gate(
    runtime_reply("child reply"),
    "child",
    open_after = 0.1
  )
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "delegate_to_agent",
      arguments = list(
        agent_name = "a",
        task = "child task"
      )
    ),
    child_reply,
    runtime_reply("lead reply")
  ))
  lead <- LeadAgent$new(
    ellmer::chat_openai_compatible(
      base_url = server$url,
      credentials = function() "fixture",
      model = "gpt-4o-mini",
      echo = "none"
    ),
    sub_agents = list(agent_definition("a", "A", "a")),
    permissions = permissions_full()
  )
  starts <- 0L
  stops <- 0L
  lead$add_hook(HookMatcher("SubagentStart", callback = function(...) {
    starts <<- starts + 1L
    NULL
  }))
  lead$add_hook(HookMatcher("SubagentStop", callback = function(...) {
    stops <<- stops + 1L
    NULL
  }))
  in_flight <- NULL
  cancel_timer <- server$when_gate("child", function() {
    in_flight <<- list(
      requests = length(server$requests()),
      status = lead$list_subagents()$status,
      interrupted = lead$interrupt("cancelled_by_host")
    )
  })
  withr::defer(cancel_timer())
  promise <- lead$run_async("Delegate this task")
  result <- resolve_async_value(promise, max_polls = 6000L)
  expect_identical(in_flight$requests, 2L)
  expect_identical(in_flight$status, "running")
  expect_identical(in_flight$interrupted, TRUE)
  expect_identical(result$stop_reason, "cancelled_by_host")
  record <- lead$list_subagents()
  expect_identical(record$status, "stopped")
  expect_identical(record$stop_reason, "cancelled_by_host")
  expect_identical(starts, 1L)
  expect_identical(stops, 1L)
  expect_identical(anyNA(record$completed_at), FALSE)
  expect_length(server$requests(), 2L)
  expect_equal(result$usage$requests, 2)
})

test_that("start cancellation prevents an ordinary child's first request", {
  server <- local_runtime_server(list(runtime_reply(
    tool = "delegate_to_agent",
    arguments = list(agent_name = "a", task = "task")
  )))
  lead <- LeadAgent$new(
    ellmer::chat_openai_compatible(
      base_url = server$url,
      credentials = function() "fixture",
      model = "gpt-4o-mini",
      echo = "none"
    ),
    sub_agents = list(agent_definition("a", "A", "a")),
    permissions = permissions_full()
  )
  stopped <- list()
  lead$add_hook(HookMatcher("SubagentStart", callback = function(...) {
    lead$interrupt("before_child_request")
    NULL
  }))
  lead$add_hook(HookMatcher("SubagentStop", callback = function(context, ...) {
    stopped[[length(stopped) + 1L]] <<- context
    NULL
  }))
  result <- lead$run_sync("Delegate this task")
  expect_length(server$requests(), 1L)
  expect_identical(result$stop_reason, "before_child_request")
  expect_identical(lead$list_subagents()$status, "not_started")
  expect_identical(lead$list_subagents()$stop_reason, "before_child_request")
  expect_length(stopped, 1L)
  expect_identical(stopped[[1]]$status, "not_started")
})

test_that("thrown child limits retain exact reasons and release reservations", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(
    state,
    usage_limits = UsageLimits(max_total_tokens = 1, on_exceed = "error")
  )
  failure <- tryCatch(
    resolve_async_value(lead$get_tools()$delegate_to_agent("a", "task")),
    error = identity
  )
  expect_s3_class(failure, "error")
  runs <- lead$list_subagents()
  expect_identical(runs$status, "failed")
  expect_identical(runs$stop_reason, "total_token_limit")
  expect_length(lead$get_subagent_messages()[[1L]], 2L)
  private <- lead$.__enclos_env__$private
  expect_length(private$delegation_usage_reservations, 0L)
  expect_length(private$active_subagents, 0L)
  expect_identical(private$current_external_usage$requests, 1L)
})

test_that("batch observer failures settle once and retain successful siblings", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  for (event in c("SubagentStart", "SubagentStop")) {
    lead$add_hook(HookMatcher(event, callback = function(agent_name, ...) {
      if (identical(agent_name, "a")) {
        cli::cli_abort("fixture batch observer failure")
      }
      NULL
    }))
  }
  batch <- lead$parallel_delegate(c(a = "one", b = "two"))
  runs <- lead$list_subagents()
  expect_identical(runs$status, c("completed", "completed"))
  expect_match(runs$hook_error[[1L]], "SubagentStart:")
  expect_match(runs$hook_error[[1L]], "SubagentStop:")
  expect_identical(is.na(runs$hook_error[[2L]]), TRUE)
  expect_identical(batch$run$usage$requests, 2L)
  expect_length(lead$.__enclos_env__$private$delegation_usage_reservations, 0L)
  expect_length(lead$.__enclos_env__$private$active_subagents, 0L)
})

test_that("status polling does not materialize active Subagent transcripts", {
  state <- new.env(parent = emptyenv())
  chat <- create_parallel_chat(state)
  clone <- chat$clone
  reads <- 0L
  chat$clone <- function(deep = FALSE) {
    child <- clone(deep)
    get_turns <- child$get_turns
    child$get_turns <- function(...) {
      reads <<- reads + 1L
      get_turns(...)
    }
    child
  }
  lead <- LeadAgent$new(
    chat,
    sub_agents = list(agent_definition("a", "A", "a"))
  )
  promise <- lead$get_tools()$delegate_to_agent("a", "task")
  baseline <- reads
  lead$list_subagents()
  lead$get_subagent_results()
  expect_identical(reads, baseline)
  lead$get_subagent_messages()
  expect_gt(reads, baseline)
  resolve_async_value(promise)
})

test_that("direct delegation can be interrupted without an active lead run", {
  reply <- fixture_gate(runtime_reply("partial"), "child")
  server <- local_runtime_server(list(reply))
  lead <- LeadAgent$new(
    runtime_chat(server),
    sub_agents = list(agent_definition("a", "A", "a"))
  )
  promise <- lead$get_tools()$delegate_to_agent("a", "task")
  expect_identical(lead$interrupt("host_cancelled"), TRUE)
  # The reply can only arrive after the interrupt.
  server$release("child")
  resolve_async_value(promise, max_polls = 6000L)
  expect_identical(lead$list_subagents()$stop_reason, "host_cancelled")
  expect_identical(lead$list_subagents()$status, "stopped")
  expect_identical(lead$interrupt(), FALSE)
  resolve_async_value(
    lead$get_tools()$delegate_to_agent("a", "next"),
    max_polls = 6000L
  )
  expect_identical(tail(lead$list_subagents()$status, 1L), "completed")
})

test_that("direct start-hook cancellation prevents the first Subagent request", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state)
  lead$add_hook(HookMatcher("SubagentStart", callback = function(...) {
    expect_identical(lead$interrupt("before_request"), TRUE)
    NULL
  }))
  resolve_async_value(lead$get_tools()$delegate_to_agent("a", "task"))
  expect_length(state$started, 0L)
  expect_identical(lead$list_subagents()$status, "not_started")
  expect_identical(lead$list_subagents()$stop_reason, "before_request")
})
