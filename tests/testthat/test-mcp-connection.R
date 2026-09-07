mcp_test_config <- function(capabilities = c("tools", "resources", "prompts")) {
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
            log,
            paste(capabilities, collapse = ",")
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
  for (cursor in c("", "  ")) {
    page <- mcp_test_await(connection$discover("resources", cursor = cursor))
    expect_identical(page$source$operation, "resources/list")
    expect_identical(page$result$resources[[1]]$uri, "fixture://denied")
  }
  for (topic in c("", "  ")) {
    blank <- mcp_test_await(connection$get_prompt(
      "summarize",
      list(topic = topic)
    ))
    expect_identical(
      blank$result$messages[[1]]$content$text,
      paste("Summarize empty", topic)
    )
  }
  for (invalid in list(1, NA_character_, character(), c("one", "two"), NULL)) {
    expect_error(
      connection$get_prompt("summarize", list(topic = invalid)),
      "argument"
    )
  }
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

test_that("resource-only and prompt-only servers need no tool catalogue", {
  for (capability in c("resources", "prompts")) {
    config <- mcp_test_config(capability)
    agent <- Agent$new(chat = create_mock_chat())
    arguments <- list(config = config$path, server = "fixture", agent = agent)
    arguments[[capability]] <- if (capability == "resources") {
      "fixture://allowed"
    } else {
      "summarize"
    }
    connection <- do.call(McpConnection$new, arguments)
    withr::defer(connection$close())
    expect_length(connection$tools(), 0L)
    expect_length(connection$capability_tools(), 1L)
    result <- if (capability == "resources") {
      mcp_test_await(connection$read_resource("fixture://allowed"))
    } else {
      mcp_test_await(connection$get_prompt(
        "summarize",
        list(topic = "evidence")
      ))
    }
    expect_identical(
      result$source$connection_id,
      connection$status()$connection_id
    )
    expect_true(is.list(mcp_test_await(connection$discover(capability))$result))
    expect_false(any(readLines(config$log) == "tools/list "))
    expect_equal(sum(readLines(config$log) == "initialize "), 1L)
    connection$close()
  }
})

test_that("host tool calls bind caller values and omit unsupplied arguments", {
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
  received <- local({
    operation <- "set"
    descriptor <- "caller value"
    forced <- 0L
    result <- mcp_test_await(tool(operation = operation, value = {
      forced <- forced + 1L
      descriptor
    }))
    expect_identical(forced, 1L)
    result
  })
  expect_match(paste(received), "caller value")
  expect_match(paste(mcp_test_await(tool(operation = "has_value"))), "FALSE")
  expect_match(
    paste(mcp_test_await(tool(operation = "has_value", value = "supplied"))),
    "TRUE"
  )
})

test_that("an intermediate startup condition does not replace initialization results", {
  noisy <- mcp_worker_start
  body(noisy) <- bquote({
    signalCondition(structure(
      list(message = "fixture startup message"),
      class = c("callr_message", "message", "condition")
    ))
    Sys.sleep(0.05)
    .(body(noisy))
  })
  local_mocked_bindings(mcp_worker_start = noisy)
  config <- mcp_test_config()
  agent <- Agent$new(chat = create_mock_chat())
  expect_message(
    connection <- McpConnection$new(
      config$path,
      "fixture",
      agent,
      tools = "state"
    ),
    "fixture startup message"
  )
  withr::defer(connection$close())
  expect_identical(connection$status()$state, "idle")
  expect_match(
    paste(mcp_test_await(connection$tools()$state(operation = "get"))),
    "empty"
  )
})

test_that("intermediate worker conditions do not settle or desynchronize requests", {
  noisy <- mcp_worker_request
  body(noisy) <- bquote({
    if (operation != "close") {
      signalCondition(structure(
        list(message = "fixture worker message"),
        class = c("callr_message", "message", "condition")
      ))
      Sys.sleep(0.05)
    }
    .(body(noisy))
  })
  local_mocked_bindings(mcp_worker_request = noisy)
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
  expect_message(
    result <- mcp_test_await(tool(operation = "set", value = "retained")),
    "fixture worker message"
  )
  expect_match(paste(result), "retained")
  expect_identical(connection$status()$state, "idle")
  expect_message(
    next_result <- mcp_test_await(tool(operation = "get")),
    "fixture worker message"
  )
  expect_match(paste(next_result), "retained")
  expect_identical(connection$status()$state, "idle")
})

test_that("one Agent can register resource and prompt tools from two connections", {
  first_config <- mcp_test_config()
  second_config <- mcp_test_config()
  agent <- Agent$new(
    chat = create_mock_chat(),
    permissions = Permissions(web = TRUE)
  )
  first <- McpConnection$new(
    first_config$path,
    "fixture",
    agent,
    resources = "fixture://allowed",
    prompts = "summarize"
  )
  withr::defer(first$close())
  second <- McpConnection$new(
    second_config$path,
    "fixture",
    agent,
    resources = "fixture://allowed",
    prompts = "summarize"
  )
  withr::defer(second$close())
  agent$register_tools(c(
    first$capability_tools(prefix = "first"),
    second$capability_tools(prefix = "second")
  ))
  expect_named(
    agent$get_tools(),
    c(
      "first_read_resource",
      "first_get_prompt",
      "second_read_resource",
      "second_get_prompt"
    )
  )
  for (prefix in c("first", "second")) {
    connection <- if (prefix == "first") first else second
    for (operation in c("read_resource", "get_prompt")) {
      tool <- agent$get_tools()[[paste(prefix, operation, sep = "_")]]
      result <- mcp_test_await(
        if (operation == "read_resource") {
          tool(uri = "fixture://allowed")
        } else {
          tool(name = "summarize")
        }
      )
      expect_identical(
        result$source$connection_id,
        connection$status()$connection_id
      )
    }
  }
  for (config in list(first_config, second_config)) {
    expect_equal(sum(readLines(config$log) == "resources/read "), 1L)
    expect_equal(sum(readLines(config$log) == "prompts/get "), 1L)
  }
  expect_error(
    first$capability_tools(prefix = "invalid prefix"),
    class = "deputy_mcp_connection"
  )
})

test_that("a clone cannot dispatch after loading a different owner context", {
  config <- mcp_test_config()
  agent <- Agent$new(chat = create_mock_chat())
  connection <- McpConnection$new(
    config$path,
    "fixture",
    agent,
    tools = "state"
  )
  withr::defer(connection$close())
  agent$register_tools(connection$tools())
  clone <- agent$clone()
  saved <- Agent$new(
    chat = create_mock_chat(),
    run_context = list(reader_id = "other-reader")
  )
  path <- tempfile(fileext = ".rds")
  saved$save_session(path)
  clone$load_session(path)
  before <- readLines(config$log)
  expect_error(
    clone$get_tools()$state(operation = "set", value = "wrong-owner"),
    "different Agent",
    class = "deputy_tool_registration"
  )
  expect_identical(readLines(config$log), before)
  expect_match(
    paste(mcp_test_await(connection$tools()$state(operation = "get"))),
    "empty"
  )
})

test_that("a run context override cannot dispatch through another owner binding", {
  config <- mcp_test_config()
  agent <- NULL
  denial <- NULL
  fixture <- create_shiny_tool_chat(
    "state",
    list(operation = "get"),
    execute = function(request) {
      denial <<- tryCatch(
        do.call(agent$get_tools()$state, request@arguments),
        error = identity
      )
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
  before <- readLines(config$log)
  agent$run_sync(
    "Read fixture state.",
    run_context = list(reader_id = "other-reader")
  )
  expect_s3_class(denial, "deputy_tool_registration")
  expect_identical(readLines(config$log), before)
  expect_match(
    paste(mcp_test_await(connection$tools()$state(operation = "get"))),
    "empty"
  )
})
