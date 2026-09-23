# mcptools 1.0.2/1.0.3 read a stdio reply for about 4 s and do not check its
# JSON-RPC id. These producer tests use a real stdio server (no network).

test_that("a dropped stdio reply fails closed instead of answering a later call", {
  config <- mcp_slow_config()
  agent <- Agent$new(chat = create_mock_chat())
  connection <- McpConnection$new(
    config$path,
    "slow",
    agent,
    tools = "wait",
    timeout = 60
  )
  withr::defer(connection$close())
  wait <- connection$tools()$wait
  expect_error(
    mcp_test_await(wait(seconds = 7), timeout = 60),
    "did not respond within the client's response window",
    class = "deputy_mcp_desynchronized"
  )
  expect_identical(connection$status()$state, "closed")
  expect_identical(connection$status()$reason, "desynchronized")
  # The late "waited 7" reply must never become the next call's answer.
  expect_error(wait(seconds = 0), "closed", class = "deputy_mcp_connection")
  expect_length(mcp_slow_calls(config), 1L)

  fresh <- McpConnection$new(config$path, "slow", agent, tools = "wait")
  withr::defer(fresh$close())
  expect_match(
    mcp_test_await(fresh$tools()$wait(seconds = 0), timeout = 30),
    "^waited 0 for id [0-9]+$"
  )
})

test_that("a reply carrying another request's id is never returned", {
  config <- mcp_slow_config()
  agent <- Agent$new(chat = create_mock_chat())
  connection <- McpConnection$new(
    config$path,
    "slow",
    agent,
    tools = c("stale", "empty", "wait")
  )
  withr::defer(connection$close())
  tools <- connection$tools()
  # A legitimate result with no content is a result, not a lost reply.
  expect_identical(mcp_test_await(tools$empty(), timeout = 30), "")
  expect_error(
    mcp_test_await(tools$stale(), timeout = 30),
    "did not match the request",
    class = "deputy_mcp_desynchronized"
  )
  expect_identical(connection$status()$reason, "desynchronized")
  expect_error(
    tools$wait(seconds = 0),
    "closed",
    class = "deputy_mcp_connection"
  )
})

test_that("tools_mcp() stops a server whose reply was dropped", {
  config <- mcp_slow_config()
  tools <- suppressMessages(tools_mcp(config$path, servers = "slow"))
  expect_identical(tools$empty(), "")
  expect_error(
    tools$wait(seconds = 7),
    "did not respond within the client's response window",
    class = "deputy_mcp_desynchronized"
  )
  expect_error(
    tools$wait(seconds = 0),
    "not running",
    class = "deputy_mcp_server_exit"
  )
  expect_length(mcp_slow_calls(config), 2L)

  fresh <- suppressMessages(tools_mcp(config$path, servers = "slow"))
  withr::defer(asNamespace("mcptools")$mcp_transport_close(
    asNamespace("mcptools")$the$mcp_servers$slow$transport
  ))
  expect_match(fresh$wait(seconds = 0), "^waited 0 for id [0-9]+$")
  expect_error(tools$wait(seconds = 0), "reconnected")
})

test_that("mcp-repl timeout_ms is capped below the transport window", {
  expect_identical(
    mcp_repl_bound_arguments(list(input = "1")),
    list(input = "1", timeout_ms = 3000L)
  )
  expect_identical(
    mcp_repl_bound_arguments(list(input = "1", timeout_ms = 60000)),
    list(input = "1", timeout_ms = 3000)
  )
  expect_identical(
    mcp_repl_bound_arguments(list(input = "1", timeout_ms = 100)),
    list(input = "1", timeout_ms = 100)
  )
  expect_identical(
    mcp_repl_bound_arguments(list(input = "", timeout_ms = 0L)),
    list(input = "", timeout_ms = 0L)
  )
  # Invalid values are left for mcp-repl to reject with its own error.
  expect_identical(
    mcp_repl_bound_arguments(list(input = "1", timeout_ms = "soon")),
    list(input = "1", timeout_ms = "soon")
  )
  expect_match(mcp_repl_tool_description("Run R."), "^Run R\\.")
  expect_match(mcp_repl_tool_description("Run R."), "3000 ms")
})

test_that("long mcp-repl work returns busy instead of desynchronizing", {
  config <- mcp_slow_config(repl = TRUE)
  agent <- Agent$new(chat = create_mock_chat())
  connection <- mcp_repl_connection(config$path, agent, server = "slow")
  withr::defer(connection$close())
  repl <- connection$tools()$repl
  expect_match(repl@description, "caps `timeout_ms` at 3000 ms")
  call <- function(...) mcp_test_await(repl(...), timeout = 30)
  expect_identical(
    call(input = "sleep 10", timeout_ms = 60000),
    "<<repl status: busy>>"
  )
  expect_identical(call(input = ""), "done")
  expect_identical(call(input = "x", timeout_ms = 100), "done")
  expect_identical(
    mcp_test_await(mcp_repl_control(connection, "interrupt"), timeout = 30),
    "done"
  )
  expect_identical(connection$status()$state, "idle")
  expect_identical(
    sub(".* timeout_ms=", "", mcp_slow_calls(config)),
    c("3000", "3000", "100", "3000")
  )
})

test_that("tools_mcp_repl() applies the same timeout_ms bound", {
  config <- mcp_slow_config(repl = TRUE)
  tools <- suppressMessages(tools_mcp_repl(config$path, server = "slow"))
  withr::defer(asNamespace("mcptools")$mcp_transport_close(
    asNamespace("mcptools")$the$mcp_servers$slow$transport
  ))
  repl <- tools$repl
  expect_match(repl@description, "caps `timeout_ms` at 3000 ms")
  expect_identical(tool_metadata(repl)$source$type, "mcp")
  expect_identical(tools$wait@description, "Wait before replying.")
  expect_identical(
    repl(input = "sleep 10", timeout_ms = 60000),
    "<<repl status: busy>>"
  )
  expect_identical(repl(input = ""), "done")
  expect_identical(
    sub(".* timeout_ms=", "", mcp_slow_calls(config)),
    c("3000", "3000")
  )
})
