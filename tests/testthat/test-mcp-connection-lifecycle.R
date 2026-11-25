test_that("Agent interruption terminates its active owned MCP request", {
  config <- mcp_test_config()
  agent <- NULL
  interrupted <- FALSE
  fixture <- create_shiny_tool_chat(
    "state",
    list(operation = "slow"),
    execute = function(request) {
      pending <- do.call(agent$get_tools()$state, request@arguments)
      later::later(
        function() {
          interrupted <<- agent$interrupt()
        },
        0.01
      )
      mcp_test_await(pending)
    }
  )
  agent <- Agent$new(chat = fixture$chat, permissions = permissions_full())
  connection <- McpConnection$new(
    config$path,
    "fixture",
    agent,
    tools = "state"
  )
  withr::defer(connection$close())
  agent$register_tools(connection$tools())
  result <- tryCatch(agent$run_sync("Run the slow request."), error = identity)
  expect_true(interrupted)
  expect_identical(connection$status()$reason, "cancelled")
  expect_identical(connection$status()$state, "closed")
  expect_s7_class(result, AgentResult)
  expect_identical(result$stop_reason, "interrupted")
})

test_that("registry changes cannot detach an active MCP call from interruption", {
  for (mutation in c("remove", "replace")) {
    config <- mcp_test_config()
    agent <- NULL
    changed <- FALSE
    interrupted <- FALSE
    fixture <- create_shiny_tool_chat(
      "state",
      list(operation = "slow"),
      execute = function(request) {
        pending <- do.call(agent$get_tools()$state, request@arguments)
        later::later(
          function() {
            if (mutation == "remove") {
              agent$set_tools(list())
            } else {
              agent$register_tool(
                ellmer::tool(
                  function(operation) "replacement",
                  name = "state",
                  description = "Replacement local tool.",
                  arguments = list(operation = ellmer::type_string())
                ),
                replace = TRUE
              )
            }
            changed <<- TRUE
            interrupted <<- agent$interrupt()
          },
          0.01
        )
        mcp_test_await(pending)
      }
    )
    agent <- Agent$new(chat = fixture$chat, permissions = permissions_full())
    connection <- McpConnection$new(
      config$path,
      "fixture",
      agent,
      tools = "state"
    )
    withr::defer(connection$close())
    agent$register_tools(connection$tools())
    result <- agent$run_sync("Run the slow request.")
    expect_true(changed)
    expect_true(interrupted)
    expect_identical(connection$status()$reason, "cancelled")
    expect_identical(connection$status()$state, "closed")
    expect_identical(result$stop_reason, "interrupted")
    if (mutation == "remove") {
      expect_length(agent$get_tools(), 0L)
    } else {
      expect_named(agent$get_tools(), "state")
    }
    connection$close()
  }
})

test_that("clones do not retain the original Agent's pending executions", {
  config <- mcp_test_config()
  owner <- Agent$new(chat = create_mock_chat())
  connection <- McpConnection$new(
    config$path,
    "fixture",
    owner,
    tools = "state"
  )
  withr::defer(connection$close())
  owner$register_tools(connection$tools())
  first <- owner$get_tools()$state(operation = "slow")
  owner$set_tools(list())
  clone <- owner$clone()
  expect_length(clone$get_tools(), 0L)
  expect_match(paste(mcp_test_await(first)), "empty")
  later_request <- connection$tools()$state(operation = "slow")
  clone$add_hook(HookMatcher("UserPromptSubmit", callback = function(...) {
    clone$interrupt()
    NULL
  }))
  result <- clone$run_sync("Stop this run.")
  expect_identical(result$stop_reason, "interrupted")
  expect_identical(result$usage$tool_calls, 0L)
  expect_identical(connection$status()$state, "busy")
  expect_match(paste(mcp_test_await(later_request)), "empty")
  expect_identical(connection$status()$state, "idle")
})

test_that("interruption cannot cancel MCP requests owned by a different context", {
  for (scenario in c("loaded", "run")) {
    config <- mcp_test_config()
    owner <- Agent$new(chat = create_mock_chat())
    connection <- McpConnection$new(
      config$path,
      "fixture",
      owner,
      tools = "state"
    )
    withr::defer(connection$close())
    owner$register_tools(connection$tools())
    actor <- if (scenario == "loaded") owner$clone() else owner
    if (scenario == "loaded") {
      saved <- Agent$new(
        chat = create_mock_chat(),
        run_context = list(reader_id = "other")
      )
      path <- tempfile(fileext = ".rds")
      saved$save_session(path)
      actor$load_session(path)
    }
    actor$add_hook(HookMatcher(
      "UserPromptSubmit",
      callback = function(...) {
        actor$interrupt()
        NULL
      }
    ))
    pending <- connection$tools()$state(operation = "slow")
    expect_identical(connection$status()$state, "busy")
    result <- if (scenario == "run") {
      actor$run_sync("Stop this run.", run_context = list(reader_id = "other"))
    } else {
      actor$run_sync("Stop this run.")
    }
    expect_identical(result$stop_reason, "interrupted")
    expect_identical(result$usage$tool_calls, 0L)
    expect_identical(connection$status()$state, "busy")
    expect_match(paste(mcp_test_await(pending)), "empty")
    expect_identical(connection$status()$state, "idle")
    expect_match(
      paste(mcp_test_await(connection$tools()$state(operation = "get"))),
      "empty"
    )
    connection$close()
  }
})
