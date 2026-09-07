test_that("sandbox mode overrides cannot bypass the selected policy", {
  expect_error(
    validate_mcp_repl_sandbox_server(
      list(
        command = "mcp-repl",
        args = c("--sandbox", "workspace-write"),
        url = "https://example.invalid/mcp"
      ),
      "workspace-write"
    ),
    "must use stdio"
  )
  for (override in list(
    c("--config", "sandbox_mode=danger-full-access"),
    "--config=sandbox_mode=external-sandbox",
    c("--config", " sandbox_mode = 'inherit-codex' ")
  )) {
    expect_error(
      validate_mcp_repl_sandbox_server(
        list(
          command = "mcp-repl",
          args = c("--sandbox", "workspace-write", override)
        ),
        "workspace-write"
      ),
      "overriding sandbox mode"
    )
  }
  expect_identical(
    validate_mcp_repl_sandbox_server(
      list(
        command = "mcp-repl",
        args = c(
          "--sandbox",
          "workspace-write",
          "--config",
          "sandbox_workspace_write.network_access=false"
        )
      ),
      "workspace-write"
    ),
    "workspace-write"
  )
  expect_error(
    mcp_repl_control(NULL),
    "mcp_repl_connection",
    class = "deputy_mcp_repl"
  )
})

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

test_that("released mcp-repl preserves state, content, isolation and explicit controls", {
  executable <- Sys.getenv("DEPUTY_MCP_REPL_BIN")
  skip_if(
    !nzchar(executable),
    "Set DEPUTY_MCP_REPL_BIN to a qualified mcp-repl 0.3.0 executable"
  )
  skip_if_not_installed("mcptools", "1.0.2")
  skip_if(as.character(utils::packageVersion("mcptools")) != "1.0.2")
  workspace <- tempfile("deputy-repl-")
  dir.create(workspace)
  config <- tempfile(fileext = ".json")
  jsonlite::write_json(
    list(
      mcpServers = list(
        r = list(
          command = executable,
          args = list(
            "--interpreter",
            "r",
            "--sandbox",
            "workspace-write",
            "--add-writable-root",
            workspace,
            "--oversized-output",
            "files"
          )
        )
      )
    ),
    config,
    auto_unbox = TRUE
  )
  a <- Agent$new(chat = create_mock_chat(), working_dir = workspace)
  b <- Agent$new(chat = create_mock_chat(), working_dir = workspace)
  first <- mcp_repl_connection(config, a)
  withr::defer(first$close())
  second <- mcp_repl_connection(config, b)
  withr::defer(second$close())
  tool_a <- first$tools()$repl
  tool_b <- second$tools()$repl
  expect_identical(
    tool_metadata(tool_a)$source$execution,
    list(backend = "mcp-repl", sandbox = "workspace-write")
  )
  call <- function(tool, input, timeout_ms = 5000) {
    mcp_test_await(tool(input = input, timeout_ms = timeout_ms), timeout = 30)
  }
  expect_match(
    call(tool_a, "deputy_value <- 42; deputy_value"),
    "[1] 42",
    fixed = TRUE
  )
  expect_match(
    call(tool_b, 'exists("deputy_value")'),
    "[1] FALSE",
    fixed = TRUE
  )
  expect_match(call(tool_a, "deputy_value"), "[1] 42", fixed = TRUE)
  plot <- call(tool_a, 'plot(1:5, main = "Deputy MCP qualification")')
  expect_true(any(vapply(
    plot,
    inherits,
    logical(1),
    "ellmer::ContentImageInline"
  )))
  large <- call(tool_a, 'cat(rep("bounded evidence\\n", 2000))')
  expect_lt(nchar(large, type = "bytes"), 6000L)
  expect_match(large, "middle truncated", fixed = TRUE)
  full <- regmatches(large, regexec("full output: ([^]]+)]", large))[[1L]][[2L]]
  expect_true(file.exists(full))
  expect_gt(file.info(full)$size, nchar(large, type = "bytes"))
  busy <- call(tool_a, 'Sys.sleep(60); cat("unexpected completion")', 100)
  expect_match(busy, "repl status: busy", fixed = TRUE)
  interrupted <- mcp_test_await(
    mcp_repl_control(first, "interrupt"),
    timeout = 30
  )
  expect_false(grepl("repl status: busy", paste(interrupted), fixed = TRUE))
  expect_match(call(tool_a, "deputy_value"), "[1] 42", fixed = TRUE)
  reset <- mcp_test_await(mcp_repl_control(first, "reset"), timeout = 30)
  expect_match(reset, "new session started", fixed = TRUE)
  expect_match(
    call(tool_a, 'exists("deputy_value")'),
    "[1] FALSE",
    fixed = TRUE
  )
  ended <- call(tool_a, 'q(save = "no")')
  expect_match(ended, "session ended", fixed = TRUE)
  expect_match(
    call(tool_a, 'exists("deputy_value")'),
    "[1] FALSE",
    fixed = TRUE
  )
  first$close()
  expect_false(mcp_tool_is_current(tool_a))
  expect_error(tool_a(input = "1+1"), "closed")
  expect_match(call(tool_b, "1+1"), "[1] 2", fixed = TRUE)
})
