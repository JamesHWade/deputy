recursive_route <- function(target, requests = 6L) {
  list(
    target = target,
    description = paste("Ask", target),
    usage_limits = UsageLimits(max_requests = requests)
  )
}

recursive_fixture <- function(
  max_requests = 12L,
  max_depth = 2L,
  max_delegations = 8L,
  max_concurrency = 2L,
  leaf_tool = NULL,
  middle_permissions = permissions_full(),
  graph_limits = NULL,
  leaf_responses = NULL,
  .local_envir = parent.frame()
) {
  root_server <- local_runtime_server(
    list(
      runtime_reply(
        tool = "analyze",
        arguments = list(task = "analyze evidence")
      ),
      runtime_reply("root synthesis")
    ),
    .local_envir = .local_envir
  )
  middle_server <- local_runtime_server(
    list(
      runtime_reply(
        tool = "review",
        arguments = list(task = "review evidence")
      ),
      runtime_reply("analyst synthesis")
    ),
    .local_envir = .local_envir
  )
  leaf_server <- local_runtime_server(
    if (!is.null(leaf_responses)) {
      leaf_responses
    } else if (is.null(leaf_tool)) {
      list(runtime_reply("reviewer evidence"))
    } else {
      list(
        runtime_reply(tool = leaf_tool@name),
        runtime_reply("reviewer evidence")
      )
    },
    .local_envir = .local_envir
  )
  root <- Agent$new(
    runtime_chat(root_server),
    permissions = permissions_full(),
    delegation_disclosure = DelegationDisclosure(authorize = function(
      requester,
      ...
    ) {
      identical(requester, "host")
    })
  )
  middle <- Agent$new(
    runtime_chat(middle_server),
    permissions = middle_permissions,
    agent_name = "analyst"
  )
  leaf <- Agent$new(
    runtime_chat(leaf_server),
    permissions = permissions_full(),
    agent_name = "reviewer"
  )
  if (!is.null(leaf_tool)) {
    leaf$register_tool(leaf_tool)
  }
  list(
    root = root,
    middle = middle,
    leaf = leaf,
    servers = list(root_server, middle_server, leaf_server),
    configure = function() {
      root$retain_agent_graph(
        agents = list(analyst = middle, reviewer = leaf),
        routes = list(
          root = list(analyze = recursive_route("analyst")),
          analyst = list(review = recursive_route("reviewer", 2L))
        ),
        usage_limits = graph_limits %||%
          UsageLimits(max_requests = max_requests),
        max_depth = max_depth,
        max_delegations = max_delegations,
        max_concurrency = max_concurrency
      )
    }
  )
}

test_that("three real levels share root observation and charge each request once", {
  fixture <- recursive_fixture()
  handles <- fixture$configure()
  root <- fixture$root
  reader <- root$observe_subagents("host")
  result <- root$run_sync("compose")
  expect_identical(trimws(result$response), "root synthesis")
  expect_identical(
    vapply(fixture$servers, function(x) length(x$requests()), integer(1)),
    c(2L, 2L, 1L)
  )
  expect_identical(result$usage$requests, 5L)
  expect_identical(root$delegation_graph_usage()$requests, 5L)
  expect_identical(root$delegation_graph_usage()$tool_calls, 2L)
  rows <- root$list_subagents()
  expect_identical(rows$depth, c(1L, 2L))
  expect_identical(rows$parent_delegation_id[[2L]], rows$delegation_id[[1L]])
  expect_identical(
    rows$parent_agent_id,
    c(root$agent_id, fixture$middle$agent_id)
  )
  expect_identical(rows$parent_run_id, c(result$run_id, rows$run_id[[1L]]))
  expect_identical(rows$root_agent_id, rep(root$agent_id, 2L))
  expect_identical(rows$status, rep("completed", 2L))
  views <- root$inspect_subagents("host", transcript = TRUE)
  expect_identical(views[[1L]]$usage$requests, 3L)
  expect_identical(views[[2L]]$usage$requests, 1L)
  events <- reader$poll()$events
  sequence <- vapply(events, function(x) x$sequence, numeric(1))
  expect_identical(anyDuplicated(sequence), 0L)
  expect_identical(sequence, sort(sequence))
  text <- Filter(function(x) identical(x$type, "text"), events)
  expect_setequal(
    unique(vapply(text, function(x) x$delegation_id, character(1))),
    rows$delegation_id
  )
  expect_length(fixture$middle$list_subagents()$delegation_id, 0L)
  expect_length(fixture$leaf$list_subagents()$delegation_id, 0L)
  reader$close()
  root$release_agent_graph()
  expect_length(root$get_tools(), 0L)
  expect_length(fixture$middle$get_tools(), 0L)
  expect_identical(names(handles), c("analyst", "reviewer"))
})

test_that("a graph budget stops descendants without resetting at another run", {
  fixture <- recursive_fixture(max_requests = 3L)
  handles <- fixture$configure()
  result <- fixture$root$run_sync("compose")
  expect_identical(result$stop_reason, "request_limit")
  expect_identical(
    vapply(fixture$servers, function(x) length(x$requests()), integer(1)),
    c(1L, 1L, 1L)
  )
  expect_identical(fixture$root$delegation_graph_usage()$requests, 3L)
  next_result <- fixture$root$run_sync("try again")
  expect_identical(next_result$stop_reason, "request_limit")
  expect_identical(fixture$root$delegation_graph_usage()$requests, 3L)
  child_result <- fixture$root$continue_agent(
    handles[[2L]],
    "try child",
    UsageLimits(max_requests = 1)
  )
  expect_identical(child_result$stop_reason, "request_limit")
  expect_length(fixture$servers[[3L]]$requests(), 1L)
})

test_that("depth count and concurrency reject grandchildren before provider IO", {
  for (kind in c("max_depth", "max_delegations", "max_concurrency")) {
    args <- list(.local_envir = environment())
    args[[kind]] <- 1L
    fixture <- do.call(recursive_fixture, args)
    fixture$configure()
    result <- suppressWarnings(fixture$root$run_sync("compose"))
    expect_identical(trimws(result$response), "root synthesis", info = kind)
    expect_identical(length(fixture$servers[[3L]]$requests()), 0L, info = kind)
    expect_identical(nrow(fixture$root$list_subagents()), 1L, info = kind)
    fixture$root$release_agent_graph()
  }
})

test_that("ancestor hooks cannot be bypassed by a nearer explicit allow", {
  effects <- 0L
  tool <- ellmer::tool(
    function() {
      effects <<- effects + 1L
      "written"
    },
    name = "write_evidence",
    description = "Write",
    arguments = list()
  )
  fixture <- recursive_fixture(leaf_tool = tool)
  root_calls <- 0L
  middle_calls <- 0L
  fixture$root$add_hook(HookMatcher(
    "PreToolUse",
    callback = function(tool_name, ...) {
      root_calls <<- root_calls + 1L
      if (tool_name == "write_evidence") {
        HookResultPreToolUse(permission = "deny")
      }
    }
  ))
  fixture$middle$add_hook(HookMatcher("PreToolUse", callback = function(...) {
    middle_calls <<- middle_calls + 1L
    HookResultPreToolUse(permission = "allow")
  }))
  fixture$configure()
  suppressWarnings(fixture$root$run_sync("compose"))
  expect_identical(effects, 0L)
  expect_identical(root_calls, 3L)
  expect_identical(middle_calls, 2L)
})

test_that("ancestor cancellation stops a queued grandchild before dispatch", {
  fixture <- recursive_fixture()
  fixture$configure()
  fixture$root$add_hook(HookMatcher(
    "SubagentStart",
    callback = function(context, ...) {
      if (identical(context$child_agent_name, "reviewer")) {
        rows <- fixture$root$list_subagents()
        fixture$root$interrupt_subagent(
          rows$delegation_id[[1L]],
          "host_cancelled"
        )
      }
      NULL
    }
  ))
  fixture$root$run_sync("compose")
  expect_length(fixture$servers[[3L]]$requests(), 0L)
  rows <- fixture$root$list_subagents()
  expect_identical(rows$stop_reason, rep("host_cancelled", 2L))
  expect_length(fixture$root$.__enclos_env__$private$active_subagents, 0L)
  expect_identical(fixture$root$delegation_graph_usage()$requests, 3L)
  fixture$root$release_agent_graph()
})

test_that("a configured cycle cannot reenter its busy ancestor", {
  servers <- list(
    local_runtime_server(list(
      runtime_reply(tool = "analyze", arguments = list(task = "analyze")),
      runtime_reply("root finished")
    )),
    local_runtime_server(list(
      runtime_reply(tool = "review", arguments = list(task = "review")),
      runtime_reply("analyst finished")
    )),
    local_runtime_server(list(
      runtime_reply(tool = "recheck", arguments = list(task = "recheck")),
      runtime_reply("reviewer finished")
    ))
  )
  agents <- lapply(servers, function(server) {
    Agent$new(runtime_chat(server), permissions = permissions_full())
  })
  root <- agents[[1L]]
  root$retain_agent_graph(
    agents = list(analyst = agents[[2L]], reviewer = agents[[3L]]),
    routes = list(
      root = list(analyze = recursive_route("analyst")),
      analyst = list(review = recursive_route("reviewer")),
      reviewer = list(recheck = recursive_route("analyst"))
    ),
    usage_limits = UsageLimits(max_requests = 10),
    max_depth = 8L,
    max_delegations = 8L,
    max_concurrency = 8L
  )
  result <- suppressWarnings(root$run_sync("compose"))
  expect_identical(result$usage$requests, 6L)
  expect_identical(root$delegation_graph_usage()$requests, 6L)
  expect_identical(nrow(root$list_subagents()), 2L)
  expect_identical(
    vapply(servers, function(x) length(x$requests()), integer(1)),
    rep(2L, 3L)
  )
  expect_match(jsonlite::toJSON(servers[[3L]]$requests()[[2L]]$body), "busy")
  root$release_agent_graph()
})

test_that("the immediate ancestor's permissions bound grandchild effects", {
  effects <- 0L
  tool <- ellmer::tool(
    function() {
      effects <<- effects + 1L
      "written"
    },
    name = "write_evidence",
    description = "Write",
    arguments = list()
  )
  fixture <- recursive_fixture(
    leaf_tool = tool,
    middle_permissions = Permissions(
      mode = "standard",
      tool_denylist = "write_evidence"
    )
  )
  fixture$configure()
  suppressWarnings(fixture$root$run_sync("compose"))
  expect_identical(effects, 0L)
  expect_length(fixture$servers[[3L]]$requests(), 2L)
  fixture$root$release_agent_graph()
})


test_that("tree tool and observed token ceilings constrain real descendants", {
  for (case in list(
    list(
      limits = UsageLimits(max_requests = 12, max_tool_calls = 1),
      reason = "tool_call_limit",
      counts = c(1L, 1L, 0L)
    ),
    list(
      limits = UsageLimits(max_requests = 12, max_total_tokens = 40),
      reason = "total_token_limit",
      counts = c(1L, 1L, 1L)
    )
  )) {
    fixture <- recursive_fixture(
      graph_limits = case$limits,
      .local_envir = environment()
    )
    fixture$configure()
    result <- suppressWarnings(fixture$root$run_sync("compose"))
    expect_identical(result$stop_reason, case$reason)
    expect_identical(
      vapply(fixture$servers, function(x) length(x$requests()), integer(1)),
      case$counts
    )
    if (case$reason == "total_token_limit") {
      expect_identical(fixture$root$delegation_graph_usage()$total_tokens, 45)
    }
    fixture$root$release_agent_graph()
  }
})

test_that("graph exhaustion preserves the host error policy", {
  fixture <- recursive_fixture(
    graph_limits = UsageLimits(max_requests = 0, on_exceed = "error")
  )
  fixture$configure()
  expect_error(
    fixture$root$run_sync("blocked"),
    class = "deputy_request_limit"
  )
  expect_identical(fixture$root$delegation_graph_usage()$requests, 0L)
  expect_true(all(vapply(
    fixture$servers,
    function(x) length(x$requests()) == 0L,
    logical(1)
  )))
  fixture$root$release_agent_graph()
})

test_that("concurrent siblings share dispatch allowance and settle independently", {
  response <- runtime_reply("evidence")
  attr(response, "fixture_delay") <- 0.15
  server <- local_runtime_server(list(response))
  root <- Agent$new(runtime_chat(server), permissions = permissions_full())
  children <- lapply(c("a", "b"), function(name) {
    Agent$new(
      runtime_chat(server),
      permissions = permissions_full(),
      agent_name = name
    )
  })
  handles <- root$retain_agent_graph(
    agents = setNames(children, c("a", "b")),
    routes = list(),
    usage_limits = UsageLimits(max_requests = 1),
    max_depth = 1,
    max_delegations = 4,
    max_concurrency = 2
  )
  pending <- lapply(handles, function(handle) {
    root$continue_agent_async(handle, "evidence", UsageLimits(max_requests = 1))
  })
  results <- resolve_async_value(promises::promise_all(.list = pending))
  expect_length(server$requests(), 1L)
  expect_identical(root$delegation_graph_usage()$requests, 1L)
  expect_setequal(
    vapply(results, function(x) x$stop_reason, character(1)),
    c("complete", "request_limit")
  )
  expect_length(root$.__enclos_env__$private$active_subagents, 0L)
  root$release_agent_graph()
})

test_that("cancelling one queued sibling leaves another runnable", {
  server <- local_runtime_server(list(runtime_reply("sibling evidence")))
  root <- Agent$new(runtime_chat(server), permissions = permissions_full())
  children <- lapply(c("a", "b"), function(name) {
    Agent$new(
      runtime_chat(server),
      permissions = permissions_full(),
      agent_name = name
    )
  })
  handles <- root$retain_agent_graph(
    agents = setNames(children, c("a", "b")),
    routes = list(),
    usage_limits = UsageLimits(max_requests = 4),
    max_depth = 1,
    max_delegations = 4,
    max_concurrency = 2
  )
  pending <- lapply(handles, function(handle) {
    root$continue_agent_async(handle, "evidence", UsageLimits(max_requests = 1))
  })
  root$cancel_agent(handles[[1L]], "one_cancelled")
  results <- resolve_async_value(promises::promise_all(.list = pending))
  expect_identical(results[[1L]]$stop_reason, "one_cancelled")
  expect_identical(results[[2L]]$stop_reason, "complete")
  expect_length(server$requests(), 1L)
  expect_identical(root$delegation_graph_usage()$requests, 1L)
  expect_length(root$.__enclos_env__$private$active_subagents, 0L)
  root$release_agent_graph()
})

test_that("failed continuation setup releases graph capacity and the busy lease", {
  fixture <- recursive_fixture()
  handles <- fixture$configure()
  local_mocked_bindings(lead_bind_delegation = function(...) {
    abort_deputy("injected binding failure")
  })
  expect_error(
    fixture$root$continue_agent_async(
      handles[[1L]],
      "test",
      UsageLimits(max_requests = 1)
    ),
    "injected binding failure"
  )
  private <- fixture$root$.__enclos_env__$private
  expect_false(private$owned_conversations[[handles[[1L]]]]$busy)
  expect_identical(tree_active_count(private$.delegation_tree), 0L)
  expect_null(fixture$middle$.__enclos_env__$private$.delegation_id)
  expect_identical(fixture$root$list_subagents()$stop_reason, "setup_failed")
  expect_length(fixture$servers[[2L]]$requests(), 0L)
  fixture$root$release_agent_graph()
})


test_that("a failed grandchild preserves partial evidence and settles its tree", {
  tool <- ellmer::tool(
    function() "checked evidence",
    name = "inspect_evidence",
    description = "Inspect evidence",
    arguments = list()
  )
  partial <- runtime_reply(tool = "inspect_evidence")
  partial$body <- sub(
    '"role":"assistant"',
    '"role":"assistant","content":"partial reviewer evidence"',
    partial$body,
    fixed = TRUE
  )
  fixture <- recursive_fixture(
    leaf_tool = tool,
    leaf_responses = list(
      partial,
      runtime_failure()
    )
  )
  fixture$configure()
  result <- suppressWarnings(fixture$root$run_sync("compose"))
  expect_identical(result$stop_reason, "complete")
  expect_identical(result$usage$requests, 6L)
  expect_identical(fixture$root$delegation_graph_usage()$requests, 6L)
  rows <- fixture$root$list_subagents()
  expect_identical(rows$status, c("completed", "failed"))
  views <- fixture$root$inspect_subagents("host", transcript = TRUE)
  expect_match(
    jsonlite::toJSON(views[[2L]]$transcript, auto_unbox = TRUE),
    "partial reviewer evidence"
  )
  expect_true(length(views[[2L]]$transcript) > 0L)
  expect_length(fixture$root$.__enclos_env__$private$active_subagents, 0L)
  fixture$root$release_agent_graph()
})

test_that("finite graph cost permits in-flight siblings but rejects missing settled cost", {
  response <- runtime_reply("priced evidence")
  attr(response, "fixture_delay") <- 0.15
  server <- local_runtime_server(list(response))
  priced_chat <- function() {
    runtime_chat(server, name = "OpenAI")
  }
  root <- Agent$new(priced_chat(), permissions = permissions_full())
  children <- lapply(c("a", "b"), function(name) {
    Agent$new(
      priced_chat(),
      permissions = permissions_full(),
      agent_name = name
    )
  })
  handles <- root$retain_agent_graph(
    agents = setNames(children, c("a", "b")),
    routes = list(),
    usage_limits = UsageLimits(max_requests = 4, max_cost_usd = 0.1),
    max_depth = 1,
    max_delegations = 4,
    max_concurrency = 2
  )
  pending <- lapply(handles, function(handle) {
    root$continue_agent_async(handle, "evidence", UsageLimits(max_requests = 1))
  })
  results <- resolve_async_value(promises::promise_all(.list = pending))
  expect_identical(
    vapply(results, function(x) x$stop_reason, character(1)),
    setNames(rep("complete", 2L), names(handles))
  )
  expect_length(server$requests(), 2L)
  expect_true(is.finite(root$delegation_graph_usage()$cost_usd))
  expect_gt(root$delegation_graph_usage()$cost_usd, 0)
  root$release_agent_graph()

  unknown <- Agent$new(
    runtime_chat(server, model = "unknown-graph-model"),
    permissions = permissions_full()
  )
  handle <- root$retain_agent_graph(
    agents = list(unknown = unknown),
    routes = list(),
    usage_limits = UsageLimits(max_requests = 4, max_cost_usd = 0.1),
    max_depth = 1,
    max_delegations = 4,
    max_concurrency = 1
  )
  result <- root$continue_agent(
    handle[[1L]],
    "unpriced",
    UsageLimits(max_requests = 1)
  )
  expect_identical(result$stop_reason, "cost_unavailable")
  expect_true(is.na(root$delegation_graph_usage()$cost_usd))
  expect_identical(root$run_sync("blocked")$stop_reason, "cost_unavailable")
  expect_length(server$requests(), 3L)
  root$release_agent_graph()
})

test_that("root completion leaves host-launched descendants settled and releasable", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "launch"),
    runtime_reply("root finished")
  ))
  delayed <- runtime_reply("late child")
  attr(delayed, "fixture_delay") <- 0.15
  child_server <- local_runtime_server(list(delayed))
  root <- Agent$new(runtime_chat(root_server), permissions = permissions_full())
  child <- Agent$new(
    runtime_chat(child_server),
    permissions = permissions_full()
  )
  pending <- NULL
  handle <- NULL
  root$register_tool(ellmer::tool(
    function() {
      pending <<- root$continue_agent_async(
        handle,
        "background child",
        UsageLimits(max_requests = 1)
      )
      "launched"
    },
    name = "launch",
    description = "Launch retained child",
    arguments = list()
  ))
  handles <- root$retain_agent_graph(
    agents = list(child = child),
    routes = list(),
    usage_limits = UsageLimits(max_requests = 4),
    max_depth = 1,
    max_delegations = 2,
    max_concurrency = 1
  )
  handle <- handles[[1L]]
  result <- root$run_sync("launch")
  expect_identical(result$stop_reason, "complete")
  expect_length(root$.__enclos_env__$private$active_subagents, 0L)
  child_result <- resolve_async_value(pending)
  expect_identical(child_result$stop_reason, "complete")
  expect_identical(root$list_subagents()$stop_reason, "complete")
  expect_length(root$.__enclos_env__$private$active_subagents, 0L)
  root$release_agent_graph()
})
