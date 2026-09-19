tree_budget_test_agent <- function(id, tree = NULL) {
  agent <- Agent$new(
    chat = create_mock_chat(),
    agent_id = id,
    usage_limits = UsageLimits(max_requests = 100L)
  )
  private <- agent$.__enclos_env__$private
  private$.delegation_tree <- tree
  private$current_external_usage <- AgentUsage()
  state <- new.env(parent = emptyenv())
  state$tokens <- data.frame(
    input = numeric(),
    output = numeric(),
    cached_input = numeric(),
    cost = numeric()
  )
  attr(private$.chat, "tree_budget_state") <- state
  private$.chat$get_tokens <- function() state$tokens
  agent
}

tree_budget_test_begin <- function(agent, run_id, usage) {
  private <- agent$.__enclos_env__$private
  state <- attr(private$.chat, "tree_budget_state", exact = TRUE)
  private$.chat$set_turns(list())
  state$tokens <- data.frame(
    input = numeric(),
    output = numeric(),
    cached_input = numeric(),
    cost = numeric()
  )
  private$current_usage_baseline <- agent_usage_snapshot(private$.chat)
  requests <- usage$requests
  divide <- function(value) {
    if (requests == 0L) numeric() else rep(value / requests, requests)
  }
  state$tokens <- data.frame(
    input = divide(usage$input_tokens),
    output = divide(usage$output_tokens),
    cached_input = divide(usage$cached_tokens),
    cost = if (requests == 0L) {
      numeric()
    } else {
      rep(usage$cost_usd / requests, requests)
    }
  )
  private$.chat$set_turns(lapply(seq_len(requests), function(index) {
    create_mock_assistant_turn(
      tokens = c(
        usage$input_tokens / requests,
        usage$output_tokens / requests,
        usage$cached_tokens / requests
      ),
      cost = usage$cost_usd / requests
    )
  }))
  private$current_run_id <- run_id
  private$run_active <- TRUE
  private$current_tool_calls <- usage$tool_calls
  private$current_outer_requests <- 0L
  private$current_external_usage <- AgentUsage()
  private$current_run_state <- list(finished = FALSE)
  tree_run_started(agent)
}

tree_budget_test_tree <- function(
  root,
  limits = UsageLimits(max_requests = 100L),
  max_depth = 3L,
  max_delegations = 10L,
  max_concurrency = 3L
) {
  tree <- new_delegation_tree(
    root,
    limits,
    max_depth,
    max_delegations,
    max_concurrency
  )
  root$.__enclos_env__$private$.delegation_tree <- tree
  tree
}

test_that("delegation trees require finite budgets and positive bounds", {
  root <- tree_budget_test_agent("root")

  tree <- tree_budget_test_tree(
    root,
    UsageLimits(max_requests = 5L, max_cost_usd = 1),
    max_depth = 2L,
    max_delegations = 4L,
    max_concurrency = 2L
  )
  expect_true(rlang::is_weakref(tree$root))
  expect_s7_class(tree$limits, UsageLimits)
  expect_identical(tree$max_depth, 2L)
  expect_identical(tree$max_delegations, 4L)
  expect_identical(tree$max_concurrency, 2L)
  expect_s7_class(tree$usage, AgentUsage)

  expect_error(
    new_delegation_tree(root, UsageLimits(), 1L, 1L, 1L),
    "finite.*max_requests"
  )
  expect_error(
    new_delegation_tree(
      root,
      structure(list(), class = "UsageLimits"),
      1L,
      1L,
      1L
    ),
    "explicit UsageLimits"
  )
  expect_error(
    new_delegation_tree(root, UsageLimits(max_requests = 1L), 0L, 1L, 1L),
    "max_depth.*positive"
  )
  expect_error(
    new_delegation_tree(root, UsageLimits(max_requests = 1L), 1L, Inf, 1L),
    "max_delegations.*positive"
  )
  expect_error(
    new_delegation_tree(root, UsageLimits(max_requests = 1L), 1L, 1L, 1.5),
    "max_concurrency.*positive"
  )
})

test_that("admission enforces depth, lifetime count, and live concurrency", {
  root <- tree_budget_test_agent("root")
  tree <- tree_budget_test_tree(
    root,
    max_depth = 2L,
    max_delegations = 2L,
    max_concurrency = 1L
  )

  first <- tree_admit(tree, "first")
  expect_identical(first$parent_delegation_id, NULL)
  expect_identical(first$depth, 1L)
  expect_identical(first$root_agent_id, "root")
  expect_identical(tree$count, 1L)
  expect_error(tree_admit(tree, "sibling"), "maximum concurrency")
  expect_identical(tree$count, 1L)

  tree_settle(tree, "first")
  tree_settle(tree, "first")
  expect_false(tree$admissions$first$active)
  expect_identical(tree$admissions$first$depth, 1L)

  second <- tree_admit(tree, "second")
  expect_identical(second$depth, 1L)
  expect_error(tree_admit(tree, "nested", "missing"), "unknown or settled")
  expect_identical(tree$count, 2L)
  tree_settle(tree, "second")
  expect_error(tree_admit(tree, "third"), "maximum.*admitted")
  expect_identical(tree$count, 2L)
  expect_error(tree_admit(tree, "child", "second"), "unknown or settled")

  depth_tree <- tree_budget_test_tree(
    root,
    max_depth = 1L,
    max_delegations = 4L,
    max_concurrency = 3L
  )
  tree_admit(depth_tree, "parent")
  expect_error(
    tree_admit(depth_tree, "child", "parent"),
    "maximum depth"
  )
  expect_identical(depth_tree$count, 1L)
})

test_that("nested admissions count awaiting callers toward concurrency", {
  root <- tree_budget_test_agent("root")
  tree <- tree_budget_test_tree(
    root,
    max_depth = 2L,
    max_delegations = 5L,
    max_concurrency = 2L
  )

  tree_admit(tree, "parent")
  child <- tree_admit(tree, "child", "parent")
  expect_identical(child$depth, 2L)
  expect_error(tree_admit(tree, "sibling"), "maximum concurrency")

  tree_settle(tree, "child")
  tree_settle(tree, "parent")
  expect_identical(
    sum(vapply(tree$admissions, function(x) isTRUE(x$active), logical(1))),
    0L
  )
  expect_silent(tree_admit(tree, "after"))
})

test_that("active and completed usage is counted once across nested callers", {
  root <- tree_budget_test_agent("root")
  child <- tree_budget_test_agent("child")
  grandchild <- tree_budget_test_agent("grandchild")
  tree <- tree_budget_test_tree(root)
  child$.__enclos_env__$private$.delegation_tree <- tree
  grandchild$.__enclos_env__$private$.delegation_tree <- tree

  tree_budget_test_begin(
    root,
    "root-run",
    AgentUsage(
      requests = 1L,
      tool_calls = 1L,
      input_tokens = 10,
      output_tokens = 5,
      cost_usd = 0.1
    )
  )
  tree_budget_test_begin(
    child,
    "child-run",
    AgentUsage(
      requests = 2L,
      tool_calls = 2L,
      input_tokens = 20,
      output_tokens = 10,
      cost_usd = 0.2
    )
  )
  tree_budget_test_begin(
    grandchild,
    "grandchild-run",
    AgentUsage(
      requests = 3L,
      tool_calls = 3L,
      input_tokens = 30,
      output_tokens = 15,
      cost_usd = 0.3
    )
  )

  expect_identical(tree_usage(tree)$requests, 6L)
  grandchild_usage <- grandchild$.__enclos_env__$private$current_run_usage()
  tree_run_finished(grandchild)
  tree_child_usage(child, grandchild_usage)
  child$.__enclos_env__$private$current_external_usage <- agent_usage_add(
    child$.__enclos_env__$private$current_external_usage,
    grandchild_usage
  )
  expect_identical(
    child$.__enclos_env__$private$current_external_usage$requests,
    3L
  )

  child_usage <- child$.__enclos_env__$private$current_run_usage()
  tree_run_finished(child)
  tree_child_usage(root, child_usage)
  root$.__enclos_env__$private$current_external_usage <- agent_usage_add(
    root$.__enclos_env__$private$current_external_usage,
    child_usage
  )
  expect_identical(
    root$.__enclos_env__$private$current_external_usage$requests,
    5L
  )
  expect_identical(tree_usage(tree)$requests, 6L)

  tree_run_finished(root)
  expect_identical(tree$usage$requests, 6L)
  expect_identical(tree_usage(tree)$tool_calls, 6L)
  expect_equal(tree_usage(tree)$input_tokens, 60)
  expect_equal(tree_usage(tree)$output_tokens, 30)
  expect_equal(tree_usage(tree)$cost_usd, 0.6, tolerance = 1e-12)
  expect_length(tree$active, 0L)
})

test_that("graph usage persists across root runs and fails closed on unknown cost", {
  root <- tree_budget_test_agent("root")
  tree <- tree_budget_test_tree(
    root,
    UsageLimits(max_requests = 3L, max_cost_usd = 1),
    max_depth = 1L,
    max_delegations = 2L,
    max_concurrency = 1L
  )

  tree_budget_test_begin(
    root,
    "run-1",
    AgentUsage(requests = 2L, cost_usd = 0.2)
  )
  tree_run_finished(root)
  expect_identical(tree$usage$requests, 2L)
  expect_null(tree_usage_status(root))

  tree_budget_test_begin(
    root,
    "run-2",
    AgentUsage(requests = 1L, cost_usd = 0.3)
  )
  tree_run_finished(root)
  expect_identical(tree$usage$requests, 3L)
  expect_identical(tree_usage_status(root)$reason, "request_limit")
  expect_identical(tree_usage_status(root)$on_exceed, "stop")
  expect_null(tree_usage_status(root, require_followup = FALSE))

  unknown_root <- tree_budget_test_agent("unknown-root")
  unknown_tree <- tree_budget_test_tree(
    unknown_root,
    UsageLimits(max_requests = 5L, max_cost_usd = 1)
  )
  tree_budget_test_begin(
    unknown_root,
    "unknown-run",
    AgentUsage(requests = 1L, cost_usd = NA_real_)
  )
  tree_run_finished(unknown_root)
  status <- tree_usage_status(unknown_root)
  expect_identical(status$reason, "cost_unavailable")
  expect_identical(status$field, "max_cost_usd")
})

test_that("in-flight requests without a cost row remain measurable", {
  root <- tree_budget_test_agent("pending-root")
  tree <- tree_budget_test_tree(
    root,
    UsageLimits(max_requests = 2L, max_cost_usd = 1)
  )
  private <- root$.__enclos_env__$private
  state <- attr(private$.chat, "tree_budget_state", exact = TRUE)
  private$.chat$set_turns(list())
  state$tokens <- data.frame(
    input = numeric(),
    output = numeric(),
    cached_input = numeric(),
    cost = numeric()
  )
  private$current_usage_baseline <- agent_usage_snapshot(private$.chat)
  private$current_run_id <- "pending-run"
  private$run_active <- TRUE
  private$current_outer_requests <- 1L
  private$current_tool_calls <- 0L
  private$current_external_usage <- AgentUsage()
  private$current_run_state <- list(finished = FALSE)
  tree_run_started(root)

  expect_null(tree_usage_status(root))
  expect_identical(tree_usage(tree)$requests, 1L)
  expect_identical(tree_usage(tree)$cost_usd, 0)
  private$current_run_state <- list(finished = TRUE)
  expect_identical(tree_usage_status(root)$reason, "cost_unavailable")
})

test_that("child usage is a no-op without a live caller run", {
  root <- tree_budget_test_agent("root")
  tree <- tree_budget_test_tree(root)
  private <- root$.__enclos_env__$private
  before <- private$current_external_usage
  private$current_run_id <- NULL

  expect_invisible(tree_child_usage(root, AgentUsage(requests = 2L)))
  expect_identical(private$current_external_usage, before)
  expect_identical(tree_usage(tree), AgentUsage())
})
