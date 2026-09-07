mcp_test_config <- function() {
  skip_if_not_installed("mcptools", "1.0.2")
  skip_if(as.character(utils::packageVersion("mcptools")) != "1.0.2")
  path <- tempfile(fileext = ".json")
  log <- tempfile()
  file.create(log)
  jsonlite::write_json(
    list(
      mcpServers = list(
        fixture = list(
          command = file.path(R.home("bin"), "Rscript"),
          args = list(
            normalizePath(test_path("fixtures", "mcp-capabilities.R")),
            log
          )
        ),
        excluded = list(command = "deputy-must-not-start-this-server")
      )
    ),
    path,
    auto_unbox = TRUE
  )
  list(path = path, log = log)
}

mcp_test_await <- function(value, timeout = 10) {
  done <- FALSE
  result <- NULL
  error <- NULL
  promises::then(
    value,
    function(x) {
      result <<- x
      done <<- TRUE
    },
    function(e) {
      error <<- e
      done <<- TRUE
    }
  )
  until <- Sys.time() + timeout
  while (!done && Sys.time() < until) {
    later::run_now(0.01)
  }
  if (!done) {
    stop("MCP test promise did not settle.")
  }
  if (!is.null(error)) {
    stop(error)
  }
  result
}

test_that("independent connections preserve exact selection, state and ownership", {
  config <- mcp_test_config()
  agent_a <- Agent$new(chat = create_mock_chat())
  agent_b <- Agent$new(chat = create_mock_chat())
  a <- McpConnection$new(config$path, "fixture", agent_a, tools = "state")
  withr::defer(a$close())
  b <- McpConnection$new(config$path, "fixture", agent_b, tools = "state")
  withr::defer(b$close())
  tool_a <- a$tools()$state
  tool_b <- b$tools()$state
  expect_match(
    paste(mcp_test_await(tool_a(operation = "set", value = "alpha"))),
    "alpha"
  )
  expect_match(paste(mcp_test_await(tool_b(operation = "get"))), "empty")
  expect_match(paste(mcp_test_await(tool_a(operation = "get"))), "alpha")
  expect_false(identical(a$status()$connection_id, b$status()$connection_id))
  expect_identical(a$status()$owner$agent_id, agent_a$agent_id)
  expect_identical(tool_metadata(tool_a)$source$server, "fixture")
  expect_false(tool_metadata(tool_a)$annotations$read_only_hint)
  expect_error(
    agent_b$register_tools(a$tools()),
    "different Agent",
    class = "deputy_tool_registration"
  )
  agent_a$register_tools(a$tools())
  expect_named(agent_a$get_tools(), "state")
  expect_equal(sum(readLines(config$log) == "initialize "), 2L)
  a$close()
  expect_error(
    tool_a(operation = "get"),
    "closed",
    class = "deputy_mcp_connection"
  )
  expect_match(paste(mcp_test_await(tool_b(operation = "get"))), "empty")
  expect_null(a$close())
})

test_that("catalogue discovery does not authorize resource or prompt access", {
  config <- mcp_test_config()
  agent <- Agent$new(chat = create_mock_chat())
  connection <- McpConnection$new(
    config$path,
    "fixture",
    agent,
    resources = "fixture://allowed",
    prompts = "summarize"
  )
  withr::defer(connection$close())
  first <- mcp_test_await(connection$discover("resources"))
  second <- mcp_test_await(connection$discover(
    "resources",
    first$result$nextCursor
  ))
  expect_identical(second$result$resources[[1]]$uri, "fixture://denied")
  expect_named(connection$tools(), character())
  expect_length(agent$get_tools(), 0L)
  before <- readLines(config$log)
  expect_error(
    connection$read_resource("fixture://denied"),
    class = "deputy_permission_denied"
  )
  expect_error(
    connection$get_prompt("unlisted"),
    class = "deputy_permission_denied"
  )
  expect_identical(readLines(config$log), before)
  resource <- mcp_test_await(connection$read_resource("fixture://allowed"))
  expect_identical(resource$source$operation, "resources/read")
  expect_identical(resource$result$contents[[1]]$text, "resource empty")
  prompt <- mcp_test_await(connection$get_prompt(
    "summarize",
    list(topic = "evidence")
  ))
  expect_identical(
    prompt$result$messages[[1]]$content$text,
    "Summarize empty evidence"
  )
  expect_length(agent$get_turns(), 0L)
  expect_error(
    mcp_test_await(connection$discover("resource_templates")),
    "unavailable"
  )
  expect_identical(connection$status()$state, "idle")
  capability_tools <- connection$capability_tools()
  expect_named(capability_tools, c("mcp_read_resource", "mcp_get_prompt"))
  deny <- permissions_check(
    Permissions(web = FALSE),
    "mcp_read_resource",
    list(uri = "fixture://allowed"),
    list(
      tool_metadata = tool_metadata(capability_tools[[1]]),
      tool_annotations = capability_tools[[1]]@annotations
    )
  )
  expect_s7_class(deny, PermissionResultDeny)
  expect_error(connection$get_prompt("summarize", list(topic = 1)), "argument")
  expect_error(
    connection$discover("resources", cursor = NA_character_),
    "cursor"
  )
})

test_that("active calls keep the host responsive and cancellation invalidates handles", {
  config <- mcp_test_config()
  agent <- Agent$new(chat = create_mock_chat())
  connection <- McpConnection$new(
    config$path,
    "fixture",
    agent,
    tools = "state"
  )
  withr::defer(connection$close())
  tool <- connection$tools()$state
  pending <- tool(operation = "slow")
  expect_identical(connection$status()$state, "busy")
  expect_error(tool(operation = "get"), class = "deputy_mcp_busy")
  ticked <- FALSE
  later::later(
    function() {
      ticked <<- TRUE
    },
    0
  )
  later::run_now(0.05)
  expect_true(ticked)
  expect_identical(connection$status()$state, "busy")
  connection$cancel()
  expect_error(
    mcp_test_await(pending),
    "cancelled",
    class = "deputy_mcp_connection"
  )
  expect_identical(connection$status()$reason, "cancelled")
  expect_false(mcp_tool_is_current(tool))
  expect_error(tool(operation = "get"), "closed")
})

test_that("request timeout discards the session instead of silently reconnecting", {
  config <- mcp_test_config()
  agent <- Agent$new(chat = create_mock_chat())
  connection <- McpConnection$new(
    config$path,
    "fixture",
    agent,
    tools = "state",
    timeout = 0.2
  )
  withr::defer(connection$close())
  tool <- connection$tools()$state
  expect_error(
    mcp_test_await(tool(operation = "slow")),
    "timeout",
    class = "deputy_mcp_connection"
  )
  expect_identical(connection$status()$state, "closed")
  expect_identical(connection$status()$reason, "timeout")
  expect_error(tool(operation = "get"), "closed")
})

test_that("connection validation fails before starting an unselected server", {
  config <- mcp_test_config()
  agent <- Agent$new(chat = create_mock_chat())
  expect_error(McpConnection$new(config$path, "absent", agent), "exact")
  expect_error(
    McpConnection$new(
      config$path,
      "fixture",
      agent,
      tools = c("state", "state")
    ),
    "unique"
  )
  expect_error(
    McpConnection$new(config$path, "fixture", agent, timeout = Inf),
    "finite"
  )
  expect_identical(readLines(config$log), character())
  expect_error(
    McpConnection$new(config$path, "fixture", agent, tools = "absent"),
    "every allowed tool"
  )
})

test_that("resource tools traverse Agent permission and hook boundaries", {
  config <- mcp_test_config()
  for (web in c(FALSE, TRUE)) {
    agent <- NULL
    received <- NULL
    observed <- NULL
    fixture <- create_shiny_tool_chat(
      "mcp_read_resource",
      list(uri = "fixture://allowed"),
      execute = function(request) {
        received <<- mcp_test_await(do.call(
          agent$get_tools()$mcp_read_resource,
          request@arguments
        ))
      }
    )
    agent <- Agent$new(
      chat = fixture$chat,
      permissions = Permissions(web = web)
    )
    connection <- McpConnection$new(
      config$path,
      "fixture",
      agent,
      resources = "fixture://allowed"
    )
    withr::defer(connection$close())
    agent$register_tools(connection$capability_tools())
    agent$add_hook(HookMatcher(
      event = "PreToolUse",
      timeout = 0,
      callback = function(tool_name, tool_input, context) {
        observed <<- context$tool_metadata
        NULL
      }
    ))
    before <- sum(readLines(config$log) == "resources/read ")
    result <- agent$run_sync("Read the allowed resource.")
    expect_identical(fixture$state$executed, web)
    after <- sum(readLines(config$log) == "resources/read ")
    expect_equal(after - before, as.integer(web))
    if (web) {
      expect_identical(
        observed$source$connection_id,
        connection$status()$connection_id
      )
      expect_identical(received$result$contents[[1]]$text, "resource empty")
    } else {
      expect_null(received)
    }
    connection$close()
  }
})

test_that("server exit is reported as state loss and old handles stay invalid", {
  config <- mcp_test_config()
  agent <- Agent$new(chat = create_mock_chat())
  connection <- McpConnection$new(
    config$path,
    "fixture",
    agent,
    tools = "state"
  )
  withr::defer(connection$close())
  tool <- connection$tools()$state
  expect_error(
    mcp_test_await(tool(operation = "crash")),
    "session state is lost"
  )
  expect_identical(connection$status()$reason, "server_exited")
  expect_error(tool(operation = "get"), "closed")
})
