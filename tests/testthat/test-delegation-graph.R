graph_test_agent <- function(text = "answer", ...) {
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

graph_test_owner <- function(...) {
  graph_test_agent(
    delegation_disclosure = DelegationDisclosure(
      authorize = function(requester, scope) identical(requester, "owner")
    ),
    ...
  )
}

graph_test_route <- function(target, requests = 2L) {
  list(
    target = target,
    description = paste("Ask", target),
    usage_limits = UsageLimits(max_requests = requests)
  )
}

graph_test_configure <- function(root, left, right, routes) {
  root$retain_agent_graph(
    agents = list(left = left, right = right),
    routes = routes,
    usage_limits = UsageLimits(max_requests = 8L),
    max_depth = 3L,
    max_delegations = 8L,
    max_concurrency = 2L
  )
}

graph_test_expect_unowned <- function(root, members) {
  root_private <- root$.__enclos_env__$private
  expect_length(root_private$owned_conversations, 0L)
  expect_null(root_private$.delegation_tree)
  for (agent in members) {
    private <- agent$.__enclos_env__$private
    expect_null(private$.conversation_owner)
    expect_null(private$.delegation_tree)
    expect_null(attr(private$.chat, "deputy_conversation_owner"))
  }
}

test_that("graph validation rejects malformed input before acquiring leases", {
  root <- graph_test_owner()
  left <- graph_test_agent()
  right <- graph_test_agent()
  before <- lapply(c(list(root), list(left, right)), function(agent) {
    agent$get_tools()
  })

  expect_error(
    root$retain_agent_graph(
      agents = list(left = left, right = right),
      routes = list(root = list(bad = graph_test_route("missing"))),
      usage_limits = UsageLimits(max_requests = 8L),
      max_depth = 3L,
      max_delegations = 8L,
      max_concurrency = 2L
    ),
    class = "deputy_conversation"
  )
  graph_test_expect_unowned(root, list(left, right))
  expect_identical(root$get_tools(), before[[1L]])
  expect_identical(left$get_tools(), before[[2L]])
  expect_identical(right$get_tools(), before[[3L]])

  expect_error(
    root$retain_agent_graph(
      agents = list(left = left, right = right),
      routes = list(root = list(list(graph_test_route("left")))),
      usage_limits = UsageLimits(max_requests = 8L),
      max_depth = 3L,
      max_delegations = 8L,
      max_concurrency = 2L
    ),
    class = "deputy_conversation"
  )
  graph_test_expect_unowned(root, list(left, right))
})

test_that("graph validation rejects duplicate aliases and route collisions atomically", {
  root <- graph_test_owner()
  left <- graph_test_agent()
  alias <- Agent$new(left$.__enclos_env__$private$.chat)

  expect_error(
    root$retain_agent_graph(
      agents = list(left = left, alias = alias),
      routes = list(),
      usage_limits = UsageLimits(max_requests = 8L),
      max_depth = 2L,
      max_delegations = 4L,
      max_concurrency = 1L
    ),
    class = "deputy_conversation"
  )
  graph_test_expect_unowned(root, list(left, alias))

  collision <- ellmer::tool(
    function() "existing",
    name = "ask_left",
    description = "Existing tool",
    arguments = list()
  )
  root$register_tool(collision)
  expect_error(
    root$retain_agent_graph(
      agents = list(left = left),
      routes = list(root = list(ask_left = graph_test_route("left"))),
      usage_limits = UsageLimits(max_requests = 8L),
      max_depth = 2L,
      max_delegations = 4L,
      max_concurrency = 1L
    ),
    class = "deputy_conversation"
  )
  graph_test_expect_unowned(root, list(left))
  expect_true("ask_left" %in% names(root$get_tools()))
})

test_that("cyclic graph routes record their actual callers and release atomically", {
  root <- graph_test_owner()
  left <- graph_test_agent()
  right <- graph_test_agent()
  resource <- new.env(parent = emptyenv())
  resource$value <- "borrowed"
  left$register_tool(ellmer::tool(
    function() resource$value,
    name = "borrowed",
    description = "Borrowed resource",
    arguments = list()
  ))
  left_tools <- left$get_tools()
  root$register_tool(ellmer::tool(
    function() "base",
    name = "base",
    description = "Base tool",
    arguments = list()
  ))

  handles <- graph_test_configure(
    root,
    left,
    right,
    routes = list(
      root = list(to_left = graph_test_route("left")),
      left = list(to_right = graph_test_route("right")),
      right = list(to_left_again = graph_test_route("left"))
    )
  )
  expect_identical(names(handles), c("left", "right"))
  tree <- root$.__enclos_env__$private$.delegation_tree
  expect_false("root" %in% names(tree$agents))
  expect_identical(names(tree$handles), c("left", "right"))
  expect_identical(composition_tool_owner(root$get_tools()[["to_left"]]), root)
  expect_identical(composition_tool_owner(left$get_tools()[["to_right"]]), left)
  expect_identical(
    composition_tool_owner(right$get_tools()[["to_left_again"]]),
    right
  )
  left_private <- left$.__enclos_env__$private
  left_private$ensure_tool_result_reader()
  expect_true(isTRUE(left_private$.tool_result_reader_registered))
  expect_error(
    left$release_agent(handles[["left"]]),
    class = "deputy_conversation"
  )

  root$register_tool(ellmer::tool(
    function() "late",
    name = "late",
    description = "Added after graph setup",
    arguments = list()
  ))
  root$release_agent_graph()

  graph_test_expect_unowned(root, list(left, right))
  expect_true("borrowed" %in% names(left$get_tools()))
  expect_true("deputy_read_tool_result" %in% names(left$get_tools()))
  expect_true(isTRUE(left_private$.tool_result_reader_registered))
  expect_true(all(c("base", "late") %in% names(root$get_tools())))
  expect_false(any(c("to_left", "to_left_again") %in% names(root$get_tools())))
  expect_identical(left$run_sync("released")$response, "answer")
  expect_identical(right$run_sync("released")$response, "answer")
  expect_identical(resource$value, "borrowed")
})

test_that("route installation failure rolls back every acquired lease", {
  root <- graph_test_owner()
  left <- graph_test_agent()
  right <- graph_test_agent()
  original <- get("graph_route_install", asNamespace("deputy"))
  local_mocked_bindings(
    graph_route_install = function(
      tree,
      source_name,
      source,
      route_name,
      spec
    ) {
      if (identical(route_name, "fail")) {
        graph_abort("injected route installation failure")
      }
      original(tree, source_name, source, route_name, spec)
    }
  )

  expect_error(
    graph_test_configure(
      root,
      left,
      right,
      routes = list(
        root = list(first = graph_test_route("left")),
        left = list(fail = graph_test_route("right"))
      )
    ),
    "injected route installation failure",
    class = "deputy_conversation"
  )
  graph_test_expect_unowned(root, list(left, right))
  expect_false("first" %in% names(root$get_tools()))
  expect_false("fail" %in% names(left$get_tools()))
})

test_that("graph finalization can release through a cleared weak root", {
  root <- graph_test_owner()
  left <- graph_test_agent()
  right <- graph_test_agent()
  graph_test_configure(
    root,
    left,
    right,
    routes = list(root = list(to_left = graph_test_route("left")))
  )
  tree <- root$.__enclos_env__$private$.delegation_tree
  weak_target <- new.env(parent = emptyenv())
  tree$root <- rlang::new_weakref(weak_target)
  rm(weak_target)
  gc()

  expect_error(delegation_tree_root(tree), "no longer available")
  finalize_delegation_graph(root)
  graph_test_expect_unowned(root, list(left, right))
  expect_false("to_left" %in% names(root$get_tools()))
  expect_identical(left$run_sync("released")$response, "answer")
})

test_that("graph finalizer releases a root while a routed child remains alive", {
  left <- graph_test_agent()
  right <- graph_test_agent()
  root <- graph_test_owner()
  graph_test_configure(
    root,
    left,
    right,
    routes = list(root = list(to_left = graph_test_route("left")))
  )
  left_private <- left$.__enclos_env__$private
  root <- NULL
  invisible(gc())

  expect_null(left_private$.delegation_tree)
  expect_null(left_private$.conversation_owner)
  expect_identical(left$run_sync("released")$response, "answer")
})
